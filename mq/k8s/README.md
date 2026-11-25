# iic-mqm-infrastructure

Example organization: **Ishanti Intelligence Collective (IIC)**.

GitOps repository for IBM MQ queue managers on AKS, deployed by Argo CD.

The `iic` repository URL and company identifiers are examples. Set the actual repository coordinates and Entra administrator-group object IDs in `operations/master/values.<environment>.<region>.yaml` before deployment. The example `adminGroups` list is empty and grants no group membership.

- Plain Kubernetes YAML and Kustomize. No Helm (for workloads) and no IBM MQ Operator.
- Queue managers are **single instance** in `dev` (`common/queue-manager-single-instance`) and 3-replica **Native HA** in `test`, `qa`, `perf`, and `prod` (`common/queue-manager-nativeha`).
- Derived from the Apache-2.0 sample chart in [ibm-messaging/mq-helm](https://github.com/ibm-messaging/mq-helm) (rendered once, then converted to Kustomize).

```
operations/
  master/
    values.<env>.cus.yaml                Argo CD AppProject & ApplicationSet values (dev, test, qa, perf, prod)
workloads/
  common/
    components/qm-naming/                Rewrites Native HA "NAME" placeholders from the prefixed StatefulSet name
    components/env-sizing/<env>/         Per-environment CPU, memory, PVC sizes, AZ spread, and license tier
    components/keyvault-secrets/         Reusable Azure Key Vault CSI component (opt-in per overlay)
    components/keyvault-env/<env>/<reg>/ Per-environment Key Vault coordinates (keyvaultName, tenantId, identity)
    queue-manager-nativeha/              Native HA: StatefulSet (3 pods), ILB + replication + metrics Services, PDB
    queue-manager-single-instance/       Single instance: StatefulSet (1 pod, 3 PVCs), LoadBalancer Service
  mqm/
    <qm>/                                One folder per queue manager = one Argo CD Application
      base/                              Reusable Component: namePrefix, instance label, MQ_QMGR_NAME, MQSC (mqsc/qm.mqsc)
      overlays/<env>/<region>/           Per-environment overlays (env: dev, test, qa, perf, prod; region: cus)
scripts/
  rolling-restart.sh                     Upgrade helper for Native HA (see below)
```

## Environments and Estimated Sizing

All 20 queue managers are defined across five environments (`cus` region). CPU, memory, and disk values in `workloads/common/components/env-sizing/<env>/` are **initial estimates**—tune per environment or override in an individual queue manager's overlay after load testing.

| Environment | Namespace | Topology | Pods / QM | CPU per pod (Req / Lim) | Memory per pod (Req / Lim) | Disk PVCs per pod (`qm` / `data` / `log`) | Total Disk / QM | AZ Spread (`topologySpreadConstraints`) | License Annotation | Argo CD Sync | ILB IP Range (`cus`) |
| :--- | :--- | :--- | :---: | :--- | :--- | :--- | :--- | :--- | :--- | :--- | :--- |
| **dev** | `mq-dev` | Single-instance | 1 | `500m` / `1` | `512Mi` / `1Gi` | `5Gi` / `10Gi` / `10Gi` (25Gi) | 25Gi | Single-zone | MQ Non-Prod | Automated | `10.208.130.20–39` |
| **test** | `mq-test` | **Native HA** | 3 | `500m` / `1` | `1Gi` / `2Gi` | `5Gi` / `20Gi` / `10Gi` (35Gi) | 105Gi | `ScheduleAnyway` | MQ Advanced Non-Prod | Manual | `10.208.131.20–39` *(TBD)* |
| **qa** | `mq-qa` | **Native HA** | 3 | `1` / `2` | `2Gi` / `4Gi` | `10Gi` / `30Gi` / `20Gi` (60Gi) | 180Gi | `ScheduleAnyway` | MQ Advanced Non-Prod | Manual | `10.208.132.20–39` *(TBD)* |
| **perf** | `mq-perf` | **Native HA** | 3 | `2` / `4` | `4Gi` / `8Gi` | `10Gi` / `64Gi` / `32Gi` (106Gi) | 318Gi | `DoNotSchedule` (3-AZ) | MQ Advanced Non-Prod | Manual | `10.208.133.20–39` *(TBD)* |
| **prod** | `mq-prod` | **Native HA** | 3 | `2` / `4` | `4Gi` / `8Gi` | `10Gi` / `64Gi` / `32Gi` (106Gi) | 318Gi | `DoNotSchedule` (3-AZ) | **MQ Advanced Prod** | Manual | `10.208.134.20–39` *(TBD)* |

Notes:
- `perf` matches `prod` CPU, memory, disk (aligned with Azure Premium SSD P4/P6 tiers), and strict 3-AZ spread so load tests reflect production latency and quorum behavior.
- Every Native HA replica is sized identically to handle the full active workload and catch-up replication. The `ibm-mq` AKS node pool must have at least **3 worker nodes** (across 3 availability zones for `perf`/`prod`) to satisfy `podAntiAffinity` (`kubernetes.io/hostname`) and `topologySpreadConstraints`.

## How a queue manager gets deployed

Everything is under `workloads/`:

1. **Argo CD finds it.** The `mqm` ApplicationSet in `operations/master/templates/mqm.yaml`
   scans `workloads/mqm/*/overlays/{{ environment }}/{{ region }}`. Each match becomes one Application, named after the
   `<qm>` folder, so the folder name must be a valid Kubernetes name.
2. **Argo CD runs `kustomize build` on that overlay folder**, which composes:
   - `resources`: either `common/queue-manager-single-instance` (`dev`) or `common/queue-manager-nativeha` (`test`, `qa`, `perf`, `prod`)
   - `components`:
     - `../../../base` — queue manager `namePrefix`, `app.kubernetes.io/instance`, `MQ_QMGR_NAME`, and the `mqsc` ConfigMap (`mqsc/qm.mqsc`)
     - `common/components/qm-naming` *(Native HA)* — rewrites `statefulSetName`, `podAntiAffinity`, `topologySpreadConstraints`, `MQ_NATIVE_HA_INSTANCE_*`, and `ibm-mq-replica-{0,1,2}` pod selectors from the prefixed StatefulSet name
     - `common/components/env-sizing/<env>` *(Native HA)* — sets per-environment CPU, memory, PVC storage sizes, AZ spread policy, and license annotations
   - Overlay patch: `namespace: mq-<env>` and the static Azure ILB private IP on `Service/ibm-mq`
3. **Argo CD applies the result** to the cluster. For each Native HA queue manager that produces one 3-replica StatefulSet (`<qm>-ibm-mq`), 1 `LoadBalancer` client Service, 1 metrics Service, 3 per-pod replication Services (`<qm>-ibm-mq-replica-{0,1,2}`), a `PodDisruptionBudget`, a ConfigMap with the MQSC, and a ServiceAccount.
4. **Kubernetes starts the pods**, attaching dedicated `qm`, `data`, and `log` PVCs per pod.

To inspect the rendered manifests for any environment:

```bash
kustomize build workloads/mqm/qm-gclr-q/overlays/dev/cus
kustomize build workloads/mqm/qm-gclr-q/overlays/test/cus
kustomize build workloads/mqm/qm-gclr-q/overlays/qa/cus
kustomize build workloads/mqm/qm-gclr-q/overlays/perf/cus
kustomize build workloads/mqm/qm-gclr-q/overlays/prod/cus
```

## Add a queue manager

1. Copy an existing queue manager folder (for example `workloads/mqm/qm-gclr-q`) to `workloads/mqm/<new-qm>`.
2. In `base/kustomization.yaml`, update `namePrefix`, `app.kubernetes.io/instance`, and `MQ_QMGR_NAME`.
3. Replace the MQSC in `base/mqsc/qm.mqsc` (for example from a `dmpmqcfg` export).
4. In each `overlays/<env>/cus/kustomization.yaml` (`dev`, `test`, `qa`, `perf`, `prod`), assign a unique static private IP on the Azure Internal Load Balancer for `Service/ibm-mq`.
5. Check each overlay renders: `kustomize build workloads/mqm/<new-qm>/overlays/<env>/cus`.
6. Open a PR. `dev` syncs automatically via Argo CD; `test`, `qa`, `perf`, and `prod` are synced manually.

## Enable Azure Key Vault secrets (optional)

Queue managers can opt into the Azure Key Vault Secrets Store CSI Driver without duplicating CSI manifests:

1. Populate the environment's Key Vault values once in `workloads/common/components/keyvault-env/<env>/<region>/kustomization.yaml`.
2. In the queue manager's `overlays/<env>/<region>/kustomization.yaml`, include both components and patch `spec.parameters.objects` (and `spec.secretObjects` if syncing a Kubernetes Secret) on `kind: SecretProviderClass`:

```yaml
components:
  - ../../../base
  - ../../../../../common/components/qm-naming
  - ../../../../../common/components/env-sizing/prod
  - ../../../../../common/components/keyvault-secrets
  - ../../../../../common/components/keyvault-env/prod/cus
```

The component automatically names each queue manager's `SecretProviderClass` and synced `Secret` `<qm>-ibm-mq-kv` to prevent collisions in shared namespaces.

## Queue Manager Inventory & Static ILB IPs — ADR-002 Option 1

Each queue manager is exposed on an Azure Standard Internal Load Balancer with a **dedicated static private IP**, `externalTrafficPolicy: Local` (preserving client source IP for `CHLAUTH` rules and routing Native HA traffic strictly to the active Ready pod's node), and a 30-minute TCP idle timeout.

| Queue manager | Kubernetes name | `dev` IP | `test` IP *(TBD)* | `qa` IP *(TBD)* | `perf` IP *(TBD)* | `prod` IP *(TBD)* | Ports |
| :--- | :--- | :--- | :--- | :--- | :--- | :--- | :--- |
| QM_GCLR_Q | `qm-gclr-q` | `10.208.130.20` | `10.208.131.20` | `10.208.132.20` | `10.208.133.20` | `10.208.134.20` | 1414, 9443 |
| iicqm_bloom | `iicqm-bloom` | `10.208.130.21` | `10.208.131.21` | `10.208.132.21` | `10.208.133.21` | `10.208.134.21` | 1414, 9443 |
| iicqm_gclr | `iicqm-gclr` | `10.208.130.22` | `10.208.131.22` | `10.208.132.22` | `10.208.133.22` | `10.208.134.22` | 1414, 9443 |
| iicqm_bute | `iicqm-bute` | `10.208.130.23` | `10.208.131.23` | `10.208.132.23` | `10.208.133.23` | `10.208.134.23` | 1414, 9443 |
| QM_G3_Q | `qm-g3-q` | `10.208.130.24` | `10.208.131.24` | `10.208.132.24` | `10.208.133.24` | `10.208.134.24` | 1414, 9443 |
| QM_G4_Q | `qm-g4-q` | `10.208.130.25` | `10.208.131.25` | `10.208.132.25` | `10.208.133.25` | `10.208.134.25` | 1414, 9443 |
| QM_G5_Q | `qm-g5-q` | `10.208.130.26` | `10.208.131.26` | `10.208.132.26` | `10.208.133.26` | `10.208.134.26` | 1414, 9443 |
| OPF_UAT_Q | `opf-uat-q` | `10.208.130.27` | `10.208.131.27` | `10.208.132.27` | `10.208.133.27` | `10.208.134.27` | 1414, 9443 |
| QM_GPX_Q | `qm-gpx-q` | `10.208.130.28` | `10.208.131.28` | `10.208.132.28` | `10.208.133.28` | `10.208.134.28` | 1414, 9443 |
| iicqm_eram | `iicqm-eram` | `10.208.130.29` | `10.208.131.29` | `10.208.132.29` | `10.208.133.29` | `10.208.134.29` | 1414, 9443 |
| iicqm_crvl | `iicqm-crvl` | `10.208.130.30` | `10.208.131.30` | `10.208.132.30` | `10.208.133.30` | `10.208.134.30` | 1414, 9443 |
| iicqm_trcmo | `iicqm-trcmo` | `10.208.130.31` | `10.208.131.31` | `10.208.132.31` | `10.208.133.31` | `10.208.134.31` | 1414, 9443 |
| INTOMGEO | `intomgeo` | `10.208.130.32` | `10.208.131.32` | `10.208.132.32` | `10.208.133.32` | `10.208.134.32` | 1414, 9443 |
| QM_DM_Q | `qm-dm-q` | `10.208.130.33` | `10.208.131.33` | `10.208.132.33` | `10.208.133.33` | `10.208.134.33` | 1414, 9443 |
| QM_CTRL_Q | `qm-ctrl-q` | `10.208.130.34` | `10.208.131.34` | `10.208.132.34` | `10.208.133.34` | `10.208.134.34` | 1414, 9443 |
| QM_ERAM | `qm-eram` | `10.208.130.35` | `10.208.131.35` | `10.208.132.35` | `10.208.133.35` | `10.208.134.35` | 1414, 9443 |
| QM_MERLIN | `qm-merlin` | `10.208.130.36` | `10.208.131.36` | `10.208.132.36` | `10.208.133.36` | `10.208.134.36` | 1414, 9443 |
| QM_TRSY | `qm-trsy` | `10.208.130.37` | `10.208.131.37` | `10.208.132.37` | `10.208.133.37` | `10.208.134.37` | 1414, 9443 |
| QM_SDL_Q | `qm-sdl-q` | `10.208.130.38` | `10.208.131.38` | `10.208.132.38` | `10.208.133.38` | `10.208.134.38` | 1414, 9443 |
| QM_GTX_GCLR_Q | `qm-gtx-gclr-q` | `10.208.130.39` | `10.208.131.39` | `10.208.132.39` | `10.208.133.39` | `10.208.134.39` | 1414, 9443 |

Common container settings:
- Pinned image digest: `cp.icr.io/cp/ibm-mqadvanced-server@sha256:06f0892b36e879d0f8957477deeabfe2b4e0fda13f64792edbe7825caf7b77e3`.
- `imagePullSecrets: [{name: ibm-entitlement-key}]`.

## Native HA upgrades: `OnDelete`, then run the script

The Native HA StatefulSet uses `updateStrategy: OnDelete`. With Native HA only the active pod is Ready, so a normal rolling update would stall on the first replica. So:

1. Merge the change and sync the Application in Argo CD (pods do not recycle yet).
2. Run `scripts/rolling-restart.sh <qm>-ibm-mq mq-<env>`. It deletes the replicas first and the active pod last, and after each one waits for `INSYNC(yes)` and `QUORUM(3/3)` from `dspmq -o nativeha`.

Do not change `replicas`; Native HA needs exactly 3. A changed MQSC ConfigMap gets a new name (hash suffix), which changes the pod template, so it also needs the restart above.

## Node drains

The PodDisruptionBudget (`maxUnavailable: 1`) effectively blocks all voluntary evictions, because the two non-active pods always count as unavailable. A drain waits rather than breaking quorum. Move pods on purpose, one at a time, using `scripts/rolling-restart.sh`, or adapt IBM's `drainMQContainers.sh`.

## Conventions

- No `namespace:` in common or base. Each overlay sets `namespace: mq-<env>`; Terraform creates the namespaces.
- Deleting a queue manager folder removes its Application but leaves its resources (PVCs) in place. Clean them up by hand.
- Argo CD's AppProject allows no cluster-scoped resources.

## Open items (marked TBD in the files)

| Item | Where | Ref |
|------|-------|-----|
| Replace placeholder `test`/`qa`/`perf`/`prod` ILB subnet IPs (`10.208.131–134.x`) with allocated VNet IPs | `workloads/mqm/*/overlays/{test,qa,perf,prod}/cus/kustomization.yaml` | |
| Image from IIC's ACR, pinned by digest (currently `cp.icr.io/cp/ibm-mqadvanced-server@sha256:...`) | `common/queue-manager-{single-instance,nativeha}/statefulset.yaml` | OQ-08 |
| Verify license `productID` annotations against IIC's IBM MQ Advanced / CP4I entitlement | `common/queue-manager-nativeha/statefulset.yaml`, `common/components/env-sizing/prod/` | |
| `ibm-entitlement-key` imagePullSecret, if pulling from IBM's registry | StatefulSet / namespace | |
| TLS for Native HA replication links (`9414`) & migrating deprecated `MQ_NATIVE_HA_INSTANCE_*` env vars to INI ConfigMaps | `common/queue-manager-nativeha/statefulset.yaml`, Key Vault CSI | |
| Populate Azure Key Vault coordinates (`keyvaultName`, `tenantId`, `userAssignedIdentityID`) per environment | `common/components/keyvault-env/<env>/cus/kustomization.yaml` | |
| Populate Entra `adminGroups` object IDs per environment | `operations/master/values.<env>.cus.yaml` | |
| CRR / cross-region DR overlays if required for `prod` | not yet modelled | |

## Validation status

YAML syntax, relative Kustomize resource/component paths, JSON 6902 patch pointers, `qm-naming` replacement targets, and per-environment ILB IP uniqueness have been programmatically verified across all 20 queue managers and all 5 environments (`dev`, `test`, `qa`, `perf`, `prod`). Repeat `kustomize build` (v5.x) and `helm template` before deploying to AKS, as `kustomize` and `helm` binaries were not installed in the editing environment.
