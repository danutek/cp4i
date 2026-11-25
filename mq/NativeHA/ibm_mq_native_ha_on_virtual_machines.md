# IBM MQ Native HA on Virtual Machines

IBM MQ Native HA is available directly on supported Linux virtual machines and bare-metal servers from **IBM MQ 9.4.4**. It uses MQ-managed recovery-log replication instead of shared queue-manager storage or the Pacemaker/DRBD stack used by RDQM.

**Scope:** Architecture, deployment, and operational guidance for a three-instance Linux Native HA queue manager. Cross-Region Replication (CRR) and In-Region Replication (IRR) are described separately because they have different availability and recovery behavior.

**Documentation basis:** IBM MQ 9.4.x and 10.0.x documentation, reviewed on 2026-11-25. Linux Native HA starts at 9.4.4, a Continuous Delivery release; do not assume that a 9.4.0 LTS fix pack includes it. IRR requires a release supporting that feature, covered here by the 10.0.x documentation. The examples below have been checked against documentation, but have not been executed as part of this document's review.

## 1. Release, Platform, and Entitlement Prerequisites

Before provisioning, record the exact MQ release, maintenance level, Linux distribution, processor architecture, and entitlement. Check the [IBM MQ system requirements][requirements] for that combination.

- Production Linux Native HA/CRR requires IBM MQ Advanced entitlement or the applicable Native HA and CRR add-on for Linux. The add-on does not grant unrelated Advanced capabilities.
- IBM provides distinct production, non-production, and replica entitlement components. For CRR, include the Recovery group's leader and replicas in the licensing assessment; do not assume that only the current Live active instance matters.
- On Linux, apply the appropriate installation entitlement tags using `setmqinst`, following the [license information][licensing].
- Initially install all instances at the same MQ version and maintenance level, with the same processor architecture and consistent installation/data paths. Temporary differences during an approved upgrade are addressed in Section 11.
- `/opt/mqm` and `/var/mqm` are defaults, not mandatory paths. If changed, apply the same layout on every instance and update service definitions, scripts, and keystore references.

Minimum server components depend on the packaging format:

| Distribution/package format | Minimum components |
| --- | --- |
| RPM-based Linux, such as supported RHEL configurations | `MQSeriesRuntime`, `MQSeriesServer`, `MQSeriesGSKit` |
| Debian packages, such as supported Ubuntu configurations | `ibmmq-runtime`, `ibmmq-server`, `ibmmq-gskit` |

Install sample-program packages separately if using the put/get samples in Section 10. Accept the MQ license and complete Linux preparation, including users/groups, limits, permissions, and filesystem requirements, before creating instances.

Sources: [Linux Native HA availability][whats-new], [Linux installation][rpm-install], and [licensing][licensing].

## 2. Choose the HA and DR Model

**RPO (Recovery Point Objective)** describes the amount of work that can be lost at recovery. **RTO (Recovery Time Objective)** describes how long the service can be unavailable. Measure the application service, including reconnection and transaction recovery, when assessing RTO.

| Model | Instances for one queue manager | Replication | Automatic failover | Recovery implications |
| --- | --- | --- | --- | --- |
| Native HA | Three instances in one group | Synchronous quorum-based logging within the group | Between instances when a usable majority remains | Protects acknowledged recoverable work against a tolerated instance failure |
| Native HA CRR | Two three-instance groups: Live and Recovery; six instances total | Synchronous within each group; asynchronous between groups | Within a group; site promotion is an operator-controlled DR procedure | Unplanned site loss can lose work not yet replicated; a properly completed planned switchover can achieve RPO 0 |
| Native HA IRR | Two single-instance groups: Live and Recovery; two instances total | Synchronous between groups when connected and synchronized | **No automatic HA failover**; manual DR switching | `Strict` prioritizes consistency; `Eventual` permits continued work during replication loss, with possible data loss at failover |

**IRR is not a two-node replacement for a three-node HA group.** IBM specifies locations within approximately 100 miles/160 km and network latency up to 5 ms. IRR is supported on Linux VMs/bare metal in the cited 10.0.x documentation, not in containers.

