# IBM MQ Native HA on Virtual Machines

IBM MQ Native HA is supported directly on Linux virtual machines and bare-metal servers (introduced for Linux hosts in IBM MQ 9.4.x, with base examples targeting 9.4.4+). It brings the same built-in, Raft-based replication model used in containers to traditional VM estates—eliminating the need for shared storage (as in Multi-Instance Queue Managers) or OS-level clustering stacks like Pacemaker and DRBD (as in RDQM).

---

## Architecture and Core Technology

A standard Native HA deployment on VMs consists of **three Linux nodes**, each hosting an instance of the same queue manager:

*   **Active/Replica Model:** One instance acts as the **Active** queue manager, processing messages and writing to its local recovery log. The other two run as **Replicas**.
*   **Raft-Based Consensus & Replication:** Native HA implements a consensus algorithm closely based on Raft (strong leader, log-based elections) over a proprietary wire protocol. Whenever the active instance writes to its recovery log, it replicates those log records to the replicas. Each replica writes to its own local log, acknowledges the write, and updates its own queue data.
*   **Quorum:** At least **2 of the 3 instances** must be available to maintain quorum and elect a new active instance if the current leader fails.
*   **Replicated Logging:** Native HA uses a *replicated log*, which is a linear log with automatic log management and automatic media images enabled. Each VM uses its own local, non-replicated block storage.
*   **Disaster Recovery Extensions:**
    *   **Native HA CRR (Cross-Region Replication):** Connects two 3-node Native HA groups (6 VMs total) as a *Live* group and a *Recovery* group for asynchronous cross-region DR.
    *   **Native HA IRR (In-Region Replication, MQ 10.0.x):** Supports a 2-node configuration across two data centers in the same region with configurable `Strict` or `Eventual` sync consistency.

---

## What Changes Without Kubernetes / OpenShift

When you move Native HA off Kubernetes/OpenShift onto VMs, you lose the platform's built-in orchestration primitives and must replace them at the OS and network layers:

| Capability | In Kubernetes / OpenShift | On Linux VMs |
| :--- | :--- | :--- |
| **Liveness & Auto-Restart** | Kubelet liveness probes + StatefulSet controller | OS service manager (`systemd`) paired with a liveness/monitoring script (IBM provides a `systemd` + Python `mqmonitor@<QMGR>` pattern). |
| **Client & Channel Routing** | Kubernetes Service / OpenShift Route | Comma-separated `CONNAME` list of all three VM addresses on clients/channels so they automatically locate the active instance, or an external load balancer with health checks. |
| **Node Consistency** | Immutable container image | Manual or automated (e.g., Ansible) enforcement: all 3 VMs must be the same node type, run the same MQ version/maintenance level, and use identical install (`/opt/mqm`) and data (`/var/mqm`) paths. |
| **TLS Certificates** | Cert-Manager / K8s Secrets | Manual keystore creation (`runmqakm`) and distribution across all 3 nodes. |

---

## High-Level Deployment Process

1.  **Install IBM MQ on All Three VMs:** Install the identical MQ 9.4.4+ maintenance level on all three Linux hosts (minimum packages: `ibmmq-runtime`, `ibmmq-server`, and `ibmmq-gskit`) using matching directory paths.
2.  **Create the Queue Manager Instances:** As the `mqm` user on each VM (e.g., `alpha`, `beta`, `gamma`), create the queue manager with replicated logging enabled (`-lr`):
    ```bash
    crtmqm -lr alpha -lf 8192 -lp 10 -ls 10 -p 1414 MYQMGR
    ```
    *(Repeat on `beta` and `gamma` with their respective instance names.)*
