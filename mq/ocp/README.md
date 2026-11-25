# IBM MQ on OpenShift with the IBM MQ Operator

Example organization: **Ishanti Intelligence Collective (IIC)**.

This is the OpenShift counterpart to `../k8s`: the same **20 logical queue managers**, the same five environments and per-pod resource/storage estimates, managed through Argo CD and Kustomize. IBM's `QueueManager` custom resources replace the hand-managed StatefulSets.

**Ownership:** Git/Argo CD owns the `QueueManager` CRs and their MQSC ConfigMaps. The IBM MQ Operator owns generated StatefulSets, Pods, Services, Routes and storage reconciliation. OLM manages the Operator installation. Do not also sync the plain Kubernetes manifests into these namespaces, edit generated resources, or use the Kubernetes version's pod-deletion rollout script here.

## Repository layout

```text
bootstrap/                              Root Argo CD Applications, one per environment + optional platform app
operations/master/
  base/                                 Shared AppProject + ApplicationSet
  overlays/<env>/cus/                    dev, test, qa, perf, prod GitOps settings
platform/
  operator/                             Namespace, cluster-wide OperatorGroup, Subscription
  namespaces/<env>/                     Operand namespace and limited controller Role/RoleBinding
workloads/
  common/
    queue-manager-single-instance/      Operator CR baseline for dev
    queue-manager-nativeha/             Operator CR baseline with rolling updates and replication TLS
    components/env-sizing/<env>/        Resource/PVC sizes and production license selection
    components/operator-references/     Custom ConfigMap name-reference rules for QueueManager
    components/mq-client-route/         Optional TLS client Route configuration
    components/mqsc-secret/              Optional externally managed MQSC Secret
  mqm/<qm>/
    base/                               Reusable identity/MQSC Component
    overlays/<env>/cus/                  Per-QM, per-environment compositions
scripts/
  configure-gitops.py                    Set public repository coordinates/controller namespace
  validate.py                            Render and validate names, references, topology and policies
```

All new manifests, including the GitOps bootstrap, use Kustomize; there is no Helm dependency. `cus` is retained as the logical region name for parity and is not an Azure infrastructure assumption.

## Queue-manager inventory

The following names exactly match `../k8s`. Logical MQ names are case-sensitive and are explicitly set through `spec.queueManager.name`.

| Folder | Logical MQ name | QueueManager CR name |
| --- | --- | --- |
| `iicqm-bloom` | `iicqm_bloom` | `iicqm-bloom-qm` |
| `iicqm-bute` | `iicqm_bute` | `iicqm-bute-qm` |
| `iicqm-crvl` | `iicqm_crvl` | `iicqm-crvl-qm` |
| `iicqm-eram` | `iicqm_eram` | `iicqm-eram-qm` |
| `iicqm-gclr` | `iicqm_gclr` | `iicqm-gclr-qm` |
| `iicqm-trcmo` | `iicqm_trcmo` | `iicqm-trcmo-qm` |
| `intomgeo` | `INTOMGEO` | `intomgeo-qm` |
| `opf-uat-q` | `OPF_UAT_Q` | `opf-uat-q-qm` |
| `qm-ctrl-q` | `QM_CTRL_Q` | `qm-ctrl-q-qm` |
| `qm-dm-q` | `QM_DM_Q` | `qm-dm-q-qm` |
| `qm-eram` | `QM_ERAM` | `qm-eram-qm` |
| `qm-g3-q` | `QM_G3_Q` | `qm-g3-q-qm` |
| `qm-g4-q` | `QM_G4_Q` | `qm-g4-q-qm` |
| `qm-g5-q` | `QM_G5_Q` | `qm-g5-q-qm` |
| `qm-gclr-q` | `QM_GCLR_Q` | `qm-gclr-q-qm` |
| `qm-gpx-q` | `QM_GPX_Q` | `qm-gpx-q-qm` |
| `qm-gtx-gclr-q` | `QM_GTX_GCLR_Q` | `qm-gtx-gclr-q-qm` |
| `qm-merlin` | `QM_MERLIN` | `qm-merlin-qm` |
| `qm-sdl-q` | `QM_SDL_Q` | `qm-sdl-q-qm` |
| `qm-trsy` | `QM_TRSY` | `qm-trsy-qm` |

The Operator derives its underlying resource names from the CR. Do not use the CR name as a replacement for the logical MQ name in application configuration.

## Environments and sizing