With IRR `Strict`, the default, logged work requires the groups to be connected and synchronized, supporting RPO 0 for planned and unplanned failover under the documented failure model. Loss of that relationship can stop work and cause the Live instance to abdicate. With `Eventual`, the Live instance can progress without Recovery acknowledgements while replication is unavailable, so an unplanned failover can lose that work. When synchronized, both settings use synchronous replication. Select the mode according to the agreed RPO and availability requirements.

Sources: [CRR/IRR comparison][dr-comparison] and [IRR behavior][irr].

## 3. Architecture, Quorum, and Message Durability

A three-instance group represents **one logical queue manager** with one active instance and two replicas. Each instance has its own queue-manager data and recovery log. Replicas receive log records, persist them, and replay them into their own queue-manager state.

Native HA uses Raft-based majority decisions. Once a majority of log copies acknowledges a required write, MQ can confirm the logged operation to the application. It does not wait for both replicas to acknowledge every write. A third instance is a full replica, not a lightweight witness.

Two powered-on VMs are not necessarily a usable quorum: the instances must communicate and have the required log state. If the active instance cannot form quorum, it cannot progress work requiring log writes and abdicates. A partitioned instance must not be independently promoted to bypass that protection.

### Message and transaction semantics

- Committed persistent work acknowledged under quorum has an RPO of zero for a tolerated single-instance HA failure. Do not extend that guarantee to loss of the entire group or to asynchronous CRR data that has not reached Recovery.
- An `MQPUT` inside a unit of work is not equivalent to a successful `MQCMIT`. Distinguish committed, uncommitted, and backed-out work in application tests.
- A disconnect near commit can leave an application uncertain whether its transaction completed. Reconnection alone does not settle that uncertainty; use appropriate transaction recovery and business-level duplicate handling.
- **Non-persistent messages are discarded when Native HA leadership changes, regardless of `NPMCLASS`.** Do not promise that every message survives failover.

Replicated logging has the characteristics of linear logging with automatic log management and automatic media images. It does not require shared storage or storage-layer replication; underlying cloud or enterprise disks can still have their own resilience mechanisms.

Sources: [Native HA overview][nha], [logging types][logging], [non-persistent message behavior][mqmd], and [client reconnection][reconnect].

## 4. VM Placement and Infrastructure Planning

The following are design recommendations to validate against the selected platform and workload:

- Place instances in independent hypervisor, power, and network failure domains. Configure VM anti-affinity where available. Three VMs on one physical host do not protect against that host failing.
- Keep the HA group within the same geographical region. Assess correlated failures in shared SANs, storage pools, DNS, switches, and virtualization management.
- Size every instance to run the entire queue-manager workload. A replica is not a reduced-capacity standby. Reserve enough resources for replication and catch-up as well as normal processing.
- Give each instance independent queue-manager storage with suitable filesystem semantics, latency, throughput, and capacity. Do not point instances at the same queue-manager directory.
- Measure replication round-trip time and log-write latency under load. Avoid applying the IRR 5 ms limit as a universal sizing rule for every Native HA topology.
- Synchronize clocks, preferably with NTP, and use consistent time zones for log correlation.

Example inventory:

| Host | Local instance name | Client listener | Intra-group replication |
| --- | --- | --- | --- |
| `alpha.example.com` | `alpha` | TCP 1414 | TCP 9414 |
| `beta.example.com` | `beta` | TCP 1414 | TCP 9414 |
| `gamma.example.com` | `gamma` | TCP 1414 | TCP 9414 |

These ports are example choices. Permit the configured replication traffic among the three hosts and application/channel traffic to the possible active hosts. For multiple queue managers on one host, allocate distinct listening ports. CRR needs separately configured inter-group connectivity; 9415 is an example choice, not a substitute for checking the actual group configuration.

## 5. Responsibilities Outside Kubernetes/OpenShift

