#!/bin/bash
# ======================================================================
#          ------- Custom Functions -------                            #
#  Space for adding custom functions so each repo can customize as.    #
#  needed.                                                             #
# ======================================================================

# Shared defaults — matches the ace-box roles and source repo
GITLAB_NAMESPACE="${GITLAB_NAMESPACE:-gitlab}"
GITLAB_CHART_VERSION="${GITLAB_CHART_VERSION:-9.4.0}"
GITLAB_ROOT_USER="${GITLAB_ROOT_USER:-root}"
GITLAB_GROUP_OTEL="${GITLAB_GROUP_OTEL:-Otel-App}"
GITLAB_GROUP_SUPPORT="${GITLAB_GROUP_SUPPORT:-Support}"

MIGRATE_DIR="${MIGRATE_DIR:-$REPO_PATH/.devcontainer/migrate}"

customFunction(){
  printInfoSection "This is a custom function that calculates 1 + 1"

  printInfo "1 + 1 = $(( 1 + 1 ))"

}

# Deploy dtpay — backend (backend-services:8080) + frontend (payment-frontend:80) in namespace dtusecase
# Frontend nginx (ConfigMap: frontend-nginx-config) proxies /api → http://backend-services:8080 within the cluster
deployDtpay() {
  printInfoSection "Deploying dtpay: backend (dtdemos-usecase) + frontend (payment-frontend)"
  kubectl create namespace dtusecase 2>/dev/null || true
  kubectl -n dtusecase apply -f "$FRAMEWORK_APPS_PATH/dtpay/manifests/dtpay.yaml"
  waitForAllReadyPods dtusecase
  registerApp "payment-frontend" "dtusecase" "payment-frontend" 80
  printInfo "dtpay deployed. Frontend URL: $(getAppURL payment-frontend)"
}

undeployDtpay() {
  printInfoSection "Undeploying dtpay"
  unregisterApp "payment-frontend" "dtusecase"
  kubectl delete ns dtusecase --force 2>/dev/null || true
}

