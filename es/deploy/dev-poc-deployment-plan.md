# dev-poc Deployment Plan

## Overview

Pre-flight review and fix of the `dev-poc` ApplicationSet before deploying the
StreamSage POC stack (Event Streams, Kafka Topics, Kafka Users, PostgreSQL,
streamsage-services, streamsage-console) to the dev environment.

Four categories of issues were found during review:
1. **EventStreams instance name mismatch** — base names the instance `es` but all
   topics, users, and service ConfigMaps reference `kafka-es`.
2. **Dev overlay patch overrides storage to `persistent-claim`** — contradicts the
   ephemeral storage intent for the POC.
3. **`min.insync.replicas: 2` in dev patch conflicts with `replicas: 1` on base topics**
   — will cause writes to fail.
4. **Deprecated `bases:` keyword in dev overlay kustomizations** — should be `resources:`.

Scope is limited to the `dev` overlay and base files that affect the dev POC.
No other overlays or environments are touched.

---

## Sub-Task 1 — Fix EventStreams instance name (`es` → `kafka-es`)

**Status:** [x] done

### Intent
Every topic YAML, every user YAML, and all seven service ConfigMaps reference the
EventStreams instance as `kafka-es` (via `eventstreams.ibm.com/cluster: kafka-es` and
`kafka-es-kafka-bootstrap.kafka-dev.svc:9093`). The base manifest and dev patch both
name the instance `es`. Renaming the instance to `kafka-es` in those two files makes
everything consistent without touching the 17+ downstream files.

### Expected Outcomes
- `deploy/apps/base/event-streams/kafka-es.yaml` → `metadata.name: kafka-es`
- `deploy/apps/overlays/dev/event-streams/kafka-es-patch.yaml` → `metadata.name: kafka-es`
- Topics and users will bind to the correct cluster via the `eventstreams.ibm.com/cluster: kafka-es` label.
- Services will connect to `kafka-es-kafka-bootstrap.kafka-dev.svc:9093` as already configured.

### Todo List
1. In `deploy/apps/base/event-streams/kafka-es.yaml`: change `metadata.name` from `es` to `kafka-es`.
2. In `deploy/apps/overlays/dev/event-streams/kafka-es-patch.yaml`: change `metadata.name` from `es` to `kafka-es`.

### Relevant Context
- `deploy/apps/base/event-streams/kafka-es.yaml` — line 3
- `deploy/apps/overlays/dev/event-streams/kafka-es-patch.yaml` — line 4
- All topic yamls in `deploy/apps/base/kafka-topics/` have `eventstreams.ibm.com/cluster: kafka-es`
- All user yamls in `deploy/apps/base/kafka-users/` have `eventstreams.ibm.com/cluster: kafka-es`
- All service configmaps in `deploy/apps/base/streamsage-services/*/configmap.yaml` reference `kafka-es-kafka-bootstrap.kafka-dev.svc:9093`

---

## Sub-Task 2 — Fix dev Event Streams patch: ephemeral storage + correct `min.insync.replicas`

**Status:** [x] done

### Intent
The dev patch currently overrides `storage.type` to `persistent-claim` (contradicting
the POC goal of ephemeral storage) and sets `min.insync.replicas: 2` at the cluster
level while all base topics define only `replicas: 1` — this combination will cause
all topic writes to fail. Both issues are in the single dev patch file.

### Expected Outcomes
- `deploy/apps/overlays/dev/event-streams/kafka-es-patch.yaml`:
  - `storage` block removed from the nodePool (base ephemeral default is inherited).
  - `min.insync.replicas` changed from `2` to `1`.
  - `transaction.state.log.min.isr` changed from `2` to `1`.
  - `offsets.topic.replication.factor`, `transaction.state.log.replication.factor`,
    and `default.replication.factor` all lowered to `1` to match single-replica topics.
- The 3-broker cluster will still start with 3 replicas (good for HA testing) but
  topics will use `replicas: 1` and `min.insync.replicas: 1` — consistent with base topic definitions.