| Capability | Kubernetes/OpenShift deployment | Linux VM deployment |
| --- | --- | --- |
| Instance supervision | Probes and workload controllers, depending on deployment | OS supervision, such as IBM's `mqmonitor.py` and systemd sample |
| Active-instance routing | A correctly configured Service; TLS routes where applicable | Client/channel address list or a load balancer that selects the active instance |
| Client reconnection | Still requires suitable client/application behavior | Still requires suitable client/application behavior |
| Configuration delivery | Images, manifests, mounted configuration | Managed files, package automation, and configuration management |
| Certificates | Secret/certificate-management integration when configured | Explicit key/trust provisioning, renewal, and distribution |
| Placement and capacity | Node placement and storage policies | VM anti-affinity, resource allocation, and infrastructure policies |

Neither platform makes application transaction recovery automatic merely by providing an HA queue manager.

## 6. Deploy a Three-Instance Group

The commands create a **new example group** named `MYQMGR`. They do not migrate an existing queue manager or its messages.

### 6.1 Install and verify MQ

Install the same supported MQ level and required components on each host. As `mqm`, select the installation environment and verify it:

```bash
. /opt/mqm/bin/setmqenv -s
dspmqver
```

Validate the infrastructure plan before creating the queue manager. Keep privileged package/service administration separate from MQ administration.

### 6.2 Create an instance on each host

On **alpha**:

```bash
crtmqm -lr alpha -lf 8192 -lp 10 -ls 10 -p 1414 MYQMGR
```

On **beta**:

```bash
crtmqm -lr beta -lf 8192 -lp 10 -ls 10 -p 1414 MYQMGR
```

On **gamma**:

```bash
crtmqm -lr gamma -lf 8192 -lp 10 -ls 10 -p 1414 MYQMGR
```

The queue-manager name is identical; the replica instance names are unique. Keep log sizing consistent. These values reproduce IBM's lab example and are not production sizing recommendations; see Section 9.

### 6.3 Provision replication TLS

Provision the keystore, personal certificate/private key, and peer trust required by the chosen certificate design. The example expects the repository at `/var/mqm/qmgrs/MYQMGR/ssl/keystore.kdb` and certificate label `nha-qm-replication` on each host. Provide a usable stash file or configure the supported encrypted repository-password mechanism. Restrict file access to the required administrators and MQ service identity.

IBM's [simple Linux lab][linux-lab] creates one self-signed certificate with `runmqakm` and copies the keystore files to all three hosts. That is a lab shortcut; IBM explicitly warns that the example is not a production certificate-management design. Section 8 covers production requirements. Never commit private keys, stash files, or real passwords to the example repository.

### 6.4 Configure each qm.ini

Back up each instance's configuration before editing. Update the generated `NativeHALocalInstance` stanza rather than appending a second one. On alpha, configure:

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

On beta and gamma, change **only the local `Name`** to `beta` or `gamma`; retain the same three-member address list and the agreed TLS settings. The repository path omits the `.kdb` extension as supported by MQ. `ANY_TLS12` follows the IBM lab; select a supported CipherSpec/protocol policy appropriate to the deployed release and organization.

These TLS attributes protect **replication traffic**. They do not configure SVRCONN/client-channel TLS, authentication, CHLAUTH, or application authorization.

Source: [Linux deployment example][linux-lab] and [NativeHALocalInstance reference][local-stanza].

### 6.5 Install monitoring and establish one lifecycle owner

Use IBM's [monitoring, restarting, and ending instances][monitor] instructions and the sample corresponding to the installed MQ level. Check whether `/opt/mqm/samp/mqmonitor.py` and `mqmonitor@.service` are supplied; if not, obtain the matching IBM-documented example. Adapt paths for a non-default installation.

For the installed sample and default paths, a service setup can use:

```bash
sudo ln -s /opt/mqm/samp/mqmonitor@.service /etc/systemd/system/mqmonitor@.service
sudo systemctl daemon-reload
sudo systemctl enable mqmonitor@MYQMGR
sudo systemctl start mqmonitor@MYQMGR
```

