## Create a new project called KKM-pulse-demo

### Reverse Engineer how dtPayment make (a nodeJs project)
Code, Build, Test, Deployed

### Create a project in Gitlab
Project name kkm-pulse-demo

### Clone the project from codespace, commit and push

``` 
git remove set-url <baseon-gitlab>
git add .
git commit 
```

### create and deploye the runner docker

### see the result 
- npm build
- npm test
- sast

## Install SonarQube (Code Quality Gate)

SonarQube Community Edition can be installed into the Kubernetes cluster with a single command using the built-in function.

## Pre-requisites

1. **Create a Peronal Acecss Token**
    a. Go User Setting -> Access -> Personal Access token.
    b. Generate new token -> Set Name and Expiry.
    c. Select all Resource access Permission

    short just search SSH keys and click.  

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


 - enable the public access in codespace

### configure the Sonarqube and varialble gitlab

### update ci to add sonarqube stages

 - enable sonar-build stage
 - commit changes
 - validate result pipeline gitlab

### deployed application into k8s
 - enable the deploy stages
 - commit changes
 - validate the pipeline and url codespace has deployed.

