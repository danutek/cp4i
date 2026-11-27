# Ishanti Demo Guide: IBM MQ Operations Evolution

**Storyline:** *From RDQM on Cloud VMs → Native HA on VMs (GitHub Actions) → Native HA on Kubernetes/OpenShift (Argo CD) + Governed AI Operations*

**Target Duration:** 35–40 minutes

---

## Live Lab Topology

All three nodes run **IBM MQ 9.4.5.0 (CD)** on **RHEL 9.7 (x86_64)**:

| Node | Private IP | Public SSH | RDQM (`QM1`) | Native HA (`MYQMGR`) |
| :--- | :--- | :--- | :--- | :--- |
| **`kc1`** | `10.240.0.4` | `169.48.154.115` | Primary (`UpToDate`) | `alpha` — Active (`QUORUM 3/3`) |
| **`tejas1`** | `10.240.0.10` | — | Secondary (`UpToDate`) | `beta` — Replica (`INSYNC yes`) |
| **`tejas2`** | `10.240.64.4` | — | Secondary (`UpToDate`) | `gamma` — Replica (`INSYNC yes`) |

---

## Pre-Flight Checklist (2 Minutes Before Demo)

Run from the root of this repository:

```bash
# 1. Confirm both QM1 (RDQM) and MYQMGR (Native HA) are healthy with kc1 Active
./mq/demo/scripts/demo-ops.sh status

# 2. Confirm baseline ISHANTI.* queues exist on MYQMGR
./mq/demo/scripts/demo-ops.sh verify-queues

# 3. Confirm GitHub CLI is authenticated
gh auth status
```

Have these browser tabs open:
1. GitHub repository: `https://github.com/danutek/cp4i`
2. GitHub Actions tab: `https://github.com/danutek/cp4i/actions`
3. Your AI assistant (Antigravity) open in the `cp4i` workspace

> **Order Tip:** Keep `alpha` (`kc1`) as `Active` through **Acts 1, 2, and 4** so GitHub Actions deploys smoothly against `169.48.154.115`, then run the **live failover** at the end of Act 4 (or anytime if you add `tejas1`/`tejas2` SSH access to `MQ_HOSTS`).

---

## Act 1: RDQM vs. Native HA on the Same 3 VMs (~8 min)

### Talking Points
* Validate Ishanti's direction: Native HA on Linux VMs removes the entire **DRBD + Pacemaker + Corosync + LVM** clustering layer that made RDQM complex to install and patch.
* Both queue managers below are running side-by-side on the exact same 3 RHEL 9.7 VMs.

### Live Commands
```bash
./mq/demo/scripts/demo-ops.sh status
```

Point out side-by-side:
1. **`QM1` (RDQM):** `rdqmstatus` + `drbdadm status` — block-level replication, kernel module dependency, Pacemaker cluster stack.
2. **`MYQMGR` (Native HA):** `dspmq -m MYQMGR -o nativeha -x` — built-in MQ log replication over TLS (`ANY_TLS12_OR_HIGHER`), `QUORUM(3/3)`, `INSYNC(yes)`, `BACKLOG(0)`, supervised cleanly by `systemd` (`mqmonitor@MYQMGR.service`).

Optionally prove live persistence:
```bash
./mq/demo/scripts/demo-ops.sh put-test
./mq/demo/scripts/demo-ops.sh get-test
```

---

## Act 2: Git-Driven Operations on VMs with GitHub Actions (~10 min)