| Environment | Namespace | Availability | Pods/QM | CPU request/limit | Memory request/limit | PVC sizes per pod: queueManager / persistedData / recoveryLogs | Placement | Workload sync |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| dev | `mq-ocp-dev` | SingleInstance | 1 | 500m / 1 | 512Mi / 1Gi | 5Gi / 10Gi / 10Gi | Operator defaults | Automatic |
| test | `mq-ocp-test` | NativeHA | 3 | 500m / 1 | 1Gi / 2Gi | 5Gi / 20Gi / 10Gi | Separate hosts; prefer separate zones | Manual |
| qa | `mq-ocp-qa` | NativeHA | 3 | 1 / 2 | 2Gi / 4Gi | 10Gi / 30Gi / 20Gi | Separate hosts; prefer separate zones | Manual |
| perf | `mq-ocp-perf` | NativeHA | 3 | 2 / 4 | 4Gi / 8Gi | 10Gi / 64Gi / 32Gi | Separate hosts and three separate zones | Manual |
| prod | `mq-ocp-prod` | NativeHA | 3 | 2 / 4 | 4Gi / 8Gi | 10Gi / 64Gi / 32Gi | Separate hosts and three separate zones | Manual |

The estimates match the Kubernetes counterpart. Size every HA replica for the entire workload. `perf` and `prod` require three eligible, zone-labelled worker nodes in distinct zones; those CRs remain unschedulable when the requirement cannot be met. This uses required zone anti-affinity rather than the original topology-spread patch.

No Azure node-pool labels, fixed fsGroup/UID, Azure storage class, or load-balancer IP annotations are copied. The cluster's default StorageClass is used unless you set `spec.queueManager.storage.defaultClass` in the relevant environment component. Confirm it supports the Operator's Native HA requirements and appropriate RWO persistent storage. Keep the Operator's SCC/security-context defaults unless a supported storage/provider design requires changes.

## Operator and MQ version baseline

The example targets the **MQ Operator `v4.0-sc2` channel** and documents the explicit **MQ `10.0.0.0-r1`** version from IBM's MQ 10.0 example. This is a reproducible example baseline, not a recommendation to run an old patch indefinitely. Before installation, select a currently approved Operator catalog and supported, patched MQ image version from that Operator's available versions. Change `spec.version` in both common CR baselines together and review the matching licenses and supported OCP levels. No image digest from the non-Operator installation is carried over.

Non-production environments use the example MQ Advanced Non-Production license `L-UMVX-XYNRAD`; prod selects MQ Advanced Production `L-CXDB-XTZ9J8`. All CRs start with **`spec.license.accept: false`**. Confirm entitlement/license terms and set it to `true` through your reviewed environment changes before deployment. If using CP4I/another entitlement, replace the license selection with the applicable IBM value.

The version-specific IBM MQ catalog is a prerequisite to `platform/operator`. It is intentionally not replaced by a moving global `latest` catalog. Generate the catalog source for the chosen Operator package using IBM's catalog-management procedure, then apply it or manage that generated manifest in your platform GitOps repository. The Subscription expects `ibmmq-operator-catalogsource` in `openshift-marketplace` and uses Automatic InstallPlan approval; **the approved specific catalog controls which Operator versions are offered**.

If a compatible cluster-wide MQ Operator is already installed, reuse it and do not install a second overlapping watch scope. Skip `platform/operator` in that case.

## Bootstrap order

Run commands from the CP4I repository root. These are setup instructions; none were executed against a cluster during creation of this example.

1. Install/verify OpenShift GitOps and the chosen IBM MQ catalog. Confirm the Operator/OCP/MQ support combination. Review `platform/operator/subscription.yaml` and its watch scope.
2. Set the repository URL, revision, and Git root. The checked-in `https://github.com/iic/cp4i` URL is fictional. Supply Git credentials to Argo CD separately, not in URLs or manifests:

   ```bash
   python3 mq/ocp/scripts/configure-gitops.py \
     --repo-url https://github.com/YOUR-ORG/YOUR-REPOSITORY.git \
     --repository-root mq/ocp \
     --revision main
   ```

   Use `--repository-root ''` if publishing the contents of `mq/ocp` as a standalone repository. The script also accepts an Argo CD namespace and application-controller ServiceAccount name if they differ from OpenShift GitOps defaults. Review and commit its changes.