Check any existing service file before creating the link. Apply the setup on each host. IBM's sample checks instance state periodically and attempts restart when necessary; it complements MQ's own quorum/election behavior.

**Once the monitor owns the instance, use systemd for its lifecycle:**

```bash
sudo systemctl status mqmonitor@MYQMGR
sudo systemctl stop mqmonitor@MYQMGR
sudo systemctl start mqmonitor@MYQMGR
```

Do not use `strmqm` and `endmqm` interchangeably with these service operations. A monitored instance stopped directly with `endmqm` can be restarted by the monitor. IBM's lab uses direct MQ commands during initial bootstrap before adding supervision; this procedure establishes supervision before normal operation.

### 6.6 Validate the group

Run on each host as an authorized MQ administrator:

```bash
dspmq -m MYQMGR -o nativeha -x
```

Expect one `ROLE(Active)`, two `ROLE(Replica)`, and a stable healthy group with `QUORUM(3/3)`. Verify peer connectivity, `INSYNC(yes)`, `HASTATUS(Normal)`, and backlog returning to zero. Investigate TLS/configuration errors in the MQ error logs and service journal:

```bash
sudo journalctl -u mqmonitor@MYQMGR --since '15 minutes ago'
```

A brief catch-up period after startup is different from a sustained or growing backlog. `QUORUM(2/3)` can occur while the third instance is connected but still catching up; process existence alone does not prove that instance can acknowledge current writes.

Source: [Native HA troubleshooting][troubleshooting].

## 7. Client and Queue-Manager Channel Connectivity

### Locate the active instance

For clients using a CCDT, a representative client-connection entry is:

```mqsc
DEFINE CHANNEL(APP.SVRCONN) CHLTYPE(CLNTCONN) TRPTYPE(TCP) +
  CONNAME('alpha.example.com(1414),beta.example.com(1414),gamma.example.com(1414)') +
  QMNAME(MYQMGR) DEFRECON(QMGR)
```

This illustrates a **CLNTCONN entry in a client CCDT**, not the server's SVRCONN definition. Provision the corresponding server channel, TLS, identities, and least-privilege authorities separately. Distribute the CCDT and configure clients to use it. Sender channels can also use an appropriate connection-name list; their retry settings govern reconnection attempts.

An external load balancer is an alternative, but its readiness check must select the active instance rather than merely a running VM or open replication port. Validate behavior during election and any TLS termination/passthrough design.

### Enable reconnection and application recovery

Address discovery and automatic client reconnection are separate concerns. For applicable MQI clients, enable same-queue-manager reconnection using `DEFRECON(QMGR)` or `MQCNO_RECONNECT_Q_MGR`, as appropriate. Check the specific API: IBM MQ classes for Java and JMS do not have identical reconnection capabilities or configuration.

Test connection failure detection, reconnection timeouts, open-object recovery, and transaction outcomes. Include consumer duplicate handling and coordination with external databases where needed. Measure recovery from the application's perspective; election time alone is not the service RTO.

**Planned shutdown is a separate test case.** Ordinary `endmqm` shutdown does not itself request automatic client reconnection; IBM documents `-r` or `-s` for reconnection/switchover behavior. Inspect the stop action used by the installed monitoring service and define the intended planned-maintenance behavior. Keep systemd as lifecycle owner; do not bypass its monitor just to issue an MQ shutdown command. The service stop action and application recovery policy must be designed together.

Sources: [Automatic client reconnection][reconnect], [channel reconnection defaults][channel-options], and [endmqm shutdown behavior][endmqm].

## 8. Production Certificate Management

Treat replication and application-channel TLS as separate configurations and test both.

1. Define certificate issuance, trust anchors, supported algorithms, identities, and the approved scope of private-key sharing. Use an appropriate CA-based design; do not automatically carry the shared self-signed lab key into production.
2. Secure key repositories, stash files, encrypted-password initial keys, and backups. Keep paths and permissions valid on every instance that might become active.
3. Monitor certificate expiration and document revocation and renewal responsibilities.
4. Plan trust overlap when changing issuing CAs or certificates, and validate replication after each instance returns.
5. Follow the release-specific procedure for activating replication TLS changes. **`REFRESH SECURITY TYPE(SSL)` does not refresh the Native HA key repository.** Use the documented restart/change process and preserve quorum.
6. Validate CRR/IRR inter-group TLS separately when those features are configured.