3.  **Configure TLS for Replication Traffic:** Create a keystore and certificate using `runmqakm` on one node, copy the keystore files to `/var/mqm/qmgrs/MYQMGR/ssl/` on the other two nodes, and set `mqm` group ownership and read permissions.
4.  **Define the Group in `qm.ini`:** On each VM, edit `/var/mqm/qmgrs/MYQMGR/qm.ini` to add the local instance identity and all three peer addresses (typically using port `9414` for intra-group replication, and `9415` if adding CRR):
    ```ini
    NativeHALocalInstance:
       Name=alpha
       CipherSpec=ANY_TLS12
       CertificateLabel=nha-qm-replication
       KeyRepository=/var/mqm/qmgrs/MYQMGR/ssl/keystore

    NativeHAInstance:
       Name=alpha
       ReplicationAddress=alpha.example.com(9414)
    NativeHAInstance:
       Name=beta
       ReplicationAddress=beta.example.com(9414)
    NativeHAInstance:
       Name=gamma
       ReplicationAddress=gamma.example.com(9414)
    ```
5.  **Configure `systemd` Monitoring:** Set up a `systemd` unit and liveness check script so failed or hung instances are automatically restarted.
6.  **Start and Verify Quorum:** Start the queue managers (`strmqm MYQMGR` or via `systemctl`) on all three hosts and verify quorum and roles:
    ```bash
    dspmq -o nativeha -x
    ```
    Confirm that one node reports `ROLE(Active)` and `QUORUM(3/3)`, while the other two report `ROLE(Replica)`.

---

## Documentation, Guides, and Reference Links

### Official IBM Documentation (MQ 9.4.x & 10.0.x)
*   **Native HA Overview (Linux & Containers):** [IBM MQ 9.4.x — Native HA](https://www.ibm.com/docs/en/ibm-mq/9.4.x?topic=availability-native-ha) — Covers prerequisites, package requirements, `systemd` concepts, and client connectivity outside Kubernetes.
*   **Step-by-Step Linux VM Lab:** [Example: Deploying a simple Native HA configuration on Linux](https://www.ibm.com/docs/en/ibm-mq/9.4.x?topic=ha-example-deploying-simple-native-configuration-linux) — Complete walkthrough including `crtmqm -lr`, `runmqakm`, `qm.ini`, `systemd` monitoring, and failover testing.
*   **Adding Cross-Region DR on Linux:** [Example: Adding a recovery group to an existing Native HA configuration on Linux](https://www.ibm.com/docs/en/ibm-mq/9.4.x?topic=nh-example-adding-recovery-group-existing-native-ha-configuration-linux) and [Deploying a simple Native HA CRR configuration on Linux](https://www.ibm.com/docs/en/ibm-mq/9.4.x?topic=nhc-example-deploying-simple-native-ha-crr-configuration-linux).
*   **`qm.ini` Stanza Reference:** [Queue manager configuration files (`qm.ini`)](https://www.ibm.com/docs/en/ibm-mq/9.4.x?topic=multiplatforms-queue-manager-configuration-files-qmini) — Reference for `NativeHALocalInstance`, `NativeHAInstance`, and `NativeHARecoveryGroup`.
*   **MQ 10.0.x In-Region Replication:** [Native HA IRR (IBM MQ 10.0.x)](https://www.ibm.com/docs/en/ibm-mq/10.0.x?topic=recovery-native-ha-irr) — Details on the newer 2-node Linux VM/bare-metal IRR model.

### Architecture Articles & GitHub Resources
*   **HA/DR Comparison:** [IBM Developer — IBM MQ High Availability and Disaster Recovery Options](https://developer.ibm.com/articles/mq-ha-dr-options/) — Compares Native HA on Linux/VMs against RDQM, Multi-Instance QMs, and MQ Clusters.
*   **Native HA Internals:** [IBM Community — Design and Architect IBM MQ Native HA](https://community.ibm.com/community/user/blogs/abhinav-priyadarshi/2025/06/17/design-and-architect-ibm-mq-native-ha-using-mq-con) — Container-focused, but includes a clear breakdown of the Raft-based quorum, replicated log mechanics, and block storage behavior.
*   **GitHub Samples & Topics:**
    *   [ibm-messaging/cp4i-mq-samples](https://github.com/ibm-messaging/cp4i-mq-samples/blob/main/README.md) — Official IBM messaging samples (container-oriented, useful for comparing `qm.ini` and Native HA patterns).
    *   [GitHub Topic: `native-ha`](https://github.com/topics/native-ha) — Community repositories and tooling tagged with Native HA.