# Run JMeter load test against dtpay — one-shot Kubernetes Job, auto-deletes after 60s
# Usage: runJmeterTest [version] [app_url]
#   version: v1.0 (default), v1.2, v1.3, v1.4, v2.0
#   app_url: bare hostname to override JVM_APP_URL (e.g. payment-frontend.dtusecase.svc.cluster.local)
#            defaults to auto-detected ingress URL via getAppURL
runJmeterTest() {
  local version="${1:-v1.0}"
  local app_url_override="${2:-}"
  local valid_versions="v1.0 v1.2 v1.3 v1.4 v2.0"

  if ! echo "$valid_versions" | grep -qw "$version"; then
    printWarn "Unknown version '$version'. Valid options: $valid_versions"
    return 1
  fi

  printInfoSection "Running JMeter load test against dtpay (image: domuharahap/jmeter-tester:$version)"

  local target_url
  if [ -n "$app_url_override" ]; then
    target_url="${app_url_override#http://}"
    target_url="${target_url#https://}"
    printInfo "JMeter target URL (override): $target_url"
  else
    target_url=$(getAppURL "payment-frontend" 2>/dev/null || echo "payment-frontend.127.0.0.1.sslip.io")
    # Strip any protocol prefix — JMeter manifest expects a bare hostname
    target_url="${target_url#http://}"
    target_url="${target_url#https://}"
    printInfo "JMeter target URL (auto-detected): $target_url"
  fi

  kubectl create namespace jmeter 2>/dev/null || true

  # Create dynatrace-creds secret in the jmeter namespace from the codespace env vars.
  # DT_ENVIRONMENT and DT_OPERATOR_TOKEN are injected by Codespaces secrets at startup.
  # Secrets are namespace-scoped — the dynatrace namespace secret cannot be read here.

  # Normalize DT_ENVIRONMENT: strip trailing slash, replace .apps.dynatrace.com → .live.dynatrace.com
  local dt_env="${DT_ENVIRONMENT:-}"
  dt_env="${dt_env%/}"
  if echo "$dt_env" | grep -q '\.apps\.dynatrace\.com'; then
    local dt_env_fixed="${dt_env/.apps.dynatrace.com/.live.dynatrace.com}"
    printWarn "DT_ENVIRONMENT uses 'apps' domain — rewriting to 'live': $dt_env_fixed"
    dt_env="$dt_env_fixed"
  fi

  kubectl -n jmeter create secret generic dynatrace-creds \
    --from-literal="DT_ENVIRONMENT=${dt_env}" \
    --from-literal="DT_OPERATOR_TOKEN=${DT_OPERATOR_TOKEN:-}" \
    --dry-run=client -o yaml | kubectl apply -f -

  # Delete any prior run before re-submitting
  kubectl delete job jmeter-tester -n jmeter 2>/dev/null || true

  # Patch image and env vars locally before applying — Job spec.template is immutable
  # once created, so all overrides must be baked in before the first kubectl apply.
  local manifest="$FRAMEWORK_APPS_PATH/jmeter-tester/manifests/jmeter-job.yaml"
  kubectl set image --local -f "$manifest" \
    jmeter-tester="domuharahap/jmeter-tester:$version" -o yaml \
    | kubectl set env --local -f - JVM_APP_URL="$target_url" -o yaml \
    | kubectl apply -n jmeter -f -

  printInfo "JMeter job submitted (version $version, target: $target_url). Waiting for pod to start..."

  # Wait up to 2 minutes for the pod to reach Running state
  local timeout=120
  local elapsed=0
  local pod_phase=""
  local pod_name=""
  while [ $elapsed -lt $timeout ]; do
    pod_name=$(kubectl get pod -n jmeter -l app=jmeter-tester -o jsonpath='{.items[0].metadata.name}' 2>/dev/null)
    if [ -n "$pod_name" ]; then
      pod_phase=$(kubectl get pod -n jmeter "$pod_name" -o jsonpath='{.status.phase}' 2>/dev/null)
      if [ "$pod_phase" = "Running" ]; then
        break
      fi
    fi
    sleep 3
    elapsed=$(( elapsed + 3 ))
  done

  if [ "$pod_phase" = "Running" ]; then
    printInfo "JMeter test is RUNNING (pod: $pod_name, target: $target_url)"
    printInfo "Follow logs: kubectl logs -n jmeter $pod_name --follow"
    printInfo "Stop test:   stopJmeterTest"
    printInfo "The job will auto-delete 60s after completion."
  else
    printWarn "Pod did not reach Running state within ${timeout}s (phase: ${pod_phase:-unknown})"
    printWarn "Check: kubectl describe pod -n jmeter -l app=jmeter-tester"
  fi
}

stopJmeterTest() {
  printInfoSection "Stopping JMeter test"
  kubectl delete job jmeter-tester -n jmeter 2>/dev/null || true
  kubectl delete ns jmeter --force 2>/dev/null || true
}