Sources: [Native HA TLS configuration][local-stanza], [multiple-certificate example][multiple-tls], and [REFRESH SECURITY restrictions][refresh-security].

## 9. Log, Storage, and Network Sizing

Native HA's recovery log must support transaction activity, media imaging, replication, and replica recovery. A circular-log workload's disk allocation is not automatically sufficient after moving to replicated logging.

For the lab command, `-lf 8192` selects 8,192 pages of 4 KiB: **32 MiB per extent**. Ten primary plus ten secondary extents represent a nominal 640 MiB active-log sizing example, **not a 640 MiB filesystem recommendation**. Additional retained log data and recovery needs require capacity. Extent size is fixed at creation; keep extent size and applicable log settings consistent across instances.

A sizing exercise should include:

- Peak log generation, transaction duration, persistent-message sizes/rates, and queue depths.
- Log-write latency and throughput on each instance, including media-image activity.
- Replica catch-up requirements, restart/rebase behavior, and usable free space under degraded operation.
- Replication bandwidth during normal traffic and recovery, plus CPU headroom for associated processing.
- CRR backlog and DR recovery objectives where applicable.
- Capacity and latency alerts based on measured workload, rather than a universal message-rate threshold.

Review automatic media-image scheduling and log-management settings for the chosen release. Deep queues can increase image volume and I/O contention. Do not manually remove retained log files to recover space without following MQ's documented recovery procedure.

Sources: [Log configuration and media imaging][nha10], [logging types][logging], and [performance considerations][log-performance].

## 10. Operational Monitoring and Acceptance Tests

### Monitor health over time

| Indicator | Operational use |
| --- | --- |
| `ROLE`, `INSTANCE` | Identify the actual active instance and the two replicas |
| `QUORUM` | Detect loss of resilience; a healthy baseline is 3/3 |
| `INSYNC`, `HASTATUS`, connectivity fields | Confirm replicas are participating and healthy |
| `BACKLOG` trend | Distinguish short recovery catch-up from a sustained replication deficit |
| Log/filesystem free space and disk latency | Detect resource exhaustion or delayed acknowledgements |
| Replication network round-trip time | Correlate communication delays with messaging latency |
| MQ error logs, FDCs, and service restarts | Investigate configuration, TLS, storage, and supervision failures |

Configure release-appropriate MQ statistics and infrastructure monitoring. Native HA replication metrics are available on MQ system topics; additional log-latency statistics are documented from 9.4.5. Alert on time spent degraded and application impact, not only whether processes are running.

Source: [MQ system-topic metrics][metrics].

### Prepare a non-production test

On the active instance, define a dedicated test queue through `runmqsc MYQMGR`:

```mqsc
DEFINE QLOCAL(NHA.TEST) DEFPSIST(YES)
```

With the sample programs installed, use `amqsput NHA.TEST MYQMGR` on the active host to put uniquely identifiable test messages. After failover, use `amqsget NHA.TEST MYQMGR` on the new active host to verify them. These local-bindings samples test queue-manager recovery; **also run a separate client-based test** using the production client API and connection/reconnection settings.

The test queue and messages must be dedicated to the exercise. Record successful operations, commit outcomes, roles, timestamps, and message identifiers before injecting faults.

### Failure and recovery matrix

