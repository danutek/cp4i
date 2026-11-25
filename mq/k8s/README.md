# iic-mqm-infrastructure

Example organization: **Ishanti Intelligence Collective (IIC)**.

GitOps repository for IBM MQ queue managers on AKS, deployed by Argo CD.

The `iic` repository URL and company identifiers are examples. Set the actual repository coordinates and Entra administrator-group object IDs in `operations/master/values.<environment>.<region>.yaml` before deployment. The example `adminGroups` list is empty and grants no group membership.

- Plain Kubernetes YAML and Kustomize. No Helm and no IBM MQ Operator.
- Queue managers are either 3-replica **Native HA** (`common/queue-manager-nativeha`) or **single instance** (`common/queue-manager-single-instance`).
- Derived from the Apache-2.0 sample chart in [ibm-messaging/mq-helm](https://github.com/ibm-messaging/mq-helm) (rendered once, then converted to Kustomize).

```
workloads/
  common/
    components/keyvault-secrets/         Reusable Azure Key Vault CSI component (opt-in per overlay)
    components/keyvault-env/<env>/<reg>/ Per-environment Key Vault coordinates (keyvaultName, tenantId, identity)
    queue-manager-nativeha/              Native HA: StatefulSet (3 pods), Services, PodDisruptionBudget
    queue-manager-single-instance/       Single instance: StatefulSet (1 pod, 3 PVCs), LoadBalancer Service
  mqm/
    <qm>/                                One folder per queue manager = one Argo CD Application
      base/                              Queue manager identity + MQSC (mqsc/qm.mqsc)
      overlays/<env>/<region>/           Per-environment values (env: dev, uat, prod; region: cus)
scripts/
  rolling-restart.sh                     Upgrade helper for Native HA (see below)
```

## How a queue manager gets deployed

Everything is under `workloads/`:

1. **Argo CD finds it.** The `mqm` ApplicationSet in `operations/master/templates/mqm.yaml`
   scans `workloads/mqm/*/overlays/{{ environment }}/{{ region }}`. Each match becomes one Application, named after the
   `<qm>` folder, so the folder name must be a valid Kubernetes name.
2. **Argo CD runs `kustomize build` on that overlay folder**, which pulls in, in this order:
   - `overlays/dev/cus/` : namespace `mq-dev`, static ILB private IP assignment
   - `base/` : queue manager name prefix, `MQ_QMGR_NAME`, the MQSC file (`mqsc/qm.mqsc`)
   - `workloads/common/queue-manager-single-instance/` (or `-nativeha/`): the **StatefulSet** (`statefulset.yaml`),
     Service (`service.yaml`), and ServiceAccount (`serviceaccount.yaml`), shared across queue managers
3. **Argo CD applies the result** to the cluster. For each queue manager that produces one StatefulSet
   (`qm-gclr-q-ibm-mq`, 1 pod), 1 `LoadBalancer` Service, a ConfigMap with the MQSC, and a ServiceAccount.
4. **Kubernetes starts the pod**, attaching its dedicated PVCs (`qm`, `data`, `log`).

The StatefulSet is not repeated per queue manager. It lives once in `workloads/common/queue-manager-single-instance/statefulset.yaml`
and each queue manager's `base/` and overlay customise it. To see exactly what is deployed:

```
kustomize build workloads/mqm/qm-gclr-q/overlays/dev/cus
```

For another environment or region, add the matching `overlays/<env>/<region>` folders.

## Add a queue manager

1. Copy an existing queue manager folder (for example `workloads/mqm/qm-gclr-q`) to `workloads/mqm/<new-qm>`.
2. In `base/kustomization.yaml`, update `namePrefix`, `app.kubernetes.io/instance`, and `MQ_QMGR_NAME`.
3. Replace the MQSC in `base/mqsc/qm.mqsc` (for example from a `dmpmqcfg` export).
4. In `overlays/dev/cus/kustomization.yaml`, update the Service patch target name to `<new-qm>-ibm-mq` and assign the dedicated private IP on the Azure Internal Load Balancer.
5. Check it renders: `kustomize build workloads/mqm/<new-qm>/overlays/dev/cus`.
6. Open a PR. Dev syncs automatically via Argo CD.

## Enable Azure Key Vault secrets (optional)

Queue managers can opt into the Azure Key Vault Secrets Store CSI Driver without duplicating CSI manifests:

1. Populate the environment's Key Vault values once in `workloads/common/components/keyvault-env/<env>/<region>/kustomization.yaml`.
2. In the queue manager's `overlays/<env>/<region>/kustomization.yaml`, include both components and patch `spec.parameters.objects` (and `spec.secretObjects` if syncing a Kubernetes Secret) on `kind: SecretProviderClass`:

```yaml
components:
  - ../../../../../common/components/keyvault-secrets
  - ../../../../../common/components/keyvault-env/dev/cus
```

The component automatically names each queue manager's `SecretProviderClass` and synced `Secret` `<qm>-ibm-mq-kv` to prevent collisions in shared namespaces.

## Single-instance queue managers (dev) — ADR-002 Option 1

The 20 dev queue managers are single instance (1 pod, 3 PVCs `qm: 5Gi`, `data: 10Gi`, `log: 10Gi`).
Each is exposed on Azure Standard Internal Load Balancer via **ADR-002 Option 1** with a **dedicated static private IP**:

| Queue manager | Kubernetes name | Dedicated Static IP | Ports Exposed |
| :--- | :--- | :--- | :--- |
| QM_GCLR_Q | `qm-gclr-q` | `10.208.130.20` | 1414, 9443 |
| iicqm_bloom | `iicqm-bloom` | `10.208.130.21` | 1414, 9443 |
| iicqm_gclr | `iicqm-gclr` | `10.208.130.22` | 1414, 9443 |
| iicqm_bute | `iicqm-bute` | `10.208.130.23` | 1414, 9443 |
| QM_G3_Q | `qm-g3-q` | `10.208.130.24` | 1414, 9443 |
| QM_G4_Q | `qm-g4-q` | `10.208.130.25` | 1414, 9443 |
| QM_G5_Q | `qm-g5-q` | `10.208.130.26` | 1414, 9443 |
| OPF_UAT_Q | `opf-uat-q` | `10.208.130.27` | 1414, 9443 |
| QM_GPX_Q | `qm-gpx-q` | `10.208.130.28` | 1414, 9443 |
| iicqm_eram | `iicqm-eram` | `10.208.130.29` | 1414, 9443 |
| iicqm_crvl | `iicqm-crvl` | `10.208.130.30` | 1414, 9443 |
| iicqm_trcmo | `iicqm-trcmo` | `10.208.130.31` | 1414, 9443 |
| INTOMGEO | `intomgeo` | `10.208.130.32` | 1414, 9443 |
| QM_DM_Q | `qm-dm-q` | `10.208.130.33` | 1414, 9443 |
| QM_CTRL_Q | `qm-ctrl-q` | `10.208.130.34` | 1414, 9443 |
| QM_ERAM | `qm-eram` | `10.208.130.35` | 1414, 9443 |
| QM_MERLIN | `qm-merlin` | `10.208.130.36` | 1414, 9443 |
| QM_TRSY | `qm-trsy` | `10.208.130.37` | 1414, 9443 |
| QM_SDL_Q | `qm-sdl-q` | `10.208.130.38` | 1414, 9443 |
| QM_GTX_GCLR_Q | `qm-gtx-gclr-q` | `10.208.130.39` | 1414, 9443 |

Features:
- Standard listener port `1414` (`qmgr`) and web console `9443` (`console-https`) for every queue manager.
- `externalTrafficPolicy: Local` to preserve client source IP for `CHLAUTH` rules.
- 30-minute idle timeout on ILB rules.
- Pinned image digest: `cp.icr.io/cp/ibm-mqadvanced-server@sha256:06f0892b36e879d0f8957477deeabfe2b4e0fda13f64792edbe7825caf7b77e3`.
- `imagePullSecrets: [{name: ibm-entitlement-key}]`.

## Native HA upgrades: `OnDelete`, then run the script

The StatefulSet uses `updateStrategy: OnDelete`. With Native HA only the active pod is Ready, so a
normal rolling update would stall on the first replica. So:

1. Merge the change. Argo CD syncs it, but the running pods do not change.
2. Run `scripts/rolling-restart.sh <qm>-ibm-mq mq-<env>`. It deletes the replicas first and the
   active pod last, and after each one waits for `INSYNC(yes)` and `QUORUM(3/3)` from `dspmq -o nativeha`.

Do not change `replicas`; Native HA needs exactly 3. A changed MQSC ConfigMap gets a new name
(hash suffix), which changes the pod template, so it also needs the restart above.

## Node drains

The PodDisruptionBudget (`maxUnavailable: 1`) effectively blocks all evictions, because the two
non-active pods always count as unavailable. A drain waits rather than breaking quorum. Move pods on
purpose, one at a time, using the script above, or adapt IBM's `drainMQContainers.sh`.

## Conventions

- No `namespace:` in common or base. Each overlay sets `namespace: mq-<env>`; Terraform creates the namespaces.
- Deleting a queue manager folder removes its Application but leaves its resources (PVCs) in place.
  Clean them up by hand.
- Argo CD's AppProject allows no cluster-scoped resources.

## Open items (marked TBD in the files)

| Item | Where | Ref |
|------|-------|-----|
| Image from IIC's ACR, pinned by digest, MQ 9.4 LTS (the sample default is `10.0.1.0-r1`) | `common/queue-manager-nativeha/statefulset.yaml` | OQ-08 |
| Storage class (`managed-csi-premium-cmk` configured) | `common/queue-manager-single-instance/statefulset.yaml` | OQ-06 |
| License annotations (`productID`, metric) and entitlement for Native HA (MQ Advanced or CP4I) | overlay `statefulset-patch.yaml` | |
| `ibm-entitlement-key` imagePullSecret, if pulling from IBM's registry | StatefulSet / namespace | |
| TLS for the replication links (9414), MQ credentials and certificates (Key Vault) | not yet modelled | |
| UAT and prod overlays (license `use`, resources, spread over 3 availability zones), CRR/DR | not yet created | |

## Validation status

The manifests were previously documented as rendering with `kustomize build` v5.4.3. After the IIC naming changes, YAML syntax, local resource paths, and queue-manager naming consistency were checked. Kustomize and Helm rendering must be repeated before deployment; those tools were not available for this edit. The manifests have **not** been applied to a cluster or synced by Argo CD. The restart script has only had a shell syntax check (`bash -n`).