3. A cluster administrator creates the platform prerequisites. Install the Operator only if a compatible one is not already present:

   ```bash
   oc apply -k mq/ocp/platform/operator
   oc apply -k mq/ocp/platform/namespaces
   oc get csv -n iic-mq-operators
   oc wait --for=condition=Established crd/queuemanagers.mq.ibm.com --timeout=300s
   ```

   Wait for the Operator CSV to report `Succeeded`. The optional `bootstrap/platform.yaml` can instead track platform resources through an appropriately privileged GitOps instance; it is manually synced and has no automatic prune policy. Do not assume workload ApplicationSet permissions grant cluster-wide platform privileges. On an existing Operator installation, manage only the namespace prerequisites unless deliberately adopting that installation into the platform app.
4. Provision `ibm-entitlement-key` in each selected operand namespace through your approved secret-management process. Provision a `kubernetes.io/tls` Secret named `mq-nativeha-replication-tls` in each Native HA namespace with the required key, certificate and trust chain. Secrets are external inputs and no secret values are committed here.
5. Configure license acceptance, approved version, storage, authentication/authorities and any client TLS. Complete namespace/controller RBAC and default StorageClass checks.
6. Render and validate before bootstrapping the selected environment:

   ```bash
   python3 mq/ocp/scripts/validate.py --environment dev
   python3 mq/ocp/scripts/validate.py --environment dev --deployment-ready --server-dry-run
   oc apply -f mq/ocp/bootstrap/dev-cus.yaml
   ```

   The second validation command contacts the configured cluster and checks CRD/admission support after the prerequisites exist. It performs server-side dry runs, not deployment. The root app manages one environment's AppProject/ApplicationSet. For higher environments, use the corresponding bootstrap file and manually sync the generated queue-manager Applications after review.

The `mq-ocp-*` namespaces and `*-ocp-<env>-cus` Application names are deliberately distinct from `mq/k8s`. Creating these CRs does not migrate existing messages, queue-manager state, or PVCs. Plan migration/cutover separately.

## MQSC configuration and rollout behavior

Each queue manager's `base/mqsc/` contains:

- `dev-connectivity.mqsc`: the source queue manager's dev configuration, including its authentication bypass and `mqm` channel mapping. **Only dev selects this key.** Keep that environment isolated from untrusted clients.
- `qm.mqsc`: the same queue/channel definitions with the dev bypass removed, CHLAUTH enabled, and a required-password OS authentication baseline. This is selected by test/qa/perf/prod. Configure an actual supported identity source, application users, channel rules and least-privilege authorities before use; this baseline does not create users or supply their credentials. Substitute LDAP or another supported authentication design as appropriate.

The generated ConfigMap includes both keys, but the Operator is explicitly told which key to apply. Keeping copied dev input is for review/parity; its presence as an unused ConfigMap key does not make it part of non-dev startup configuration.

Kustomize generates content-hashed ConfigMap names. The custom name-reference configuration rewrites `spec.queueManager.mqsc[].configMap.name` to the final prefixed/hash name. When content changes, the CR's reference changes and the Operator can reconcile the new configuration. Editing a stable-named ConfigMap alone is insufficient: IBM documents that it does not itself tell the Operator to restart a running queue manager.

Native HA uses the Operator's **`availability.updateStrategy: RollingUpdate`**, not a hand-written StatefulSet `OnDelete` rollout. Do not specify `replicas`, raw MQ Native HA instance address variables, custom replica Services, or a copied PDB here. Verify the selected Operator release's PDB/node-drain behavior, observed health and application reconnection in acceptance tests. Operator-driven updates can still cause a leadership change and brief client interruption.

ConfigMaps and QueueManager CRs carry Argo `Prune=false,Delete=false`; ApplicationSets preserve resources on deletion and generated Applications have no cascading resource finalizer. PVCs have `deleteClaim: false`. These are deletion guards, not backups: do not force-delete CRs or assume an App deletion test is a data-recovery plan. Retained historical ConfigMaps need deliberate cleanup after confirming no CR or existing workload references them.

## OpenShift access

The Operator creates internal MQ access on port 1414 and an HTTPS console Route when web is enabled. There are no Azure ILB resources or fixed external IPs. Inspect the actual generated endpoints:

```bash
oc get queuemanager,svc,route -n mq-ocp-dev
oc describe queuemanager iicqm-bloom-qm -n mq-ocp-dev
```

The web Route does not configure console users. Use the Operator's supported web authentication/manual configuration facilities and externally managed secrets for your environment.