| Test | Expected behavior / acceptance evidence |
| --- | --- |
| Stop one replica through systemd | The remaining usable majority continues; monitoring reports reduced redundancy |
| Restart that replica | It catches up; backlog settles and the group returns to the healthy baseline |
| Stop the active service | Verify role transition and retained persistent messages; record planned-shutdown client behavior separately from abrupt-failure recovery |
| Abruptly lose the active VM | Verify the same data/application objectives under an actual instance failure, not just a graceful stop |
| Isolate the active from both peers | It cannot continue quorum-dependent logged work; a connected eligible majority can elect an active instance |
| Lose two usable instances | The remaining instance must not be treated as an independently writable queue manager; restore quorum |
| Return a stale instance | Confirm catch-up/rebase and subsequent participation before counting it as restored redundancy |
| Change leader with non-persistent test messages | Confirm that the application tolerates their loss; do not apply the persistent-message expectation |

Run disruptive network, storage-failure, and multi-node tests only in an appropriate test environment with a recovery plan. Set measurable acceptance targets for application outage, commit uncertainty handling, message reconciliation, and replica catch-up. Do not promise a fixed RTO without measurement.

## 11. Maintenance and Upgrade Procedure

**Fix-pack updates and changes to version/release/modification levels are not equivalent.** A higher `V.R.M` instance cannot write log data to a lower `V.R.M` replica. Election preferences and replica eligibility therefore change during an upgrade. A fix-pack-only change to `F` does not have that same restriction, but mixed levels should still be temporary.

Use the [Native HA upgrade instructions][upgrade] for the exact source and target levels. Plan the instances as one queue manager, upgrade them close together, and avoid leaving one upgraded instance under extended observation while the rest remain at an older level.

For a change whose supported procedure allows rolling instance maintenance:

1. Confirm the group is healthy, collect configuration/recovery material, and verify the approved compatibility and rollback plan.
2. Stop one replica using `systemctl stop mqmonitor@MYQMGR` on that host. Apply the installation maintenance according to the distribution-specific IBM instructions.
3. Start its monitor again and verify the required health/synchronization state before moving on, where the mixed-level compatibility permits that state.
4. Repeat for the other replica. If the next change requires a leadership transition, confirm that the remaining instances can support the intended role and quorum.
5. Move service away from the old active using the approved lifecycle procedure, maintain that instance, and return it to the group.
6. Verify the target level on every host, restored replication, application recovery, and absence of sustained backlog.

This is a planning sequence, not permission to use an arbitrary rolling path. Where IBM's source/target migration rules require a different sequence or outage, those rules govern. Do not assume that reinstalling an older MQ binary reverses a completed queue-manager migration.

## 12. Backup, Restore, and Existing-Queue-Manager Migration

HA replicas and a DR group are not substitutes for a tested backup/restore and rebuild strategy. A replicated logical error or unintended message consumption can reach other copies.

Maintain separate recovery material for:

- MQ object and authority definitions, with an appropriate export such as `dmpmqcfg`; an export does not back up queued messages or recovery logs.
- Each instance's `qm.ini`, installation inventory, `/var/mqm/mqs.ini` where applicable, and service definitions. Preserve the intended unique local identity when rebuilding a host.
- Keystores, trust material, protected repository credentials, exits, and other externally managed dependencies.
- Application connection configuration and the supported procedure for restoring message/log state when that is part of the recovery objective.

Do not assume recovery-log replication distributes arbitrary OS files or certificate changes. Use configuration management for those assets. Follow a release-appropriate IBM backup/restore procedure and prove it in an isolated exercise; a live filesystem copy or unrelated VM snapshots must not be assumed to form a consistent, restorable MQ backup.

When migrating an existing queue manager, separately plan definitions/authorities, messages, certificates, application cutover, rollback, and outage requirements. The `crtmqm` commands in Section 6 create new instances; they are not an in-place conversion or a message migration procedure.

Reference: [Configuration-file management and backup considerations][ini-management].

## 13. Add CRR or IRR as a Separate DR Design

### CRR

Use the [Linux CRR example][crr-lab] or [add a recovery group][add-recovery] procedure to configure the second three-instance group, group identities, inter-group addresses, and TLS. Validate both local groups before assessing DR replication.

Monitor group-level status with:

```bash
dspmq -m MYQMGR -o nativeha -g
```

