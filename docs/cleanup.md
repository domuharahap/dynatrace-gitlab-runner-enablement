--8<-- "snippets/dt-enablement.md"

# Cleanup

Remove everything the workshop created, in the Codespace, in Kubernetes, and in GitLab.

---

## Stop the GitLab Runner

```bash
sudo gitlab-runner stop
sudo gitlab-runner uninstall
```

Then remove the runner registrations from GitLab: in each project (`firstproject`, `kkm-pulse-demo`) go to **Settings → CI/CD → Runners** and delete the runner entry.

---

## Remove the deployed app

```bash
kubectl delete ns kkm-pulse-dev --force
kubectl delete ns kkm-pulse-prod --force
```

---

## Remove SonarQube

```bash
uninstallSonarqube
```

!!! info ""
    This removes the SonarQube Helm release, the `sonarqube` namespace, and its port-forward.

---

## Remove the Dynatrace Operator (optional)

If you want to fully remove Dynatrace monitoring from the cluster:

```bash
undeployDynakube
uninstallDynatrace
```

!!! warning ""
    This removes the Dynakube custom resource (and, with `uninstallDynatrace`, the Operator Helm release and `dynatrace` namespace). OneAgent stops reporting immediately.

---

## Remove your GitLab.com projects

In GitLab: open `firstproject` (and `kkm-pulse-demo` if you're fully done with it) → **Settings → General → Advanced → Delete project**.

---

## Delete the Codespace

!!! tip "Delete from inside the terminal"
    There is a convenience function loaded in the shell — just type:

    ```bash
    deleteCodespace
    ```

    This triggers deletion of the Codespace from inside the container itself.

Alternatively, go to [https://github.com/codespaces](https://github.com/codespaces){target=_blank} and delete the Codespace from the GitHub UI.

!!! warning "Revoke tokens"
    After the workshop, revoke or delete the Dynatrace API tokens you used (`DT_OPERATOR_TOKEN`, `DT_INGEST_TOKEN`) and any GitLab Personal/Runner Authentication Tokens you generated, to avoid leaving unused credentials active.

<div class="grid cards" markdown>
- [Resources :octicons-arrow-right-24:](resources.md)
</div>
