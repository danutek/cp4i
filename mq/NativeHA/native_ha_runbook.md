# IBM MQ Native HA on Linux Virtual Machines — Operational Runbook

This runbook provides step-by-step Day-0, Day-1, and Day-2 commands, verification gates, and recovery playbooks for deploying and operating a three-instance **IBM MQ Native HA** queue manager on Linux virtual machines (IBM MQ **9.4.4+** for Native HA / CRR; **10.0.x** for IRR).

- **Companion architecture & design guide:** [IBM MQ Native HA on Virtual Machines](./ibm_mq_native_ha_on_virtual_machines.md)
- **Alternative HA option (RHEL + DRBD/Pacemaker):** [IBM MQ RDQM Complete Guide](../rdqm/mq_rdqm_complete_guide.md)

> [!IMPORTANT]
> **Documentation basis & validation note:** Commands and stanzas below are checked against IBM MQ 9.4.x and 10.0.x documentation (reviewed 2026-11-25), but have not been executed against a live cluster as part of this authoring pass. Always validate every command, package name, TLS policy, and `mqmonitor.py` stop action in a non-production environment before production rollout.

---

## Table of Contents

1. [Standard Runbook Inventory & Scope](#1-standard-runbook-inventory--scope)
2. [Phase 1 (Day 0): Linux OS Preparation & Pre-Flight Checks](#2-phase-1-day-0-linux-os-preparation--pre-flight-checks)
3. [Phase 2 (Day 0): Install IBM MQ, Accept License, and Set Entitlement](#3-phase-2-day-0-install-ibm-mq-accept-license-and-set-entitlement)
4. [Phase 3 (Day 1): Create Instances & Configure Replication TLS](#4-phase-3-day-1-create-instances--configure-replication-tls)
5. [Phase 4 (Day 1): Enable `systemd` Supervision (`mqmonitor.py`) & Verify Group Health](#5-phase-4-day-1-enable-systemd-supervision-mqmonitorpy--verify-group-health)
6. [Phase 5 (Day 1): Configure Application Channels & Client Reconnection](#6-phase-5-day-1-configure-application-channels--client-reconnection)
7. [Phase 6 (Day 1): Acceptance & Failover Test Playbook](#7-phase-6-day-1-acceptance--failover-test-playbook)
8. [Phase 7 (Day 2): Routine Operations Playbooks](#8-phase-7-day-2-routine-operations-playbooks)
9. [Phase 8 (Day 2): Failure Recovery & Troubleshooting Playbooks](#9-phase-8-day-2-failure-recovery--troubleshooting-playbooks)
10. [Phase 9 (Optional): Adding CRR or IRR Disaster Recovery](#10-phase-9-optional-adding-crr-or-irr-disaster-recovery)
11. [Quick-Reference Command Cheat Sheet](#11-quick-reference-command-cheat-sheet)
12. [Reference Links](#12-reference-links)

---

## 1. Standard Runbook Inventory & Scope

All commands in this runbook use the following reference deployment. Replace hostnames, IPs, ports, and passwords to match your environment.

| Parameter | Example Value | Notes |
| --- | --- | --- |
| Queue manager name | `MYQMGR` | Identical on all 3 hosts |
| Hosts / instance names | `alpha.example.com` (`alpha`), `beta.example.com` (`beta`), `gamma.example.com` (`gamma`) | Unique local instance names; separate hypervisor/power/network failure domains |
| Client listener port | TCP `1414` | Distinct port per queue manager if hosting multiple QMs |
| Intra-group replication port | TCP `9414` | Permitted bidirectionally among `alpha`, `beta`, `gamma` |
| Install / data paths | `/opt/mqm` and `/var/mqm` | Must match on all 3 hosts |
| Replication keystore | `/var/mqm/qmgrs/MYQMGR/ssl/keystore.kdb` | Referenced without `.kdb` in `qm.ini` |
| Replication cert label | `nha-qm-replication` | Must exist in keystore on every host |

### Replicated vs. Host-Local Quick Reference

Before executing Day-1 or Day-2 changes, confirm which layer owns the change:

| Replicated automatically via MQ recovery logs | Host-local (apply on **all 3 hosts** via config management) |
| --- | --- |
| Queues, channels, listeners, topics, subscriptions | `/var/mqm/qmgrs/MYQMGR/qm.ini` and `/var/mqm/mqs.ini` |
| `AUTHREC`, `CHLAUTH`, `CONNAUTH` definitions | Replication & application TLS keystores, `.sth`, and `InitialKeyFile` |
| Committed persistent messages & XA syncpoint state | Channel/API/security exits and external shared libraries |
| Media images & recoverable object state | `systemd` units, `mqmonitor.py`, and OS users/groups/PAM/LDAP bindings |

---

## 2. Phase 1 (Day 0): Linux OS Preparation & Pre-Flight Checks

Run all commands in this phase on **all three hosts** (`alpha`, `beta`, `gamma`) unless noted otherwise.

### 2.1 Verify platform uniformity, storage, and time synchronization

1. Confirm matching OS distribution, architecture, and independent non-shared filesystems:

```bash
uname -m
cat /etc/os-release
df -hT /opt /var/mqm 2>/dev/null || df -hT /opt /var
```

- All three nodes must use the same processor architecture, environment type (do not mix VMs, bare metal, and containers), and equivalent CPU, memory, and independent storage.
- Do **not** mount `/var/mqm` or `/var/mqm/log` on shared NFS/clustered storage shared across instances.

2. Verify NTP synchronization and consistent timezone across all three hosts:

```bash
timedatectl status
chronyc tracking
```

### 2.2 Pre-create consistent `mqm` and application OS identities (recommended)

Keeping identical `mqm` UID/GID and OS application user/group mappings across all three VMs prevents post-failover file-ownership mismatches and `2035 MQRC_NOT_AUTHORIZED` errors when using OS-based authentication/OAM.

```bash
# Example fixed UID/GID (adjust to organization standards; run identically on all 3 hosts)
sudo groupadd -g 1001 mqm 2>/dev/null || true
sudo useradd -u 1001 -g mqm -d /var/mqm -m -s /bin/bash mqm 2>/dev/null || true
id mqm
```

### 2.3 Verify resilient peer name resolution

Ensure `alpha.example.com`, `beta.example.com`, and `gamma.example.com` resolve reliably on all three hosts. Back redundant DNS with local `/etc/hosts` entries if a transient DNS outage could destabilize replication quorum:

```bash
for h in alpha.example.com beta.example.com gamma.example.com; do
  getent hosts "$h"
done
```

### 2.4 Configure firewall ports and verify SELinux mode

Permit client traffic (`1414/tcp`) from authorized application subnets and bidirectional replication traffic (`9414/tcp`) among `alpha`, `beta`, and `gamma`.

**RHEL / Rocky / Alma (`firewalld`):**

```bash
# Replace 10.10.20.0/24 with your peer VM subnet (or add per-host rich rules)
sudo firewall-cmd --permanent --add-port=1414/tcp
sudo firewall-cmd --permanent --add-rich-rule='rule family="ipv4" source address="10.10.20.0/24" port port="9414" protocol="tcp" accept'
sudo firewall-cmd --reload
sudo firewall-cmd --list-all
```

**Ubuntu (`ufw`):**

```bash
sudo ufw allow 1414/tcp
sudo ufw allow from 10.10.20.0/24 to any port 9414 proto tcp
sudo ufw status verbose
```

**SELinux check (RHEL-based hosts):**

```bash
getenforce
```

If SELinux is `Enforcing`, verify that non-default MQ paths or custom `systemd` wrapper scripts have appropriate contexts and audit denials (`ausearch -m avc -ts recent`) during initial startup.

---

## 3. Phase 2 (Day 0): Install IBM MQ, Accept License, and Set Entitlement

Run on **all three hosts** at the **exact same MQ version and maintenance level** (9.4.4+ CD or 10.0.x).

### 3.1 Extract media and accept the license

```bash
cd /tmp/mq-install/MQServer
sudo ./mqlicense.sh -accept
```

### 3.2 Install minimum required server components

**RPM-based Linux (RHEL):**

```bash
sudo dnf install -y \
  ./MQSeriesRuntime-*.rpm \
  ./MQSeriesServer-*.rpm \
  ./MQSeriesGSKit-*.rpm

# Optional: install samples if running amqsput/amqsget tests in Phase 6
sudo dnf install -y ./MQSeriesSamples-*.rpm
```

**Debian-based Linux (Ubuntu):**

```bash
sudo apt-get update
sudo apt-get install -y \
  ./ibmmq-runtime_*.deb \
  ./ibmmq-server_*.deb \
  ./ibmmq-gskit_*.deb

# Optional: install samples for Phase 6 testing
sudo apt-get install -y ./ibmmq-samples_*.deb
```

### 3.3 Set primary installation and entitlement tags

Configure `/opt/mqm` as the primary installation and apply the license entitlement matching your contract (check [IBM MQ license information][licensing] and verify exact flags for your MQ level):

```bash
sudo /opt/mqm/bin/setmqinst -i -p /opt/mqm

# Example: IBM MQ Advanced production entitlement
sudo /opt/mqm/bin/setmqinst -l advanced -e y -p /opt/mqm

# Alternative examples (use ONLY what matches your purchased entitlement):
# sudo /opt/mqm/bin/setmqinst -l nha -e y -p /opt/mqm          # Native HA add-on active/chargeable node
# sudo /opt/mqm/bin/setmqinst -l nhareplica -e y -p /opt/mqm   # Native HA replica entitlement
# sudo /opt/mqm/bin/setmqinst -l nonprod -e y -p /opt/mqm      # Non-production environment
```

### 3.4 Validate kernel parameters and MQ installation

Run as `mqm` on each host:

```bash
sudo su - mqm
. /opt/mqm/bin/setmqenv -s
dspmqver
dspmqinst
/opt/mqm/bin/mqconfig
```

**Gate:** Resolve every `FAIL` reported by `mqconfig` (such as `nofile`, `nproc`, `sem`, `shmmax`, or `tcp_keepalive_time` in `/etc/sysctl.d/` and `/etc/security/limits.d/`) on all three hosts before proceeding.

---

## 4. Phase 3 (Day 1): Create Instances & Configure Replication TLS

### 4.1 Create the queue manager instance on each host

Run as `mqm`. Keep `-lf`, `-lp`, `-ls`, and the queue manager name identical across all three hosts; only `-lr <instance_name>` changes.

> [!NOTE]
> `-lf 8192` allocates 8,192 × 4 KiB pages (**32 MiB per extent**), and `-p 1414` automatically defines a TCP listener on port 1414. Size log extents and filesystem capacity for your measured workload before production (extent size `-lf` is fixed at creation).

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

### 4.2 Provision replication TLS keystores

Choose **Option A** only for labs/sandboxes, or **Option B** for production.

#### Option A: Lab / Sandbox Shortcut (Shared Self-Signed Certificate)

> [!WARNING]
> Do **not** carry a shared self-signed lab keystore into production. Never commit `.kdb`, `.sth`, or plaintext passwords to Git.

On **alpha** (as `mqm`):

```bash
mkdir -p /var/mqm/qmgrs/MYQMGR/ssl
chmod 750 /var/mqm/qmgrs/MYQMGR/ssl

# Create CMS key repository with stash file (replace placeholder password)
runmqakm -keydb -create \
  -db /var/mqm/qmgrs/MYQMGR/ssl/keystore.kdb \
  -pw '<STRONG_LAB_PASSWORD>' \
  -type cms \
  -stash

# Create self-signed certificate matching CertificateLabel in qm.ini
runmqakm -cert -create \
  -db /var/mqm/qmgrs/MYQMGR/ssl/keystore.kdb \
  -stashed \
  -label nha-qm-replication \
  -dn "CN=MYQMGR,O=Example,C=US" \
  -size 2048 \
  -sigalg SHA256WithRSA \
  -expire 365

# Verify certificate exists
runmqakm -cert -list -db /var/mqm/qmgrs/MYQMGR/ssl/keystore.kdb -stashed
```

Copy `keystore.kdb`, `keystore.sth`, `keystore.rdb`, and `keystore.crl` securely (e.g., `scp`/`sftp`) into `/var/mqm/qmgrs/MYQMGR/ssl/` on **beta** and **gamma**, then lock down permissions on **all three hosts**:

```bash
chown mqm:mqm /var/mqm/qmgrs/MYQMGR/ssl/keystore.*
chmod 640 /var/mqm/qmgrs/MYQMGR/ssl/keystore.*
```

#### Option B: Production CA-Signed Per-Host Certificates (+ Optional `runmqicred` Encrypted Password)

Run on **each host** (`alpha`, `beta`, `gamma`) as `mqm`, substituting `<HOST_FQDN>` (`alpha.example.com`, etc.):

```bash
mkdir -p /var/mqm/qmgrs/MYQMGR/ssl
chmod 750 /var/mqm/qmgrs/MYQMGR/ssl

# 1. Create per-host key repository (omit -stash if using runmqicred below)
runmqakm -keydb -create \
  -db /var/mqm/qmgrs/MYQMGR/ssl/keystore.kdb \
  -pw '<HOST_UNIQUE_KDB_PASSWORD>' \
  -type cms \
  -stash

# 2. Import internal CA root and intermediate certificates
runmqakm -cert -add \
  -db /var/mqm/qmgrs/MYQMGR/ssl/keystore.kdb \
  -stashed \
  -label corporate-root-ca \
  -file /tmp/certs/root-ca.pem \
  -format ascii

runmqakm -cert -add \
  -db /var/mqm/qmgrs/MYQMGR/ssl/keystore.kdb \
  -stashed \
  -label corporate-issuing-ca \
  -file /tmp/certs/issuing-ca.pem \
  -format ascii

# 3. Generate per-host CSR with SAN
runmqakm -certreq -create \
  -db /var/mqm/qmgrs/MYQMGR/ssl/keystore.kdb \
  -stashed \
  -label nha-qm-replication \
  -dn "CN=<HOST_FQDN>,OU=MQ-NativeHA,O=Example,C=US" \
  -san_dnsname "<HOST_FQDN>" \
  -size 2048 \
  -sigalg SHA256WithRSA \
  -file /tmp/certs/<HOST_FQDN>.csr

# 4. After your CA signs the CSR, receive the signed personal certificate
runmqakm -cert -receive \
  -db /var/mqm/qmgrs/MYQMGR/ssl/keystore.kdb \
  -stashed \
  -file /tmp/certs/<HOST_FQDN>.pem \
  -format ascii

# 5. Validate certificate chain and private key ownership
runmqakm -cert -validate -db /var/mqm/qmgrs/MYQMGR/ssl/keystore.kdb -stashed -label nha-qm-replication
chmod 640 /var/mqm/qmgrs/MYQMGR/ssl/keystore.*
```

**Optional MQ 9.4+ Encrypted Password Alternative (instead of `.sth` stash files):**

If your security standard forbids `.sth` stash files, generate a unique initial key file and encrypt the keystore password with `runmqicred`:

```bash
# Create an installation-specific random initial key file (protect 600 mqm:mqm)
umask 077
openssl rand -base64 32 > /var/mqm/qmgrs/MYQMGR/ssl/nha.key
chown mqm:mqm /var/mqm/qmgrs/MYQMGR/ssl/nha.key
chmod 600 /var/mqm/qmgrs/MYQMGR/ssl/nha.key

# Encrypt the keystore password interactively (copy the <!...> output string)
runmqicred -sf /var/mqm/qmgrs/MYQMGR/ssl/nha.key
```

Then add `KeyRepositoryPassword=<ENCRYPTED_OUTPUT>` and `InitialKeyFile=/var/mqm/qmgrs/MYQMGR/ssl/nha.key` inside `NativeHALocalInstance` in Section 4.3, and omit `-stash` when creating the `.kdb`.

### 4.3 Update `qm.ini` on each host

1. Back up the generated `qm.ini` on every host before editing:

```bash
cp -p /var/mqm/qmgrs/MYQMGR/qm.ini /var/mqm/qmgrs/MYQMGR/qm.ini.bak.$(date +%Y%m%d%H%M%S)
```

2. Edit `/var/mqm/qmgrs/MYQMGR/qm.ini`. **Update the existing `NativeHALocalInstance` stanza** generated by `crtmqm -lr` rather than adding a duplicate, and append all three `NativeHAInstance` stanzas.

On **alpha**:

```ini
NativeHALocalInstance:
   Name=alpha
   CipherSpec=ANY_TLS12_OR_HIGHER
   CertificateLabel=nha-qm-replication
   KeyRepository=/var/mqm/qmgrs/MYQMGR/ssl/keystore
   # Uncomment both lines below ONLY if using runmqicred instead of a .sth stash file:
   # KeyRepositoryPassword=<ENCRYPTED_OUTPUT_FROM_RUNMQICRED>
   # InitialKeyFile=/var/mqm/qmgrs/MYQMGR/ssl/nha.key

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

- On **beta**, change **only** `NativeHALocalInstance` → `Name=beta`.
- On **gamma**, change **only** `NativeHALocalInstance` → `Name=gamma`.
- Adjust `CipherSpec` to match your organization's TLS policy and MQ release (e.g., `ANY_TLS12`, `ANY_TLS12_OR_HIGHER`, or `ANY_TLS13_OR_HIGHER`).

---

## 5. Phase 4 (Day 1): Enable `systemd` Supervision (`mqmonitor.py`) & Verify Group Health

### 5.1 Inspect IBM's sample monitor script and stop action

Before enabling the service, verify that IBM's sample files exist and inspect how `--stop` shuts down the queue manager:

```bash
ls -l /opt/mqm/samp/mqmonitor.py /opt/mqm/samp/mqmonitor@.service
cat /opt/mqm/samp/mqmonitor@.service
grep -n -C 5 "endmqm" /opt/mqm/samp/mqmonitor.py
```

> [!IMPORTANT]
> IBM's sample `mqmonitor.py --stop` invokes `endmqm -tp 29 -w <qmgr>`, which does **not** pass `-r` (reconnect clients) or `-s` (switchover with quorum check) by default. Review this carefully against your planned-maintenance client reconnection policy in Phase 6 and Phase 7.1.

### 5.2 Enable and start `mqmonitor@MYQMGR` on all three hosts

Run on **alpha**, **beta**, and **gamma** (within a short window so initial election completes cleanly):

```bash
# Confirm no conflicting unit file already exists
ls -l /etc/systemd/system/mqmonitor@.service 2>/dev/null || true

sudo ln -s /opt/mqm/samp/mqmonitor@.service /etc/systemd/system/mqmonitor@.service
sudo systemctl daemon-reload
sudo systemctl enable mqmonitor@MYQMGR
sudo systemctl start mqmonitor@MYQMGR
sudo systemctl status mqmonitor@MYQMGR --no-pager
```

> [!CAUTION]
> **Single lifecycle owner rule:** Once `mqmonitor@MYQMGR` is active, always use `sudo systemctl start|stop|restart|status mqmonitor@MYQMGR`. Do **not** run manual `strmqm` or `endmqm` while `mqmonitor` is running—the monitor polls every ~10 seconds and will restart a manually stopped instance.

### 5.3 Validate group status and healthy output

Run as `mqm` on each host:

```bash
dspmq -m MYQMGR -o nativeha -x
```

**Expected healthy output (on the active host, e.g., `alpha`):**

```text
QMNAME(MYQMGR) ROLE(Active) INSTANCE(alpha) INSYNC(yes) QUORUM(3/3) GRPLSN(<0:0:12:4820>) GRPNAME() GRPROLE(Live)
 INSTANCE(alpha) ROLE(Active) REPLADDR(alpha.example.com(9414)) CONNACTV(yes) INSYNC(yes) BACKLOG(0) CONNINST(yes) ACKLSN(<0:0:12:4820>) HASTATUS(Normal) SYNCTIME(2026-11-25T18:10:02.123456Z) ALTDATE(2026-11-25) ALTTIME(18.10.02)
 INSTANCE(beta) ROLE(Replica) REPLADDR(beta.example.com(9414)) CONNACTV(yes) INSYNC(yes) BACKLOG(0) CONNINST(yes) ACKLSN(<0:0:12:4820>) HASTATUS(Normal) SYNCTIME(2026-11-25T18:10:02.123456Z) ALTDATE(2026-11-25) ALTTIME(18.10.02)
 INSTANCE(gamma) ROLE(Replica) REPLADDR(gamma.example.com(9414)) CONNACTV(yes) INSYNC(yes) BACKLOG(0) CONNINST(yes) ACKLSN(<0:0:12:4820>) HASTATUS(Normal) SYNCTIME(2026-11-25T18:10:02.123456Z) ALTDATE(2026-11-25) ALTTIME(18.10.02)
```

Check service journal and MQ error logs for any TLS or peer warnings:

```bash
sudo journalctl -u mqmonitor@MYQMGR --since '15 minutes ago' --no-pager
tail -n 40 /var/mqm/qmgrs/MYQMGR/errors/AMQERR01.LOG
```

**Gate:** Exactly one `ROLE(Active)`, two `ROLE(Replica)`, `QUORUM(3/3)`, all three showing `CONNACTV(yes)`, `INSYNC(yes)`, `BACKLOG(0)`, and `HASTATUS(Normal)`.

---

## 6. Phase 5 (Day 1): Configure Application Channels & Client Reconnection

Run MQSC definitions on the **current Active instance only**—objects, `CHLAUTH`, and `AUTHREC` replicate automatically to both replicas via the recovery logs.

### 6.1 Verify listener and define server-connection channel

```bash
runmqsc MYQMGR <<'EOF'
DISPLAY LSSTATUS(*)
DEFINE CHANNEL(APP.SVRCONN) CHLTYPE(SVRCONN) TRPTYPE(TCP) +
  SHARECNV(10) HBINT(30) DESCR('Application client channel') REPLACE
EOF
```

- Configure **application-channel TLS** (`SSLCIPH`, `SSLCAUTH`, queue-manager `SSLKEYR`), **`CHLAUTH`**, **`CONNAUTH`**, and least-privilege **`setmqaut`** grants according to your security policy.
- Remember: **application TLS keystores and OS users/groups are host-local**—deploy identical application keystores and OS identities to `alpha`, `beta`, and `gamma` so failovers do not break client connections.

### 6.2 Configure client connectivity (JSON CCDT or Binary CCDT)

#### Option 1: JSON CCDT (Recommended for modern MQ 9.4+ clients)

Save as `ccdt.json` and distribute to client hosts (point clients via `MQCCDTURL=file:///path/to/ccdt.json`):

```json
{
  "channel": [
    {
      "name": "APP.SVRCONN",
      "clientConnection": {
        "connection": [
          { "host": "alpha.example.com", "port": 1414 },
          { "host": "beta.example.com", "port": 1414 },
          { "host": "gamma.example.com", "port": 1414 }
        ],
        "queueManager": "MYQMGR"
      },
      "connectionManagement": {
        "clientWeight": 1,
        "affinity": "none",
        "sharingConversations": 10
      },
      "general": {
        "description": "Native HA multi-host client channel"
      },
      "type": "clientConnection"
    }
  ]
}
```

Enable same-queue-manager reconnection in the client application or `mqclient.ini` (for applicable MQI clients, e.g., `DefRecon=QMGR` or `MQCNO_RECONNECT_Q_MGR`; for JMS/Java, verify the exact API's reconnection properties).

#### Option 2: Binary CCDT (via `runmqsc -n`)

```bash
runmqsc -n <<'EOF'
DEFINE CHANNEL(APP.SVRCONN) CHLTYPE(CLNTCONN) TRPTYPE(TCP) +
  CONNAME('alpha.example.com(1414),beta.example.com(1414),gamma.example.com(1414)') +
  QMNAME(MYQMGR) DEFRECON(QMGR) REPLACE
EOF
```

#### Option 3: External TCP Load Balancer

If fronting the group with an L4 load balancer instead of a multi-host CCDT:
- Health checks **must** identify the **active** instance (not just an open VM IP or port `9414`). A TCP listener on port `1414` only accepts connections on the active instance; validate probe interval, failover drain time, and TLS passthrough behavior under failover tests.

---

## 7. Phase 6 (Day 1): Acceptance & Failover Test Playbook

Execute all tests in a non-production environment and record timestamps, roles, message IDs, and measured application RTO.

### 7.1 Local persistent-message survival test

1. On the **active** host (e.g., `alpha`), create a dedicated test queue and put uniquely identifiable persistent messages:

```bash
runmqsc MYQMGR <<'EOF'
DEFINE QLOCAL(NHA.TEST) DEFPSIST(YES) REPLACE
EOF

printf "nha-test-msg-001\nnha-test-msg-002\n\n" | /opt/mqm/samp/bin/amqsput NHA.TEST MYQMGR
```

2. Trigger an active failover (e.g., `sudo systemctl stop mqmonitor@MYQMGR` on `alpha`, or abruptly power off the `alpha` VM for an unplanned-failure test).
3. On `beta` or `gamma`, identify the newly elected active instance:

```bash
dspmq -m MYQMGR -o nativeha -x
```

4. On the **new active** host, verify all committed persistent messages are intact:

```bash
/opt/mqm/samp/bin/amqsget NHA.TEST MYQMGR
```

5. Restore `alpha` (`sudo systemctl start mqmonitor@MYQMGR` or power VM back on) and confirm `QUORUM(3/3)`, `INSYNC(yes)`, and `BACKLOG(0)`.

### 7.2 Full acceptance matrix

| # | Scenario | Action | Pass Criteria |
| --- | --- | --- | --- |
| 1 | Replica stop & catch-up | `sudo systemctl stop mqmonitor@MYQMGR` on one replica; put messages on active; restart replica | Active keeps serving (`QUORUM(2/3)`); restarted replica catches up to `QUORUM(3/3)`, `BACKLOG(0)` |
| 2 | Planned active shutdown | `sudo systemctl stop mqmonitor@MYQMGR` on active | Replica promotes; record client reconnection behavior separately from abrupt failure |
| 3 | Abrupt active VM failure | Hard power-off / reset active VM during active client traffic | Replica promotes; zero loss of committed persistent messages; clients reconnect and reconcile uncertain commits |
| 4 | Active network isolation | Block TCP `9414` on active host from both peers | Isolated active abdicates quorum-dependent writes; connected 2-node majority elects new active |
| 5 | Loss of two instances | Stop two instances concurrently | Remaining instance does **not** serve quorum-dependent writes; service resumes once a second instance returns |
| 6 | Non-persistent message check | Put non-persistent messages, force failover | Confirm application owners expect non-persistent messages to be discarded on leadership change |
| 7 | Reboot persistence | Reboot each VM one at a time | `mqmonitor@MYQMGR` auto-starts on boot and rejoins cleanly to `QUORUM(3/3)` |

---

## 8. Phase 7 (Day 2): Routine Operations Playbooks

### 8.1 Controlled / Planned Switchover (Moving the Active Role)

1. **Pre-check:** Confirm all three instances are healthy (`QUORUM(3/3)`, both replicas `INSYNC(yes)` and `BACKLOG(0)`):

```bash
dspmq -m MYQMGR -o nativeha -x
```

2. **Verify client reconnection policy:** Because IBM's default `mqmonitor.py --stop` runs `endmqm -tp 29 -w` (without `-r` or `-s`), confirm whether your operations team uses a customized stop action or coordinates application drain before stopping the active service.
3. **Stop the current active instance** through `systemd`:

```bash
sudo systemctl stop mqmonitor@MYQMGR
```

4. **Confirm new active election** on a surviving host:

```bash
dspmq -m MYQMGR -o nativeha -x
```

5. **Restart the original host's monitor** once maintenance completes and confirm it rejoins as a synchronized replica (`QUORUM(3/3)`):

```bash
sudo systemctl start mqmonitor@MYQMGR
dspmq -m MYQMGR -o nativeha -x
```

### 8.2 Rolling Replication TLS Certificate Rotation (Zero Quorum Loss)

> [!CAUTION]
> **`REFRESH SECURITY TYPE(SSL)` does not reload Native HA's replication key repository.** Changes take effect only when each instance restarts.

1. **Pre-check:** Verify `QUORUM(3/3)`, `INSYNC(yes)`, `HASTATUS(Normal)`, and `BACKLOG(0)`.
2. **Stage new CA trust first (if changing issuing CAs):** Add the new CA root/intermediate certificates to the keystore on all three hosts **before** activating any new leaf certificate, and restart replicas one at a time (followed by the active host) so every peer trusts both old and new CAs.
3. **Rotate leaf certificates one instance at a time (replicas first, active last):**
   - Back up `/var/mqm/qmgrs/MYQMGR/ssl/keystore.*` on the target replica.
   - Install the renewed certificate (same `CertificateLabel` or updated label in `qm.ini`) and verify `runmqakm -cert -validate`.
   - Restart the replica via `systemd`:
     ```bash
     sudo systemctl restart mqmonitor@MYQMGR
     ```
   - Wait until `dspmq -m MYQMGR -o nativeha -x` returns `QUORUM(3/3)`, `INSYNC(yes)`, `HASTATUS(Normal)`, and `BACKLOG(0)` before proceeding to the second replica, and finally the active instance.
4. **Clean up:** After all three hosts use the new chain and are healthy, remove retired CA certificates if required.

### 8.3 Rolling Maintenance & MQ Upgrades

- **Fix packs (`F` level):** Mixed fix-pack levels are permitted briefly during rolling updates.
- **`V.R.M` upgrades:** A higher `V.R.M` instance cannot write log data to a lower `V.R.M` replica—consult the exact IBM [Native HA upgrade guide][upgrade] for your source/target path and keep all three hosts close together (do not leave one upgraded node soaking for days).
- **Native HA CRR rule:** Always upgrade the **Recovery** group first so Recovery stays at an equal or higher MQ version than Live.

Rolling sequence (where supported by IBM's migration rules for your exact source/target levels):

1. Back up definitions and host config (Section 8.4) and verify `QUORUM(3/3)`.
2. On **Replica 1**:
   ```bash
   sudo systemctl stop mqmonitor@MYQMGR
   # Apply OS patches or IBM MQ maintenance packages per IBM instructions
   sudo systemctl start mqmonitor@MYQMGR
   ```
   Verify `dspmqver` and confirm `dspmq -m MYQMGR -o nativeha -x` reaches the expected synchronized state.
3. Repeat Step 2 on **Replica 2**.
4. Confirm the two updated replicas can maintain quorum and assume leadership, then stop, update, and restart the **Active** host via `systemd`.
5. Confirm target `dspmqver` on all three hosts, `QUORUM(3/3)`, `HASTATUS(Normal)`, `BACKLOG(0)`, and healthy application connectivity.

### 8.4 Backup & Configuration Export Procedure

Run periodically and before any major maintenance:

```bash
# On the Active host (as mqm): export all MQ objects and authorities
BACKUP_DIR="/var/backups/mq/MYQMGR/$(date +%Y%m%d)"
mkdir -p "$BACKUP_DIR"
dmpmqcfg -m MYQMGR -a -o 1line > "$BACKUP_DIR/MYQMGR_objects.mqsc"
dmpmqcfg -m MYQMGR -t authrec -o setmqaut > "$BACKUP_DIR/MYQMGR_authrec.sh"

# On EACH host (alpha, beta, gamma): archive host-local assets
cp -p /var/mqm/qmgrs/MYQMGR/qm.ini "$BACKUP_DIR/$(hostname -s)_qm.ini"
cp -p /var/mqm/mqs.ini "$BACKUP_DIR/$(hostname -s)_mqs.ini"
cp -p /etc/systemd/system/mqmonitor@.service "$BACKUP_DIR/mqmonitor@.service"
```

Store TLS keystores, `InitialKeyFile`s, and password secrets separately in an encrypted secrets vault—never in plaintext backup directories. Remember that `dmpmqcfg` exports definitions and authorities only, not queued messages or recovery logs.

---

## 9. Phase 8 (Day 2): Failure Recovery & Troubleshooting Playbooks

### 9.1 Replacing a Permanently Lost or Corrupted Replica VM (Quorum Intact at `2/3`)

Use this playbook when one VM (e.g., `gamma`) suffers unrecoverable disk/OS loss or local queue-manager corruption while the other two hosts maintain quorum.

1. **Verify surviving quorum** on `alpha` and `beta`:
   ```bash
   dspmq -m MYQMGR -o nativeha -x
   ```
   Confirm `QUORUM(2/3)` with one `Active` and one `INSYNC(yes)` replica.
2. **Clean up local corruption (if reusing the same VM) OR provision a replacement VM:**
   - If reusing `gamma` after local corruption:
     ```bash
     sudo systemctl stop mqmonitor@MYQMGR
     sudo su - mqm -c ". /opt/mqm/bin/setmqenv -s && dltmqm MYQMGR"
     ```
   - If building a fresh replacement VM: complete Phase 1 and Phase 2 with the **exact same OS/architecture, MQ version/maintenance level, paths, `mqm` UID/GID, OS identities, and firewall rules**.
3. **Recreate the blank instance** with the **same instance name (`gamma`)** and **same log extent size (`-lf`)** as the surviving peers:
   ```bash
   sudo su - mqm
   . /opt/mqm/bin/setmqenv -s
   crtmqm -lr gamma -lf 8192 -lp 10 -ls 10 -p 1414 MYQMGR
   ```
4. **Restore host-local assets** onto `gamma`:
   - Restore `/var/mqm/qmgrs/MYQMGR/qm.ini` (confirm `NativeHALocalInstance` has `Name=gamma` and `NativeHAInstance` lists all three peers).
   - Restore/provision replication TLS keystore, application TLS keystore, any `InitialKeyFile`, and any channel/API exits with proper `mqm:mqm` ownership and `640`/`600` permissions.
   - Re-link and enable `mqmonitor@.service` if fresh VM.
5. **Start supervision and monitor catch-up:**
   ```bash
   sudo systemctl enable --now mqmonitor@MYQMGR
   watch -n 5 'sudo su - mqm -c ". /opt/mqm/bin/setmqenv -s && dspmq -m MYQMGR -o nativeha -x"'
   ```
   Expect `gamma` to move through `Checking` → `Synchronizing` / `Rebasing` → `HASTATUS(Normal)`, `INSYNC(yes)`, `BACKLOG(0)`, and group `QUORUM(3/3)`.

### 9.2 Handling Catastrophic Quorum Loss (2 of 3 Instances Permanently Lost)

- If two instances are temporarily down (e.g., power event), **restore at least one failed host cleanly** so quorum (`2/3`) reforms automatically.
- If two instances are **permanently destroyed** (data/logs unrecoverable), the sole surviving instance cannot safely form quorum or guarantee complete committed state. **Do not attempt to hack or force-promote it independently.**
- Recover via your tested DR/rebuild path:
  - **With Native HA CRR:** Promote the Recovery group using IBM's unplanned failover procedure, assess the recovery point (`RCOVLSN`/`RCOVTIME`), route clients to the new Live group, and later rebuild/rebase the original site as Recovery.
  - **Without CRR:** Rebuild a fresh 3-instance Native HA group (Phases 1–5) and restore definitions (`dmpmqcfg` exports), host-local configs, and message state per your approved backup/restore procedure.

### 9.3 `HASTATUS` State & Incident Troubleshooting Playbook

Start every incident by gathering status, logs, and connectivity evidence on all three hosts:

```bash
# 1. Native HA status
dspmq -m MYQMGR -o nativeha -x

# 2. Recent queue manager errors and FDCs
tail -n 60 /var/mqm/qmgrs/MYQMGR/errors/AMQERR01.LOG
ls -lt /var/mqm/errors/*.FDC 2>/dev/null | head -n 10

# 3. Monitor service journal
sudo journalctl -u mqmonitor@MYQMGR --since '30 minutes ago' --no-pager

# 4. Filesystem space and listening sockets
df -h /var/mqm /var/mqm/log 2>/dev/null || df -h /var/mqm
ss -tulpn | grep -E '1414|9414'
```

| Symptom / `HASTATUS` | Likely Causes | Targeted Diagnostic & Remediation |
| --- | --- | --- |
| `HASTATUS(Disconnected)` or `CONNINST(no)` | Service down, firewall blocking TCP `9414`, DNS failure, or TLS handshake/label mismatch | Test TCP reachability (`nc -zv beta.example.com 9414`), verify `getent hosts`, inspect `AMQERR01.LOG` for TLS `AMQ96xx` errors, verify `CertificateLabel` & CA trust via `runmqakm -cert -validate`. |
| `HASTATUS(Checking)` stuck | Log consistency check stalled or peer unreachable | Check `AMQERR01.LOG` and FDCs on both active and affected replica; confirm no disk I/O errors (`dmesg -T`). |
| `HASTATUS(Synchronizing)` with flat/growing `BACKLOG` | Network bandwidth saturation, high RTT, or slow disk I/O on replica | Measure RTT (`ping`), disk latency (`iostat -xz 1 5`), and log write rate; compare against active write throughput. |
| `HASTATUS(Rebasing)` | Replica log diverged or too far behind, fresh rebuild, or CRR rebase | Confirm ample free disk space on the rebasing host; **never** manually delete temporary `*-backup` log directories (MQ cleans them up after rebase). |
| `HASTATUS(Disk full)` | Log or QM filesystem reached 100% | Expand filesystem or clear unrelated non-MQ files; **never** manually delete active recovery log files—follow IBM MQ log recovery procedures. |
| `HASTATUS(Unknown)` | `mqmonitor` stopped, crashed, or QM failed to initialize | Check `systemctl status mqmonitor@MYQMGR`, `journalctl`, `qm.ini` syntax errors, and `keystore.*` permissions (`640 mqm:mqm`). |
| `2035 MQRC_NOT_AUTHORIZED` only **after** failover | Missing OS user/group, mismatched UID/GID, or missing application TLS keystore on the new active VM | Compare `id <appuser>`, `/etc/group`, PAM/SSSD status, and application TLS keystores across all 3 hosts. |
| `systemctl stop` killed instance, or manual `endmqm` auto-restarted | Conflicting lifecycle management | Always stop/start through `sudo systemctl stop|start mqmonitor@MYQMGR`; never mix manual `endmqm` with active `mqmonitor`. |

---

## 10. Phase 9 (Optional): Adding CRR or IRR Disaster Recovery

- **Native HA CRR (6 instances: Live 3-node group + Recovery 3-node group, asynchronous inter-group replication):**
  - Validate both local 3-node groups independently first (`dspmq -m MYQMGR -o nativeha -x`).
  - Configure group identities, inter-group replication addresses, and inter-group TLS per IBM's [Linux CRR example][crr-lab] or [add a recovery group][add-recovery].
  - Monitor group-level replication and recovery point:
    ```bash
    dspmq -m MYQMGR -o nativeha -g
    ```
  - Always check `RCOVLSN`, `RCOVTIME`, synchronization state, and backlog before planned switchover or unplanned promotion. Ensure the previous Live site cannot serve independently before promoting Recovery.

- **Native HA IRR (2 instances: Live 1-node + Recovery 1-node, synchronous inter-group replication, MQ 10.0.x, ≤ ~100 mi / 160 km and ≤ 5 ms RTT):**
  - Remember: **IRR has no automatic HA failover**—DR transitions are manual.
  - Within a complete `NativeHARecoveryGroup` stanza (including mandatory inter-group TLS), set:
    ```ini
    SyncReplication=Yes
    SyncConsistency=Strict   # Or Eventual if availability outweighs strict RPO 0 during link loss
    ```
  - For unplanned failover, inspect `RCOVLSN` and `RCOVTIME` and follow IBM's [unplanned IRR failover][irr-failover] procedure. Never promote both groups independently.

---

## 11. Quick-Reference Command Cheat Sheet

```bash
# Load MQ environment (as mqm)
. /opt/mqm/bin/setmqenv -s

# Check Native HA instance health, quorum, sync, and backlog
dspmq -m MYQMGR -o nativeha -x

# Check Native HA CRR/IRR group-level status
dspmq -m MYQMGR -o nativeha -g

# Lifecycle operations (ALWAYS via systemd once mqmonitor is enabled)
sudo systemctl status mqmonitor@MYQMGR
sudo systemctl stop mqmonitor@MYQMGR
sudo systemctl start mqmonitor@MYQMGR
sudo systemctl restart mqmonitor@MYQMGR

# Inspect monitor logs & MQ error logs
sudo journalctl -u mqmonitor@MYQMGR -n 100 --no-pager
tail -f /var/mqm/qmgrs/MYQMGR/errors/AMQERR01.LOG

# Inspect keystore certificates & expiration dates
runmqakm -cert -list -db /var/mqm/qmgrs/MYQMGR/ssl/keystore.kdb -stashed
runmqakm -cert -details -db /var/mqm/qmgrs/MYQMGR/ssl/keystore.kdb -stashed -label nha-qm-replication

# Export object and authority definitions (on Active host)
dmpmqcfg -m MYQMGR -a -o 1line > MYQMGR_objects.mqsc
dmpmqcfg -m MYQMGR -t authrec -o setmqaut > MYQMGR_authrec.sh
```

---

## 12. Reference Links

- [Companion Architecture & Planning Guide](./ibm_mq_native_ha_on_virtual_machines.md)
- [Native HA on Linux: architecture and prerequisites][nha]
- [IBM MQ licensing and Linux Native HA entitlement][licensing]
- [Example: simple Native HA configuration on Linux][linux-lab]
- [Monitoring, restarting, and ending queue-manager instances][monitor]
- [NativeHALocalInstance stanza reference][local-stanza]
- [Troubleshooting Native HA/CRR on Linux][troubleshooting]
- [Upgrading Native HA configurations][upgrade]
- [Using multiple TLS certificates with Native HA CRR on Linux][multiple-tls]
- [Linux CRR deployment example][crr-lab]
- [Adding a Recovery group to an existing Linux group][add-recovery]
- [Unplanned IRR failover][irr-failover]

[nha]: https://www.ibm.com/docs/en/ibm-mq/9.4.x?topic=configurations-native-ha
[licensing]: https://www.ibm.com/docs/en/ibm-mq/9.4.x?topic=mq-license-information
[linux-lab]: https://www.ibm.com/docs/en/ibm-mq/9.4.x?topic=ha-example-deploying-simple-native-configuration-linux
[monitor]: https://www.ibm.com/docs/en/ibm-mq/9.4.x?topic=ha-monitoring-restarting-ending-queue-manager-instances
[local-stanza]: https://www.ibm.com/docs/en/ibm-mq/9.4.x?topic=qmini-nativehalocalinstance-stanza-file
[troubleshooting]: https://www.ibm.com/docs/en/ibm-mq/9.4.x?topic=dt-troubleshooting-native-ha-native-ha-crr-configurations-linux
[upgrade]: https://www.ibm.com/docs/en/ibm-mq/9.4.x?topic=ha-upgrading-native-configurations
[multiple-tls]: https://www.ibm.com/docs/en/ibm-mq/9.4.x?topic=nhc-example-using-multiple-tls-certificates-native-ha-crr-linux
[crr-lab]: https://www.ibm.com/docs/en/ibm-mq/9.4.x?topic=nhc-example-deploying-simple-native-ha-crr-configuration-linux
[add-recovery]: https://www.ibm.com/docs/en/ibm-mq/9.4.x?topic=nh-example-adding-recovery-group-existing-native-ha-configuration-linux
[irr-failover]: https://www.ibm.com/docs/en/ibm-mq/10.0.x?topic=irr-complete-unplanned-failover-native-ha-configuration