### Talking Points
* **Honest framing:** *"Argo CD reconciles Kubernetes APIs—you can't point it at Linux VMs. For VM-based Native HA, **GitHub Actions** is the right Git-driven automation layer."*
* **Enterprise security note:** In this public demo repo, GitHub-hosted runners validate PRs (zero secrets exposed) and deploy on merge to `main` via GitHub Secrets. Inside Ishanti's **private GitHub Enterprise** repos, you would run a **self-hosted runner inside the VPC** so SSH/port 22 is never exposed externally.
* **Replicated vs. Host-Local split** (reference [native_ha_runbook.md](../NativeHA/native_ha_runbook.md#replicated-vs-host-local-quick-reference)):
  * **MQSC objects** (queues, channels, `AUTHREC`, `CHLAUTH`) only need to be applied to the **Active** node—Native HA replicates them automatically to `tejas1` and `tejas2`.
  * **Host-local state** (`qm.ini`, TLS keystores, `systemd`, OS users/patching) must still be synchronized across all 3 VMs via config management.

### Live Demo Steps
1. Open [myqmgr.mqsc](./myqmgr.mqsc) and [mq-nativeha-demo.yml](../../.github/workflows/mq-nativeha-demo.yml) briefly to show the declarative MQSC and the CI guardrails in [validate-mqsc.sh](./scripts/validate-mqsc.sh):
   * Forces `REPLACE` (idempotency)
   * Forces `DEFPSIST(YES)` on `QLOCAL` queues (so Native HA log replication actually protects messages!)
   * Blocks disabling `CHLAUTH` / `CONNAUTH`
   * Blocks accidental `DELETE` / `CLEAR`
2. Trigger a dry-run or live deploy directly from GitHub Actions (`Actions → MQ Native HA VM GitOps Deploy → Run workflow`) or via CLI:
   ```bash
   gh workflow run mq-nativeha-demo.yml -f dry_run=false
   gh run watch
   ```
3. Show the **GitHub Actions Job Summary** displaying the validation checks, deployed `ISHANTI.*` objects, and verified `QUORUM(3/3)` + `INSYNC(yes)`.

### Pivot to Act 3
> *"GitHub Actions is **push-based** (event-driven). What happens when someone edits `qm.ini` on `tejas2` at 2 AM, a VM dies and has to be rebuilt from scratch, or you need rolling upgrades across 20 queue managers × 5 environments? That's where Kubernetes + Argo CD shines."*

---

## Act 3: Same Native HA Engine on Kubernetes / OpenShift + Argo CD (~8 min)

### Talking Points
* Show your existing GitOps repos—[mq/k8s/README.md](../k8s/README.md) (plain Kubernetes/AKS) and [mq/ocp/README.md](../ocp/README.md) (OpenShift + IBM MQ Operator).
* Walk through **20 queue managers × 5 environments** (`dev` single-instance → `test`/`qa`/`perf`/`prod` 3-AZ Native HA) defined declaratively with Kustomize overlays:
  * **Continuous reconciliation:** Argo CD continuously detects and reverts drift.
  * **Self-healing:** Lost pod is rescheduled automatically, reattaches its PVC, and rejoins Native HA quorum with zero manual intervention.
  * **Gated promotion:** Automated sync in `dev`; PR + manual sync approval in `prod`.
* **Key reassurance for Ishanti:** Native HA on VMs + GitHub Actions uses the **exact same MQ Native HA replication engine and MQSC artifacts** as Kubernetes—so starting on VMs today is a clean stepping stone, not throwaway work.

### Optional Live Command (Render a Prod Kustomize Manifest)
```bash
kubectl kustomize mq/k8s/workloads/mqm/qm-gclr-q/overlays/prod/cus | head -n 60
```

---

## Act 4: Governed AI-Assisted MQ Operations (~10 min)

### Framing for Financial Services
> *"In an enterprise like Ishanti, AI should **never** bypass change control to mutate production ad hoc. Instead, pair AI with GitOps: AI handles triage, authoring, and verification; Git + GitHub Actions / Argo CD enforce review, policy, and auditability."*

### Live Prompt 1 — Estate-Wide Triage (Read-Only)
Paste into Antigravity:
> `Inspect kc1 (169.48.154.115) and give me a health comparison of QM1 (RDQM) and MYQMGR (Native HA), including where each primary is running, quorum/sync status, and current depth of all ISHANTI.* queues.`

### Live Prompt 2 — AI + GitOps Governed Change (The Crowd-Pleaser)
Paste into Antigravity:
> `Add a new persistent local queue named ISHANTI.ORDERS.IN (max depth 50000, backout queue ISHANTI.DEMO.DLQ) to mq/demo/myqmgr.mqsc. Create a feature branch, commit the change, and open a GitHub pull request so GitHub Actions validates it.`

Walk Ishanti through the governance loop live:
1. Antigravity edits [myqmgr.mqsc](./myqmgr.mqsc), runs `validate-mqsc.sh`, pushes a branch, and opens a PR via `gh`.
2. **GitHub Actions runs `validate-mqsc` automatically on the PR** (show the green check in GitHub).
3. You review and click **Merge Pull Request** (human approval gate!).
4. **GitHub Actions automatically deploys `ISHANTI.ORDERS.IN` to `MYQMGR`** and verifies `QUORUM(3/3)`.
5. Ask Antigravity:
   > `Verify that ISHANTI.ORDERS.IN is live on MYQMGR and confirm Native HA is still 3/3 in sync.`

### Live Prompt 3 — Production AI Architecture (MCP)
Briefly show [mq/mq_mcp/README.md](../mq_mcp/README.md):
* Explain that while the lab demo uses SSH for simplicity, in production you expose MQ through a scoped, RBAC-audited **Model Context Protocol (MCP) server** talking to the **IBM MQ REST API** (so AI never needs SSH keys or shell access on production brokers).

### Optional Finale — Live Native HA Failover
If you want to end with a live resilience test (putting persistent messages first, failing over `alpha` on `kc1` to `tejas1`/`tejas2`, and showing `alpha` rejoin as `Replica` with `QUORUM(3/3)` and `BACKLOG(0)`):
```bash
./mq/demo/scripts/demo-ops.sh put-test ISHANTI.DEMO.IN
./mq/demo/scripts/demo-ops.sh failover --confirm
```

---

## Comparison Summary Table

| Dimension | RDQM on VMs *(Today)* | Native HA on VMs + GitHub Actions *(Near-Term)* | Native HA on K8s/OCP + Argo CD *(Target)* |
| :--- | :--- | :--- | :--- |
| **Replication Layer** | DRBD + Pacemaker (OS/kernel-coupled) | MQ-native log replication over TLS | MQ-native log replication over TLS |
| **Deployment Model** | Manual / Ansible scripts | Push-based CI/CD (GitHub Actions on PR/merge) | Pull-based GitOps (Argo CD continuous reconcile) |
| **Drift & Self-Healing** | Manual / custom alerts | Scheduled checks + Ansible/Terraform | Built-in (K8s controller + Argo CD) |
| **Host-Local State (`qm.ini`, certs)** | Managed per VM | Synced across 3 VMs via automation | Declarative ConfigMaps / Secrets / CSI |
| **AI Operations Layer** | Read-only triage + MCP | AI opens PR → GitHub Actions deploys | AI opens PR → Argo CD syncs |

---

## Post-Demo Reset

To clean up between rehearsals:
```bash
./mq/demo/scripts/demo-ops.sh reset
```
And revert any demo PR queue added to `mq/demo/myqmgr.mqsc` before the next run.
