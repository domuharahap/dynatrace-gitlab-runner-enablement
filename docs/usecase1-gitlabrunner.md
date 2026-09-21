## 1. Create first Project in Gitlab

1. **Log in to the GitLab UI.**
Create Project
2. **Generate ssh key in codespace**
```
ssh-keygen
```

get the key generated and copy to Gitlab
```
home/vscode/.ssh/id_<REPLACE_GENERATED_ID>/*.pub
```

3. **Copy the output ssh key into Gitlab SSH key**

4. **Clone the Project created in codespace**
```
git clone
```

5. **Add my first file into Gitlab projecte**
 
``` 
### Create File
cat <<EOF > .gitlab-ci.yaml
# My first Gitlab CI
stage:
 - build
 - deploy

build-job
 - stage: build
 - script:
    - echo "Hello, $USER!"
    - echo "compile my first project"
    - echo "compile completed"
deploy-job
 - stage: deploy
 - script:
    - echo "Deploying application..."
    - echo "Application successfully deployed." 
EOF
```
6. **Git Add, Commit, push**
``` 
#
git add .
git commit -m "my first gitlab project"
git push
```

## install Gitlab Runner on codespace

```
# Download the binary for your system
sudo curl -L --output /usr/local/bin/gitlab-runner https://gitlab-runner-downloads.s3.amazonaws.com/latest/binaries/gitlab-runner-linux-amd64

# Give it permission to execute
sudo chmod +x /usr/local/bin/gitlab-runner

# Create a GitLab Runner user
sudo useradd --comment 'GitLab Runner' --create-home gitlab-runner --shell /bin/bash

# Install and run as a service
sudo gitlab-runner install --user=gitlab-runner --working-directory=/home/gitlab-runner
sudo gitlab-runner start
```

Example 1:

The runner is configured with the tags [docker, shell, codespace].
The job has the tags [shell] and is executed and run.
Example 2:

The runner is configured with the tags [docker, shell, codespace].
The job has the tags [docker, shell, codespace] and is executed and run.
Example 3:

The runner is configured with the tags [docker, shell, codespace].
The job has the tags [docker, shell, k8s] and is not executed.

## Install SonarQube (Code Quality Gate)

SonarQube Community Edition can be installed into the Kubernetes cluster with a single command using the built-in function.

### Option A — One-command install (recommended)

Run this from the codespace terminal:

```bash
installSonarqube
```

This will:
1. Add the SonarQube helm repo and update it
2. Create the `sonarqube` namespace
3. Deploy SonarQube Community Edition via helm
4. Wait for all pods to be ready
5. Start a port-forward on **port 9000** so the UI is accessible

The URL is printed at the end. Default credentials: **admin / admin** (change on first login).

### Option B — Manual steps

```bash
# Add and update the helm repo
helm repo add sonarqube https://SonarSource.github.io/helm-chart-sonarqube
helm repo update

# Create namespace
kubectl create namespace sonarqube

# Install SonarQube Community Edition
helm upgrade --install sonarqube sonarqube/sonarqube \
  --namespace sonarqube \
  --wait --timeout 15m \
  --set monitoringPasscode="dynatr@c3" \
  --set edition="" \
  --set community.enabled=true

# Expose SonarQube on port 9000 (run in background)
kubectl port-forward -n sonarqube svc/sonarqube-sonarqube 9000:9000 --address 0.0.0.0 &
```

SonarQube will be available at `http://localhost:9000` (or the codespace forwarded URL on port 9000).

### Uninstall

```bash
uninstallSonarqube
```