**MQ client Routes are opt-in** because a passthrough MQ Route requires an MQ TLS client/channel and correct SNI behavior; it does not carry arbitrary plaintext MQ traffic. Add this to an individual overlay after provisioning a `mq-client-tls` Secret containing `tls.key`, `tls.crt` and `ca.crt` in its namespace:

```yaml
components:
  # Keep all existing components; append:
  - ../../../../../common/components/mq-client-route
```

The component enables the Operator's MQ Route, imports the key under label `ibmmqtls`, and supplies TLS MQSC for `ADMIN.SVRCONN` with required client certificates. Add your application's channels, identity mappings and authorities; do not assume the sample admin channel is your production application contract. Follow IBM's Route/SNI client instructions. Use dedicated raw TCP load-balancing instead when that is the chosen network design.

Metrics and the Operator-generated ServiceMonitor are enabled with OpenShift-provided TLS. Enable/configure user-workload monitoring and the appropriate collection permissions on the target cluster.

## Secret-management integration

Use existing OpenShift Secret/External Secrets/CSI integrations to provide the Secret names referenced by the CR. The optional `mqsc-secret` component appends an external `mq-runtime-config` Secret containing `runtime.mqsc`, without committing credentials. Never copy the plain Kubernetes Key Vault component's StatefulSet patches here: Operator overrides must target the QueueManager's supported secret/PKI fields or Pod template, and CSI synchronization may require its own mount to occur.

Keep cloud-specific identity setup outside the portable base. Certificates, secrets and their renewal procedures remain deployment prerequisites even though the Operator manages workload lifecycle.

## Adding a queue manager or environment

Copy an existing queue-manager directory, change its base `namePrefix`, instance label and `spec.queueManager.name` patch, and replace its MQSC. Keep the custom name-reference component and identity replacements in every overlay. Create all required environment overlays, render them, and check names/ConfigMap references. The Git generator discovers queue-manager folders automatically; there is no maintained list of Applications to update.

For another region, copy an environment's region overlay and add the matching operations/master overlay and bootstrap Application. For another environment, choose its namespace, license, sizing, availability and placement deliberately rather than assuming `dev` defaults.

## Validation and operational acceptance

`python3 scripts/validate.py` from this directory renders all **100 queue-manager overlays**, five GitOps roots, and platform resources using Kustomize/`oc kustomize`. It checks logical-name parity with `../k8s`, namespace/resource uniqueness, hashed ConfigMap references, selected MQSC security, topology, affinity labels, sizing, license use, PVC retention and dev-only automatic workload sync.

Local rendering does not validate the installed Operator CRD, image/license availability, SCC, StorageClass behavior, routing, or actual HA failover. Use the optional server-dry-run mode after configuring the environment, then test:

- CR reconciliation/Ready status and the expected one/three MQ pods.
- Persistent puts/commits, leader loss, replica rejoin, backlog/quorum recovery and client reconnect behavior.
- TLS replication and TLS Route access independently.
- An MQSC change, Operator rollout and confirmation that definitions actually changed.
- Storage expansion, retained-PVC behavior, backup/rebuild and planned maintenance.

Argo `Synced` describes desired-resource delivery, not proof of MQ availability. Check QueueManager conditions and MQ state as well. No resources were deployed to a live cluster as part of creating these files.

## IBM references

- [QueueManager API reference](https://www.ibm.com/docs/en/ibm-mq/10.0.x?topic=operator-api-reference-queuemanager-mqibmcomv1beta1)
- [MQ 10.0 Operator license values](https://www.ibm.com/docs/en/ibm-mq/10.0.x?topic=reference-licensing-api-references-mq-operator)
- [Operator Native HA configuration](https://www.ibm.com/docs/en/ibm-mq/9.4.x?topic=operator-configuring-native-ha-using-mq)
- [Supplying MQSC and INI files; ConfigMap update behavior](https://www.ibm.com/docs/en/ibm-mq/9.4.x?topic=manager-example-supplying-mqsc-ini-files)
- [Operator catalog sources and controlled updates](https://www.ibm.com/docs/en/ibm-mq/9.4.x?topic=openshift-adding-mq-operator-catalog-source)
- [CLI subscriptions, including MQ v4.0-sc2](https://www.ibm.com/docs/en/cloud-paks/cp-integration/16.2.0?topic=operators-installing-by-using-cli)
- [MQ Operator/container lifecycle dates](https://www.ibm.com/support/pages/lifecycle-dates-ibm-mq-containers)