# ----------------------------------------------------------------------
# GitLab — install via official helm chart on sslip.io magic domain
# ----------------------------------------------------------------------
installGitlab(){
  printInfoSection "Installing GitLab (helm chart $GITLAB_CHART_VERSION) in namespace '$GITLAB_NAMESPACE'"

  local ip domain root_password
  ip=$(detectIP)
  domain="${ip}.${MAGIC_DOMAIN:-sslip.io}"

  kubectl create namespace "$GITLAB_NAMESPACE" 2>/dev/null || true

  # Generate root password once, persist as k8s secret so reruns reuse it
  if kubectl -n "$GITLAB_NAMESPACE" get secret ace-gitlab-initial-root-password &>/dev/null; then
    root_password=$(kubectl -n "$GITLAB_NAMESPACE" get secret ace-gitlab-initial-root-password \
      -o jsonpath='{.data.password}' | base64 -d)
    printInfo "Reusing existing gitlab root password"
  else
    root_password=$(head -c 18 /dev/urandom | base64 | tr -d '/+=' | head -c 24)
    kubectl -n "$GITLAB_NAMESPACE" create secret generic ace-gitlab-initial-root-password \
      --from-literal="username=$GITLAB_ROOT_USER" \
      --from-literal="password=$root_password"
    printInfo "Created gitlab root password secret"
  fi

  helm repo add gitlab https://charts.gitlab.io/ >/dev/null
  helm repo update >/dev/null

  printInfo "Installing gitlab — ingress domain: gitlab.${domain}"
  helm upgrade --install gitlab gitlab/gitlab \
    --namespace "$GITLAB_NAMESPACE" \
    --version "$GITLAB_CHART_VERSION" \
    --wait --timeout 30m \
    --set "global.hosts.domain=${domain}" \
    --set "global.hosts.https=false" \
    --set "global.appConfig.initialDefaults.signupEnabled=false" \
    --set "global.ingress.provider=nginx" \
    --set "global.ingress.configureCertmanager=false" \
    --set "global.ingress.class=nginx" \
    --set "global.ingress.tls.enabled=false" \
    --set "global.initialRootPassword.secret=ace-gitlab-initial-root-password" \
    --set "global.initialRootPassword.key=password" \
    --set "installCertmanager=false" \
    --set "certmanager.install=false" \
    --set "nginx-ingress.enabled=false" \
    --set "gitlab-runner.rbac.create=true" \
    --set "gitlab-runner.rbac.clusterWideAccess=true" \
    --set "gitlab-runner.gitlabUrl=http://gitlab.${domain}" \
    --set "registry.enabled=false" \
    --set "global.kas.enabled=false" \
    --set "gitlab-exporter.enabled=false" \
    --set "gitlab.toolbox.enabled=false" \
    --set "prometheus.install=false" \
    --set "postgresql.primary.persistence.enabled=false" \
    --set "redis.master.persistence.enabled=false" \
    --set "minio.persistence.enabled=false"

  local endpoint
  endpoint=$(_gitlabInternalEndpoint)
  printInfo "Waiting for gitlab API at ${endpoint}/api/v4/projects to respond"
  local RETRY=0 RETRY_MAX=60 http_code=""
  while [[ $RETRY -lt $RETRY_MAX ]]; do
    http_code=$(curl -sk -o /dev/null -w '%{http_code}' "${endpoint}/api/v4/projects" 2>/dev/null || echo "000")
    if [[ "$http_code" == "200" ]]; then
      printInfo "GitLab API is up (HTTP $http_code)"
      break
    fi
    RETRY=$((RETRY + 1))
    printWarn "Retry: ${RETRY}/${RETRY_MAX} - Wait 10s for GitLab API (last HTTP $http_code) ..."
    sleep 10
  done
  if [[ $RETRY -eq $RETRY_MAX ]]; then
    printError "GitLab API at ${endpoint} did not respond with 200 within $((RETRY_MAX * 10))s"
    return 1
  fi

  # Generate + persist a Personal Access Token for API/git operations
  _gitlabEnsurePat

  # Wide-open RBAC like the source repo, so CI runners can do anything
  kubectl create clusterrolebinding gitlab-cluster-admin \
    --clusterrole=cluster-admin --group=system:serviceaccounts 2>/dev/null || true

  # Register GitLab in the app registry and expose it on a dedicated port
  _registerGitlabApp "$domain"
  printInfo "GitLab available at: http://gitlab.${domain}"
  printInfo "GitLab Codespaces URL: $(getAppURL gitlab 8929)"
  printInfo "Root credentials: $GITLAB_ROOT_USER / $root_password"
}

uninstallGitlab(){
  printInfoSection "Uninstalling GitLab"
  pkill -f "kubectl port-forward.*gitlab-webservice-default.*8929" 2>/dev/null || true
  helm uninstall gitlab -n "$GITLAB_NAMESPACE" 2>/dev/null || true
  kubectl delete namespace "$GITLAB_NAMESPACE" 2>/dev/null || true
  if [[ -f "$APP_REGISTRY" ]]; then
    grep -v "^gitlab|" "$APP_REGISTRY" > "${APP_REGISTRY}.tmp" 2>/dev/null || true
    mv "${APP_REGISTRY}.tmp" "$APP_REGISTRY" 2>/dev/null || true
  fi
}

