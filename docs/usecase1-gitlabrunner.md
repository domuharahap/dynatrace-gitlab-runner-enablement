## 1. Create first Project in Gitlab

## Pre Requisites
1. **Log in to the GitLab UI.**
Create Project
2. **Generate ssh key in codespace**
```
ssh-keygen
```

get the key generated and copy to Gitlab
```
cat home/vscode/.ssh/*.pub
```

3. **Copy the output ssh key into Gitlab SSH key**
    a. Go User Setting -> Access -> SSH Keys.
    b. Add new Key -> pass the keygen generated into key input field.
    c. Add Key to Save

    short just search SSH keys and click.  

4. **Clone the Project created in codespace**
    a. Go to Project FirstPrject and Cliek `+` -> `add New Files`
    b. copy and save with file name `.gitlab-ci.yaml`

    ```
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
        ```

Alternatively, you can clone this into your codespace
1. go to gitlab project -> Code -> Copy Clone with SSH
2. Go you your codespace run this command clone
```
git clone git@gitlab.com:<generatedCode>/firstproject.git
```
3. create the new files called .gitlab-ci.yaml
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

See and validate the pipeline running


let run more example

Example 1:

The runner is configured with the tags [docker, shell, codespace].
The job has the tags [shell] and is executed and run.
Example 2:

The runner is configured with the tags [docker, shell, codespace].
The job has the tags [docker, shell, codespace] and is executed and run.
Example 3:

The runner is configured with the tags [docker, shell, codespace].
The job has the tags [docker, shell, k8s] and is not executed.