### Todo List
1. In `deploy/apps/overlays/dev/event-streams/kafka-es-patch.yaml`:
   - Remove the `storage` block entirely from the `nodePools[0]` entry.
   - Change `offsets.topic.replication.factor` from `3` → `1`.
   - Change `transaction.state.log.replication.factor` from `3` → `1`.
   - Change `transaction.state.log.min.isr` from `2` → `1`.
   - Change `default.replication.factor` from `3` → `1`.
   - Change `min.insync.replicas` from `2` → `1`.

### Relevant Context
- `deploy/apps/overlays/dev/event-streams/kafka-es-patch.yaml` — lines 13–35
- `deploy/apps/base/event-streams/kafka-es.yaml` — base has `type: ephemeral` at line 47
- All base topic yamls have `replicas: 1` and `min.insync.replicas: '1'`

---

## Sub-Task 3 — Fix deprecated `bases:` → `resources:` in dev overlay kustomizations

**Status:** [x] done

### Intent
Kustomize v4+ deprecated the `bases:` field in favour of `resources:`. ArgoCD uses a
modern Kustomize build and will emit warnings; future versions may reject `bases:` entirely.
Four dev overlay kustomizations are affected.

### Expected Outcomes
All four affected files use `resources:` instead of `bases:`.

### Todo List
1. `deploy/apps/overlays/dev/event-streams/kustomization.yaml` — rename `bases:` → `resources:`.
2. `deploy/apps/overlays/dev/kafka-users/kustomization.yaml` — rename `bases:` → `resources:`.
3. `deploy/apps/overlays/dev/streamsage-services/kustomization.yaml` — rename `bases:` → `resources:`.
4. `deploy/apps/overlays/dev/streamsage-console/kustomization.yaml` — rename `bases:` → `resources:`.

### Relevant Context
- `deploy/apps/overlays/dev/event-streams/kustomization.yaml` — line 6
- `deploy/apps/overlays/dev/kafka-users/kustomization.yaml` — line 6
- `deploy/apps/overlays/dev/streamsage-services/kustomization.yaml` — line 6
- `deploy/apps/overlays/dev/streamsage-console/kustomization.yaml` — line 6

---

## Sub-Task 4 — Clean up AppSet `ignoreDifferences` spurious `kind: Kafka` entry

**Status:** [x] done

### Intent
The AppSet `ignoreDifferences` block includes an entry for `group: eventstreams.ibm.com`
`kind: Kafka`. IBM Event Streams does not expose a `Kafka` CRD — that is a Strimzi type.
This entry will never match anything and is misleading. Remove it to keep the config clean.

### Expected Outcomes
- `deploy/apps/argocd/applicationsets/dev-poc-appset.yaml` — the `kind: Kafka` block is removed.
- Remaining `ignoreDifferences` entries for `EventStreams`, `KafkaTopic`, `KafkaUser`,
  and `Cluster` are retained.

### Todo List
1. In `deploy/apps/argocd/applicationsets/dev-poc-appset.yaml`: remove the four lines
   for the `kind: Kafka` ignoreDifferences entry (lines 104–107).

### Relevant Context
- `deploy/apps/argocd/applicationsets/dev-poc-appset.yaml` — lines 104–107

---

## Pre-flight Checklist (not code changes — manual steps before syncing)

These are operational requirements that must be satisfied before ArgoCD syncs:

- [ ] Secrets `streamsage-postgres-superuser` and `streamsage-postgres-app` exist in namespace `postgres-dev`
- [ ] Secret `ibm-entitlement-key` exists in namespace `kafka-dev` (confirmed already done)
- [ ] Namespace `kafka-dev` exists or ArgoCD has permission to create it (`CreateNamespace=true` is set)
- [ ] Namespace `postgres-dev` exists or ArgoCD has permission to create it
- [ ] Namespace `streamsage-dev` exists or ArgoCD has permission to create it
- [ ] CloudNativePG operator is installed cluster-wide
- [ ] IBM Event Streams operator is installed cluster-wide (confirmed already done)
- [ ] Any existing `dev-scram` EventStreams instance has been deleted before syncing