# ----------------------------------------------------------------------
# GitLab — app registry + Codespaces port exposure
# ----------------------------------------------------------------------
_registerGitlabApp() {
  # Registers GitLab in the app registry so it appears in the greeting.
  # On Codespaces: starts a background port-forward on port 8929 so the
  # GitLab web UI is accessible at https://${CODESPACE_NAME}-8929.app.github.dev
  # without relying on the nginx ingress Host-header routing.
  local domain="$1"
  local ingress_host="gitlab.${domain}"
  local cs_port=8929

  # Kill any stale port-forward before starting a fresh one
  pkill -f "kubectl port-forward.*gitlab-webservice-default.*8929" 2>/dev/null || true
  nohup kubectl port-forward -n "$GITLAB_NAMESPACE" svc/gitlab-webservice-default \
    "${cs_port}:8080" --address 0.0.0.0 >/dev/null 2>&1 &
  printInfo "GitLab port-forward started on :${cs_port} → gitlab-webservice-default:8080"

  mkdir -p "$(dirname "$APP_REGISTRY")"
  grep -v "^gitlab|" "$APP_REGISTRY" > "${APP_REGISTRY}.tmp" 2>/dev/null || true
  mv "${APP_REGISTRY}.tmp" "$APP_REGISTRY" 2>/dev/null || true
  echo "gitlab|${GITLAB_NAMESPACE}|gitlab-webservice-default|8080|${ingress_host}|${cs_port}|" >> "$APP_REGISTRY"
  printInfo "GitLab registered in app registry (ingress: ${ingress_host}, cs-port: ${cs_port})"
}

# ----------------------------------------------------------------------
# GitLab — internal helpers (REST API + auth)
# ----------------------------------------------------------------------
_gitlabInternalEndpoint(){
  # Host-reachable ingress URL — the ClusterIP from gitlab-webservice-default
  # isn't routable from the dev container, so we use the sslip.io magic domain.
  local ip
  ip=$(detectIP)
  echo "http://gitlab.${ip}.${MAGIC_DOMAIN:-sslip.io}"
}

_gitlabRootPassword(){
  kubectl -n "$GITLAB_NAMESPACE" get secret ace-gitlab-initial-root-password \
    -o jsonpath='{.data.password}' 2>/dev/null | base64 -d
}

_gitlabEnsurePat(){
  # If PAT already exists in k8s, source it; otherwise create via OAuth -> PAT
  if kubectl -n "$GITLAB_NAMESPACE" get secret ace-gitlab-root-pat &>/dev/null; then
    GITLAB_PAT=$(kubectl -n "$GITLAB_NAMESPACE" get secret ace-gitlab-root-pat \
      -o jsonpath='{.data.personalAccessToken}' | base64 -d)
    printInfo "Reusing existing gitlab PAT"
    return 0
  fi

  local endpoint password oauth_token pat
  endpoint=$(_gitlabInternalEndpoint)
  password=$(_gitlabRootPassword)

  oauth_token=$(curl -sk -X POST "${endpoint}/oauth/token" \
    -H "Content-Type: application/json" \
    -d "{\"grant_type\":\"password\",\"username\":\"${GITLAB_ROOT_USER}\",\"password\":\"${password}\"}" \
    | sed -n 's/.*"access_token":"\([^"]*\)".*/\1/p')

  if [ -z "$oauth_token" ]; then
    printError "Could not get GitLab OAuth token"
    return 1
  fi

  pat=$(curl -sk -X POST "${endpoint}/api/v4/users/1/personal_access_tokens" \
    -H "Content-Type: application/json" \
    -H "Authorization: Bearer ${oauth_token}" \
    -d '{"name":"ace-box-pat","scopes":["api","read_api","read_user","read_repository","write_repository","sudo","admin_mode"]}' \
    | sed -n 's/.*"token":"\([^"]*\)".*/\1/p')

  if [ -z "$pat" ]; then
    printError "Could not create GitLab PAT"
    return 1
  fi

  kubectl -n "$GITLAB_NAMESPACE" create secret generic ace-gitlab-root-pat \
    --from-literal="personalAccessToken=$pat"
  GITLAB_PAT="$pat"
  printInfo "Created and persisted GitLab PAT"
}

