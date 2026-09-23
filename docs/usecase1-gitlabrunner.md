--8<-- "snippets/dt-enablement.md"

# Use Case 1 — First GitLab Project & Runner

In this use case you will create your first project on **GitLab.com**, connect your Codespace to it over SSH, and install your own **GitLab Runner** directly inside the Codespace so it can execute pipelines against the Kubernetes cluster and Docker daemon already running there.

---

## 1. Create your first GitLab project

!!! example "Step-by-step"
    1. Log in to [gitlab.com](https://gitlab.com) (or create a free account)
    2. Click **Create new... → New project/repository → Create blank project**
    3. Project name: `firstproject`, visibility: your choice (Private is fine)
    4. Leave "Initialize repository with a README" **checked**, then **Create project**

---

## 2. Connect your Codespace to GitLab over SSH

### Generate an SSH key in the Codespace

```bash
ssh-keygen -t ed25519 -C "$(git config --global user.email || echo codespace)"
```

Press **Enter** through the prompts to accept the defaults (no passphrase needed for a throwaway Codespace).

### Copy the public key into GitLab

```bash
cat ~/.ssh/id_ed25519.pub
```

1. In GitLab, click your avatar → **Edit profile** → **SSH Keys** (or go directly to **User Settings → SSH Keys**)
2. Click **Add new key**, paste the output above into **Key**, give it a title, and click **Add key**

### Clone the project into the Codespace

```bash
git clone git@gitlab.com:<your-gitlab-username>/firstproject.git
cd firstproject
```

---

## 3. Create your first pipeline

Create a `.gitlab-ci.yaml` file at the root of the project:

```bash
cat <<'EOF' > .gitlab-ci.yaml
# My first GitLab CI pipeline
stages:
  - build
  - deploy

build-job:
  stage: build
  tags:
    - shell
  script:
    - echo "Hello, $USER!"
    - echo "compile my first project"
    - echo "compile completed"

deploy-job:
  stage: deploy
  tags:
    - shell
  script:
    - echo "Deploying application..."
    - echo "Application successfully deployed."
EOF
```

Commit and push:

```bash
git add .gitlab-ci.yaml
git commit -m "my first gitlab pipeline"
git push
```

!!! info "Nothing will run yet"
    Open **CI/CD → Pipelines** in GitLab and you'll see the pipeline stuck **pending** — there is no runner registered against this project yet. That's what the rest of this use case fixes.

---

## 4. Install GitLab Runner inside the Codespace

The Codespace already has Docker, `kubectl`, `k3d`, and Node.js installed and a k3d cluster running — installing the runner as a **shell executor** lets every pipeline job use those tools directly, with no extra Docker-in-Docker setup.

```bash
# Download the binary for the codespace's architecture (amd64 shown; use arm64 on Apple Silicon)
sudo curl -L --output /usr/local/bin/gitlab-runner \
  https://gitlab-runner-downloads.s3.amazonaws.com/latest/binaries/gitlab-runner-linux-amd64

# Give it permission to execute
sudo chmod +x /usr/local/bin/gitlab-runner

# Create a dedicated GitLab Runner user
sudo useradd --comment 'GitLab Runner' --create-home gitlab-runner --shell /bin/bash
```

### Give the runner access to Docker and the cluster

Pipeline jobs will run `docker build` and `kubectl apply` as the `gitlab-runner` Linux user — it needs the same Docker group membership and kubeconfig your own `vscode` user already has.

```bash
# Let gitlab-runner talk to the Docker socket
sudo usermod -aG docker gitlab-runner

# Share the kubeconfig so gitlab-runner can reach the k3d-enablement cluster
sudo mkdir -p /home/gitlab-runner/.kube
sudo cp ~/.kube/config /home/gitlab-runner/.kube/config
sudo chown -R gitlab-runner:gitlab-runner /home/gitlab-runner/.kube
```

### Install and start the runner service

```bash
sudo gitlab-runner install --user=gitlab-runner --working-directory=/home/gitlab-runner
sudo gitlab-runner start
```

!!! tip "Group membership needs a restart"
    `usermod -aG docker` only takes effect for **new** processes. Since you ran it before `gitlab-runner start`, the service picks it up immediately. If you ever add the group *after* the service is already running, restart it with `sudo gitlab-runner restart`.

---

## 5. Register the runner against your project

GitLab.com no longer uses the old shared "registration token" — you create the runner in the UI first and get a one-time **authentication token** (`glrt-...`).

!!! example "Step-by-step"
    1. In your `firstproject` GitLab project, go to **Settings → CI/CD → Runners**
    2. Click **New project runner**
    3. Tags: enter `shell` (matches the tag used by the jobs above); check **"Run untagged jobs"** if you want it to also pick up jobs with no tags
    4. Click **Create runner**, then copy the registration command shown — specifically the `--token glrt-...` value

Register it non-interactively from the Codespace terminal:

```bash
sudo gitlab-runner register \
  --non-interactive \
  --url "https://gitlab.com/" \
  --token "<glrt-...-paste-your-token-here>" \
  --executor "shell" \
  --description "codespace-shell-runner" \
  --tag-list "shell,docker,codespace"
```

Verify it's alive:

```bash
sudo gitlab-runner list
sudo gitlab-runner verify
```

Back in GitLab, **Settings → CI/CD → Runners** should now show your runner as **online**.

---

## 6. Watch the pipeline run

Re-run the pipeline from **CI/CD → Pipelines → Run pipeline**, or push an empty commit:

```bash
git commit --allow-empty -m "trigger pipeline"
git push
```

Both `build-job` and `deploy-job` should turn green. Click into a job to see its log.

---

## Understanding runner tags

Tags decide which jobs a runner is allowed to pick up. The runner you just registered is tagged `shell, docker, codespace`. A job only runs on a runner if **every tag the job lists** is also a tag the runner has (the runner is free to have *more* tags than the job asks for).

| | Runner tags | Job tags | Runs? |
|---|---|---|---|
| Example 1 | `[docker, shell, codespace]` | `[shell]` | ✅ yes — the job's one required tag is a subset of the runner's tags |
| Example 2 | `[docker, shell, codespace]` | `[docker, shell, codespace]` | ✅ yes — exact match |
| Example 3 | `[docker, shell, codespace]` | `[docker, shell, k8s]` | ❌ no — `k8s` isn't one of the runner's tags, so it stays **pending** forever unless another runner has it |

Keep this in mind for later use cases — every job you add must use a tag your runner actually has (we'll standardize on `shell`).

<div class="grid cards" markdown>
- [Continue to Use Case 2 — Node.js CI, Test & SAST :octicons-arrow-right-24:](usecase2-nodejs-sast.md)
</div>