Record the Recovery group's recoverable position/time, synchronization state, and backlog. For a planned switchover, follow IBM's synchronization and role-change sequence. For an unplanned promotion, assess the recovery point, prevent the previous Live site from serving independently, and explicitly handle client routing and subsequent failback/reconciliation. Loss of the WAN link is not by itself proof that the remote site has failed.

### IRR

Use the [IRR configuration guide][irr-create]. IRR has one instance per group and a manual DR transition; do not apply three-node quorum operations to it.

Within an otherwise complete `NativeHARecoveryGroup` configuration, the relevant synchronization attributes include:

```ini
SyncReplication=Yes
SyncConsistency=Strict
```

`Eventual` is the alternative consistency setting described in Section 2. These two lines alone are not a complete IRR configuration. TLS is mandatory between the groups. Test loss of the Recovery instance and replication link as well as loss of Live, because the selected consistency setting changes service availability.

For an unplanned failover, inspect `RCOVLSN` and `RCOVTIME` and use IBM's documented procedure to disable replication toward the failed group and establish the intended Live role. Do not promote both groups independently. Include the process for re-establishing replication after the original site returns.

Sources: [IRR semantics][irr] and [unplanned IRR failover][irr-failover].

## 14. Deployment Acceptance Checklist

- Exact supported release/platform and Linux Native HA entitlement are recorded.
- Three-instance HA, six-instance CRR, or two-instance IRR is explicitly selected.
- VM failure domains, capacity, DNS, ports, clock synchronization, and storage dependencies are documented.
- Unique instance identities and consistent group configuration are verified.
- Replication TLS and application-channel security have been validated separately.
- Systemd monitoring owns instance start/stop and survives a host reboot.
- Roles, synchronization, quorum, and backlog reach the expected healthy baseline.
- Persistent-message, transaction-outcome, and client-reconnection tests pass.
- Non-persistent-message behavior is understood by application owners.
- Monitoring, certificate rotation, maintenance, backup/rebuild, and DR procedures have owners and tested recovery objectives.

## 15. Reference Links

### Authoritative IBM Documentation

- [Native HA on Linux: architecture and prerequisites][nha]
- [Native HA first available on Linux in MQ 9.4.4][whats-new]
- [IBM MQ licensing and Linux Native HA entitlement][licensing]
- [IBM MQ 9.4 system requirements][requirements]
- [Installing MQ on Linux using RPM][rpm-install]
- [Example: simple Native HA configuration on Linux][linux-lab]
- [Monitoring, restarting, and ending queue-manager instances][monitor]
- [NativeHALocalInstance stanza][local-stanza]
- [Types of logging][logging]
- [Native HA log configuration and media-image scheduling, MQ 10.0.x][nha10]
- [Performance implications of moving from circular to replicated logging][log-performance]
- [Non-persistent-message behavior in Native HA][mqmd]
- [Automatic client reconnection][reconnect]
- [Client-channel reconnection options][channel-options]
- [endmqm shutdown and reconnection behavior][endmqm]
- [Troubleshooting Native HA/CRR on Linux][troubleshooting]
- [Native HA replication metrics][metrics]
- [Upgrading Native HA configurations][upgrade]
- [Configuration-file management and backup considerations][ini-management]
- [REFRESH SECURITY restrictions][refresh-security]
- [Using multiple TLS certificates with Native HA CRR on Linux][multiple-tls]
- [Linux CRR deployment example][crr-lab]
- [Adding a Recovery group to an existing Linux group][add-recovery]
- [Comparison of CRR and IRR][dr-comparison]
- [IRR behavior and consistency settings][irr]
- [Creating an IRR configuration][irr-create]
- [Unplanned IRR failover][irr-failover]

### Additional Architecture and Sample Material