_gitlabEnsureGroup(){
  # Usage: _gitlabEnsureGroup <group_name>
  # Echoes the group ID on stdout; logs go to stderr so callers can capture
  # the ID cleanly via $(...).
  local name="$1" endpoint id
  endpoint=$(_gitlabInternalEndpoint)

  id=$(curl -sk -H "Authorization: Bearer ${GITLAB_PAT}" \
    "${endpoint}/api/v4/groups?search=$(printf %s "$name" | jq -sRr @uri)" \
    | jq -r ".[] | select(.name==\"$name\") | .id" | head -n1)

  if [ -z "$id" ] || [ "$id" = "null" ]; then
    id=$(curl -sk -X POST "${endpoint}/api/v4/groups" \
      -H "Content-Type: application/json" \
      -H "Authorization: Bearer ${GITLAB_PAT}" \
      -d "{\"path\":\"$name\",\"name\":\"$name\",\"visibility\":\"public\"}" \
      | jq -r '.id')
    printInfo "Created group '$name' (id=$id)" >&2
  else
    printInfo "Group '$name' already exists (id=$id)" >&2
  fi
  echo "$id"
}

_gitlabEnsureProject(){
  # Usage: _gitlabEnsureProject <project_name> <namespace_id>
  # Echoes the project ID on stdout; logs go to stderr so callers can capture
  # the ID cleanly via $(...).
  local name="$1" ns_id="$2" endpoint id
  endpoint=$(_gitlabInternalEndpoint)

  id=$(curl -sk -H "Authorization: Bearer ${GITLAB_PAT}" \
    "${endpoint}/api/v4/projects?search=$(printf %s "$name" | jq -sRr @uri)" \
    | jq -r ".[] | select(.name==\"$name\") | select(.namespace.id==$ns_id) | .id" | head -n1)

  if [ -z "$id" ] || [ "$id" = "null" ]; then
    id=$(curl -sk -X POST "${endpoint}/api/v4/projects" \
      -H "Content-Type: application/json" \
      -H "Authorization: Bearer ${GITLAB_PAT}" \
      -d "{\"name\":\"$name\",\"namespace_id\":$ns_id,\"visibility\":\"public\"}" \
      | jq -r '.id')
    printInfo "  Created project '$name' (id=$id)" >&2
  else
    printInfo "  Project '$name' already exists (id=$id)" >&2
  fi
  echo "$id"
}

_gitlabPushRepo(){
  # Usage: _gitlabPushRepo <local_dir> <group> <project_name> [branch]
  local src="$1" group="$2" repo="$3" branch="${4:-main}"
  local endpoint host password
  endpoint=$(_gitlabInternalEndpoint)
  host="${endpoint#http://}"
  password=$(_gitlabRootPassword)

  if [ ! -d "$src" ] || [ -z "$(ls -A "$src" 2>/dev/null)" ]; then
    printWarn "  Skipping push for '$repo' — source dir '$src' empty/missing"
    return 0
  fi

  ( cd "$src"
    if [ ! -d .git ]; then
      git init -q -b "$branch"
      git config user.email "ace-box@local"
      git config user.name  "ace-box"
      git add .
      git commit -q -m "Initial commit for branch $branch" || true
    fi
    git remote remove gitlab 2>/dev/null || true
    git remote add gitlab "http://${GITLAB_ROOT_USER}:${password}@${host}/${group}/${repo}.git"
    git push -q gitlab "$branch" 2>&1 | sed 's/^/    /' || \
      printWarn "  Push of $repo failed (may already be populated)"
  )
}

