--8<-- "snippets/dt-enablement.md"

# Use Case 5 — Dev/Prod Gates

The pipeline builds, tests, scans, containerizes, deploys to dev, and load-tests itself. The last piece: a **separate production environment** that only ever receives a build that already passed the load test — and a manual approval step, since promoting to prod should be a deliberate human decision, not an automatic one.

---

## 1. Look at the prod ingress

`manifests/ingress-prod.yaml` already ships in the repo. Unlike the dev ingress, it has **no catch-all rule** — on purpose, so it never competes with dev for the Codespace's port-80 forward. You'll reach prod with a `Host` header instead of a plain browser URL:

```yaml title="manifests/ingress-prod.yaml" linenums="1"
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: kkm-pulse-prod-ingress
  namespace: kkm-pulse-prod
  annotations:
    nginx.ingress.kubernetes.io/proxy-read-timeout: "3600"
    nginx.ingress.kubernetes.io/proxy-send-timeout: "3600"
spec:
  ingressClassName: nginx
  rules:
    - host: kkm-pulse-prod.127.0.0.1.sslip.io
      http:
        paths:
          - path: /
            pathType: Prefix
            backend:
              service:
                name: kkm-pulse-demo
                port:
                  number: 3000
```

---

## 2. Add the `deploy_prod` stage

```yaml title=".gitlab-ci.yaml (append)" linenums="1"
stages:
  - build
  - test
  - code_quality
  - package
  - deploy_dev
  - load_test
  - deploy_prod

deploy-prod:
  stage: deploy_prod
  tags:
    - shell
  needs:
    - notify-dynatrace-test-result
  when: manual
  environment:
    name: production
    url: http://kkm-pulse-prod.127.0.0.1.sslip.io
  script:
    - kubectl create namespace kkm-pulse-prod --dry-run=client -o yaml | kubectl apply -f -
    - sed -e "s#__NAMESPACE__#kkm-pulse-prod#" -e "s#__IMAGE__#kkm-pulse-demo:${CI_COMMIT_SHORT_SHA}#" manifests/deployment.yaml | kubectl apply -f -
    - kubectl apply -f manifests/ingress-prod.yaml
    - kubectl rollout status deployment/kkm-pulse-demo -n kkm-pulse-prod --timeout=120s
    - 'curl -sf -H "Host: kkm-pulse-prod.127.0.0.1.sslip.io" http://localhost/api/status'

notify-dynatrace-prod-deploy:
  stage: deploy_prod
  tags:
    - shell
  needs:
    - deploy-prod
  script:
    - DT_TENANT=$(echo "$DT_ENVIRONMENT" | sed -E 's/\.apps\./.live./; s#/$##')
    - >
      curl -sf -X POST "${DT_TENANT}/api/v2/events/ingest"
      -H "Authorization: Api-Token ${DT_INGEST_TOKEN}"
      -H "Content-Type: application/json"
      -d "{\"eventType\":\"CUSTOM_DEPLOYMENT\",\"title\":\"kkm-pulse-demo deployed to PRODUCTION\",\"properties\":{\"dt.event.deployment.name\":\"kkm-pulse-demo\",\"version\":\"${CI_COMMIT_SHORT_SHA}\",\"environment\":\"prod\"}}"
```

```bash
git add manifests/ingress-prod.yaml .gitlab-ci.yaml
git commit -m "ci: add gated production deployment"
git push
```

### Why this is a real gate, not decoration

- `deploy-prod` declares `needs: [notify-dynatrace-test-result]`. In GitLab CI, a `needs` dependency must **succeed** before the dependent job is even offered — `notify-dynatrace-test-result` is the job from Use Case 4 that `exit 1`s when the load test's error rate exceeds 10%.
- `when: manual` means even a passing pipeline **pauses** at `deploy_prod` — someone has to click ▶️ in the GitLab UI. This models a real approval gate (release manager, change board, whoever you'd want signing off in your org).
- Put both together: a bad build can never reach the manual button, and a good build never ships to prod by accident.

---

## 3. Watch the gate work — twice

### A passing run

1. Push a normal change, watch the pipeline run through `load_test`
2. In **CI/CD → Pipelines**, open the pipeline — `deploy-prod` appears in the graph with a ▶️ (manual) icon, available to click
3. Click it, confirm `kkm-pulse-prod` comes up:

    ```bash
    kubectl get all -n kkm-pulse-prod
    curl -H "Host: kkm-pulse-prod.127.0.0.1.sslip.io" http://localhost/api/status
    ```

### A failing run — prove the gate actually blocks

Temporarily break the app on purpose. Edit `server.js`'s `/api/status` handler to always fail:

```js
app.get('/api/status', (req, res) => {
    res.status(500).json({ error: "simulated failure for the workshop" });
});
```

```bash
git add server.js
git commit -m "chore: simulate a bad build"
git push
```

Watch what happens:

- `deploy-dev` still succeeds — Kubernetes doesn't know the *content* of the response is wrong, only that the process is running
- `load-test` records a 100% error rate
- `notify-dynatrace-test-result` fails the error-budget check and exits non-zero
- `deploy_prod` never appears as an available stage — there is no ▶️ button to click

Check the events feed in Dynatrace too — you'll see the dev `CUSTOM_DEPLOYMENT` and the `CUSTOM_INFO` load-test-result event with `error_rate_pct: 100`, but no production deployment event, because it never ran.

Revert the change once you've seen it:

```bash
git revert HEAD --no-edit
git push
```

---

## Recap

Across five use cases you took `kkm-pulse-demo` from zero to a pipeline that:

1. Builds and tests on every push (Use Case 2)
2. Statically scans the code and enforces a SonarQube quality gate (Use Case 2)
3. Packages a Docker image and deploys it to Kubernetes with no external registry (Use Case 3)
4. Reports every deployment and load-test result to Dynatrace as an event, and gets validated against Davis AI anomaly detection (Use Case 4)
5. Separates dev and prod, and structurally cannot promote a build that failed its load test (Use Case 5)

Use Case 6 goes further: Dynatrace's Site Reliability Guardian validates production against KPI and security objectives *after* deployment, and a Dynatrace Workflow automatically calls back the pipeline to trigger a rollback when production degrades.

<div class="grid cards" markdown>
- [Continue to Use Case 6 — SRG & Automated Rollback :octicons-arrow-right-24:](usecase6-srg-workflow.md)
</div>