- [IBM Developer: MQ high availability and disaster recovery options](https://developer.ibm.com/articles/mq-ha-dr-options/)
- [IBM Community: Native HA architecture using MQ containers](https://community.ibm.com/community/user/blogs/abhinav-priyadarshi/2025/06/17/design-and-architect-ibm-mq-native-ha-using-mq-con) — container-focused background.
- [IBM messaging CP4I MQ samples](https://github.com/ibm-messaging/cp4i-mq-samples/blob/main/README.md) — container examples, not a replacement for the Linux procedures above.

[nha]: https://www.ibm.com/docs/en/ibm-mq/9.4.x?topic=configurations-native-ha
[whats-new]: https://www.ibm.com/docs/en/ibm-mq/9.4.x?topic=wncim9-whats-new-in-mq-944-multiplatforms-advanced-entitlement-only
[licensing]: https://www.ibm.com/docs/en/ibm-mq/9.4.x?topic=mq-license-information
[requirements]: https://www.ibm.com/support/pages/system-requirements-ibm-mq-94
[rpm-install]: https://www.ibm.com/docs/en/ibm-mq/9.4.x?topic=imlur-installing-first-mq-installation-linux-using-rpm-command
[linux-lab]: https://www.ibm.com/docs/en/ibm-mq/9.4.x?topic=ha-example-deploying-simple-native-configuration-linux
[monitor]: https://www.ibm.com/docs/en/ibm-mq/9.4.x?topic=ha-monitoring-restarting-ending-queue-manager-instances
[local-stanza]: https://www.ibm.com/docs/en/ibm-mq/9.4.x?topic=qmini-nativehalocalinstance-stanza-file
[logging]: https://www.ibm.com/docs/en/ibm-mq/9.4.x?topic=lost-types-logging
[nha10]: https://www.ibm.com/docs/en/ibm-mq/10.0.x?topic=recovery-native-ha
[log-performance]: https://www.ibm.com/docs/en/ibm-mq/9.4.x?topic=nh-performance-considerations-when-moving-from-circular-linear-logs
[mqmd]: https://www.ibm.com/docs/en/ibm-mq/9.4.x?topic=descriptor-field-details-mqmd
[reconnect]: https://www.ibm.com/docs/en/ibm-mq/10.0.x?topic=restart-automatic-client-reconnection
[channel-options]: https://www.ibm.com/docs/en/ibm-mq/9.4.x?topic=formats-change-copy-create-channel
[endmqm]: https://www.ibm.com/docs/en/ibm-mq/9.4.x?topic=reference-endmqm-end-queue-manager
[troubleshooting]: https://www.ibm.com/docs/en/ibm-mq/9.4.x?topic=dt-troubleshooting-native-ha-native-ha-crr-configurations-linux
[metrics]: https://www.ibm.com/docs/en/ibm-mq/9.4.x?topic=trace-metrics-published-system-topics
[upgrade]: https://www.ibm.com/docs/en/ibm-mq/9.4.x?topic=ha-upgrading-native-configurations
[ini-management]: https://www.ibm.com/docs/en/ibm-mq/9.4.x?topic=configuring-changing-mq-configuration-information-in-ini-files-multiplatforms
[refresh-security]: https://www.ibm.com/docs/en/ibm-mq/9.4.x?topic=reference-refresh-security-refresh-security-settings
[multiple-tls]: https://www.ibm.com/docs/en/ibm-mq/9.4.x?topic=nhc-example-using-multiple-tls-certificates-native-ha-crr-linux
[crr-lab]: https://www.ibm.com/docs/en/ibm-mq/9.4.x?topic=nhc-example-deploying-simple-native-ha-crr-configuration-linux
[add-recovery]: https://www.ibm.com/docs/en/ibm-mq/9.4.x?topic=nh-example-adding-recovery-group-existing-native-ha-configuration-linux
[dr-comparison]: https://www.ibm.com/docs/en/ibm-mq/10.0.x?topic=chadr-comparison-native-ha-crr-native-ha-irr-solutions
[irr]: https://www.ibm.com/docs/en/ibm-mq/10.0.x?topic=recovery-native-ha-irr
[irr-create]: https://www.ibm.com/docs/en/ibm-mq/10.0.x?topic=irr-creating-native-ha-configuration
[irr-failover]: https://www.ibm.com/docs/en/ibm-mq/10.0.x?topic=irr-complete-unplanned-failover-native-ha-configuration