# ----------------------------------------------------------------------
# GitLab — seed groups and push local repos
# ----------------------------------------------------------------------
seedGitlabRepos(){
  printInfoSection "Seeding GitLab repositories from $MIGRATE_DIR"

  if [ -z "$GITLAB_PAT" ]; then
    _gitlabEnsurePat || return 1
  fi

  # Support group (3 repos: monaco, automated load test, manual release)
  local support_id
  support_id=$(_gitlabEnsureGroup "$GITLAB_GROUP_SUPPORT")
  local s
  for s in dynatrace_env_automation automated_load_test astroshop_release_repo; do
    _gitlabEnsureProject "$s" "$support_id" >/dev/null
    _gitlabPushRepo "$MIGRATE_DIR/support_repos/$s" "$GITLAB_GROUP_SUPPORT" "$s"
  done

  # Otel-App group (all astroshop service repos)
  local otel_id
  otel_id=$(_gitlabEnsureGroup "$GITLAB_GROUP_OTEL")
  local r
  for r in "$MIGRATE_DIR"/astroshop_repos/*/; do
    [ -d "$r" ] || continue
    local name
    name=$(basename "$r")
    _gitlabEnsureProject "$name" "$otel_id" >/dev/null
    _gitlabPushRepo "$r" "$GITLAB_GROUP_OTEL" "$name"
  done

  printInfo "GitLab seeding complete"
}

# ----------------------------------------------------------------------
# SonarQube — install Community Edition via official helm chart
# ----------------------------------------------------------------------
SONARQUBE_NAMESPACE="${SONARQUBE_NAMESPACE:-sonarqube}"
SONARQUBE_MONITORING_PASSCODE="${SONARQUBE_MONITORING_PASSCODE:-dynatr@c3}"
SONARQUBE_PORT=9000

installSonarqube() {
  printInfoSection "Installing SonarQube (Community Edition) in namespace '$SONARQUBE_NAMESPACE'"

  helm repo add sonarqube https://SonarSource.github.io/helm-chart-sonarqube >/dev/null
  helm repo update >/dev/null

  kubectl create namespace "$SONARQUBE_NAMESPACE" 2>/dev/null || true

  helm upgrade --install sonarqube sonarqube/sonarqube \
    --namespace "$SONARQUBE_NAMESPACE" \
    --wait --timeout 15m \
    --set "monitoringPasscode=${SONARQUBE_MONITORING_PASSCODE}" \
    --set "edition=" \
    --set "community.enabled=true"

  printInfo "Waiting for SonarQube pods to be ready..."
  waitForAllReadyPods "$SONARQUBE_NAMESPACE"

  _registerSonarqubeApp
  printInfo "SonarQube available at: $(getAppURL sonarqube $SONARQUBE_PORT)"
  printInfo "Default credentials: admin / admin (change on first login)"
}

uninstallSonarqube() {
  printInfoSection "Uninstalling SonarQube"
  pkill -f "kubectl port-forward.*sonarqube.*${SONARQUBE_PORT}" 2>/dev/null || true
  helm uninstall sonarqube -n "$SONARQUBE_NAMESPACE" 2>/dev/null || true
  kubectl delete namespace "$SONARQUBE_NAMESPACE" 2>/dev/null || true
  if [[ -f "$APP_REGISTRY" ]]; then
    grep -v "^sonarqube|" "$APP_REGISTRY" > "${APP_REGISTRY}.tmp" 2>/dev/null || true
    mv "${APP_REGISTRY}.tmp" "$APP_REGISTRY" 2>/dev/null || true
  fi
}

_registerSonarqubeApp() {
  # Exposes SonarQube via ingress and a Codespaces port-forward on port 9000.
  local ip domain ingress_host cs_port
  ip=$(detectIP)
  domain="${ip}.${MAGIC_DOMAIN:-sslip.io}"
  ingress_host="sonarqube.${domain}"
  cs_port="$SONARQUBE_PORT"

  pkill -f "kubectl port-forward.*sonarqube.*${cs_port}" 2>/dev/null || true
  nohup kubectl port-forward -n "$SONARQUBE_NAMESPACE" svc/sonarqube-sonarqube \
    "${cs_port}:9000" --address 0.0.0.0 >/dev/null 2>&1 &
  printInfo "SonarQube port-forward started on :${cs_port} → sonarqube-sonarqube:9000"

  mkdir -p "$(dirname "$APP_REGISTRY")"
  grep -v "^sonarqube|" "$APP_REGISTRY" > "${APP_REGISTRY}.tmp" 2>/dev/null || true
  mv "${APP_REGISTRY}.tmp" "$APP_REGISTRY" 2>/dev/null || true
  echo "sonarqube|${SONARQUBE_NAMESPACE}|sonarqube-sonarqube|9000|${ingress_host}|${cs_port}|" >> "$APP_REGISTRY"
  printInfo "SonarQube registered in app registry (ingress: ${ingress_host}, cs-port: ${cs_port})"
}





