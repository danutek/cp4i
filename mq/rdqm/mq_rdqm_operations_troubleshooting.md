# IBM MQ RDQM Operations and Troubleshooting Guide

**ExampleCo**

This practical operations guide is designed for administrators managing IBM MQ RDQM (Replicated Data Queue Managers) on Linux. It provides the core commands and workflows required to check RDQM health, manage queue managers, monitor clusters, handle DRBD replication, and troubleshoot kernel modules in a Secure Boot environment.

## 1. RDQM Architecture Overview

RDQM consists of several layers working together to ensure high availability:

* **MQ Queue Manager:** The core messaging engine.
* **Pacemaker:** The cluster resource manager.
* **Corosync:** Maintains cluster node membership.
* **DRBD:** Handles block-level data replication.
* **Filesystem:** The underlying storage layer.

Three nodes normally participate in an RDQM configuration: Node 1 (Active), Node 2 (Standby), and Node 3 (Tie breaker/standby). At any given moment, only one node owns the queue manager.

---

## 2. Network and Firewall Requirements

RDQM requires reliable node-to-node communication. Ensure your firewalls allow the following traffic:

| Port | Protocol | Purpose |
| --- | --- | --- |
| 5404 | UDP | Corosync |
| 5405 | UDP | Corosync |
| 7789 | TCP | DRBD |
| 1414 | TCP | MQ listener |

**Example firewalld configuration:**

```bash
firewall-cmd --permanent --add-port=5404/udp
firewall-cmd --permanent --add-port=5405/udp
firewall-cmd --permanent --add-port=7789/tcp
firewall-cmd --permanent --add-port=1414/tcp
firewall-cmd --reload

```

---

## 3. Kernel Module Management and Secure Boot

RDQM relies on DRBD kernel modules (`drbd` and `drbd_transport_tcp`). If your system has Secure Boot enabled, unsigned modules will fail to load, often resulting in an `Operation not permitted` error.

**Check Secure Boot State:**

```bash
mokutil --sb-state

```

### Viewing Kernel Modules

To list currently loaded DRBD modules:

```bash
lsmod | grep drbd

```

To view full descriptions of each module (which generates significant output):

```bash
modinfo drbd
modinfo drbd_transport_tcp

```

### Signing Kernel Modules

Load signed kernel modules to enhance system security when UEFI Secure Boot is active. Assuming you have already generated a public/private key pair and enrolled the public key on the target system, follow these steps to sign your existing DRBD module:

1. **Export your public key** to the `sb_cert.cer` file:
```bash
certutil -d /etc/pki/pesign -n 'Custom Secure Boot key' -Lr > sb_cert.cer

```


*(Note: Replace 'Custom Secure Boot key' with the nickname of your actual key if different)*.
2. **Extract the key** from the NSS database as a PKCS #12 file:
```bash
pk12util -o sb_cert.p12 -n 'Custom Secure Boot key' -d /etc/pki/pesign

```


3. When prompted by the previous command, **enter a new password** that encrypts the private key.
4. **Export the unencrypted private key**:
```bash
openssl pkcs12 -in sb_cert.p12 -out sb_cert.priv -nocerts -noenc

```


**Important:** Keep the unencrypted private key secure.
5. **Sign your kernel module**:
```bash
/usr/src/kernels/$(uname -r)/scripts/sign-file sha256 sb_cert.priv sb_cert.cer my_module.ko

```


This command appends the signature directly to the ELF image in your kernel module file.

### Confirming the Module Signature

To display information about the kernel module's signature, run:

```bash
modinfo my_module.ko | grep signer

```

Check that the signature lists your name as entered during generation. Because the appended signature is not contained in an ELF image section and is not a formal part of the ELF image, utilities such as `readelf` cannot display the signature on your kernel module.

---

## 4. Cluster Configuration

The `rdqmadm` command is used to configure and manage RDQM.

* **Configure the Cluster:**
```bash
rdqmadm -c

```


This command initializes the RDQM subsystem and prepares it to participate in a high-availability cluster. It automatically performs the complex setup of DRBD configuration, Pacemaker resources, and the Corosync cluster.
* **Unconfigure the Cluster:**
```bash
rdqmadm -u

```


Removes the RDQM configuration. Use this command carefully.

---

## 5. Managing RDQM Queue Managers

If running these commands as root, always create the secondary instances first, followed by the primary.

* **Create Secondary Instances:**
```bash
crtmqm -sxs QM1

```


The `-sxs` flag denotes a replicated data HA secondary queue manager.
* **Create Primary Instance:**
```bash
crtmqm -sx QM1

```


The `-sx` flag denotes a replicated data HA primary queue manager.
* **Start the Queue Manager:**
```bash
strmqm QM1

```


Pacemaker will automatically determine which node becomes active.
* **Stop the Queue Manager:**
* Graceful stop: `endmqm QM1`
* Immediate stop: `endmqm -i QM1`


* **Delete the Queue Manager:**
```bash
dltmqm QM1

```


This removes the replicated data queue manager configuration.

---

## 6. Cluster Monitoring and Administration

### Checking RDQM Status

To view the overall RDQM state:

```bash
rdqmstatus

```

This output displays the HA status, the queue manager's running status, the active node, and kernel module statuses.

### Pacemaker Diagnostics (`crm_mon` & `crm`)

The `crm_mon` command is the most important diagnostic tool for RDQM clusters, displaying the real-time state of the Pacemaker cluster, node health, quorum status, and resource placement.

* **View live cluster status** (runs continuously):
```bash
crm_mon

```


* **View static cluster status** (outputs once and exits):
```bash
crm_mon -1

```


* **Move a queue manager to another node:**
```bash
crm resource move <resource> <node>

```


*(Example: `crm resource move qm1 srvmq2`)*
* **Clear a manual resource move:**
```bash
crm resource clear <resource>

```



---

## 7. DRBD Replication Checks

RDQM uses DRBD for block replication.

**Check raw DRBD status:**

```bash
cat /proc/drbd

```

Healthy replication will show `cs:Connected` and `ds:UpToDate/UpToDate`.

**Check disk replication role status:**

```bash
drbdadm status

```

---

## 8. Troubleshooting Workflow & Logs

If a queue manager fails to start, follow this structured diagnostic workflow:

1. **Check MQ Status:** `rdqmstatus`
2. **Check Cluster Health:** `crm_mon -1`
3. **Check DRBD Replication:** `cat /proc/drbd`
4. **Check Core Services:** `systemctl status pacemaker` and `systemctl status corosync`
5. **Check Kernel Modules:** `lsmod | grep drbd`
6. **Check Firewall Rules:** `firewall-cmd --list-all`
7. **Check Port Bindings:** `ss -lntp`

### Key Log Locations

* **MQ Logs:** `/var/mqm/errors`
* **System Logs:** `journalctl -xe`
* **Pacemaker Logs:** `journalctl -u pacemaker`
* **Corosync Logs:** `journalctl -u corosync`
