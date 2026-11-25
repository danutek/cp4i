Below is a **practical operations guide** for administering **IBM MQ RDQM (Replicated Data Queue Managers)** on Linux. It focuses on the commands you’ll actually use when running clusters like the ones we built: `rdqmadm`, `rdqmstatus`, `crm_mon`, DRBD diagnostics, and a few system-level checks that solve many real-world RDQM issues.

---

# IBM MQ RDQM Operations Guide

**Administration and Troubleshooting**

This guide covers:

* Checking RDQM health
* Managing queue managers
* Cluster monitoring
* DRBD replication checks
* Pacemaker cluster commands
* Library and kernel module diagnostics
* Common troubleshooting workflows

---

# 1. RDQM Architecture (Quick Overview)

RDQM consists of several layers working together:

```
MQ Queue Manager
      │
Pacemaker (resource manager)
      │
Corosync (cluster membership)
      │
DRBD (block replication)
      │
Filesystem
```

Three nodes normally participate:

```
Node1 (Active)
Node2 (Standby)
Node3 (Tie breaker / standby)
```

At any moment **one node owns the queue manager**.

---

# 2. Core RDQM Commands

## rdqmstatus

Displays the overall RDQM state.

```
rdqmstatus
```

Example output:

On the primary node:
```
rdqmstatus
Node:                                   srvmq1
OS kernel version:                      5.14.0-611.36.1
DRBD OS kernel version:                 5.14.0-611.5.1
DRBD version:                           9.2.16
DRBD kernel module status:              Loaded

Queue manager name:                     QM1
Queue manager status:                   Running
HA status:                              Normal
HA current location:                    This node
HA preferred location:                  This node
HA blocked location:                    None
```

On the secondary node:

```
rdqmstatus
Node:                                   srvmq2
OS kernel version:                      5.14.0-611.35.1
DRBD OS kernel version:                 5.14.0-611.5.1
DRBD version:                           9.2.16
DRBD kernel module status:              Loaded

Queue manager name:                     QM1
Queue manager status:                   Running elsewhere
HA status:                              Normal
HA current location:                    srvmq1
HA preferred location:                  srvmq1
HA blocked location:                    None
Command '/opt/mqm/bin/rdqmstatus' run with sudo.
```


Important fields:

| Field  | Meaning             |
| ------ | ------------------- |
| Status | Running / Stopped   |
| Role   | Primary / Secondary |
| Node   | Active node         |

---

## crm status

The **`crm` command** is a command-line management tool for **Pacemaker**, the cluster resource manager used by RDQM to control high-availability services. Pacemaker works together with **Corosync** to monitor cluster nodes and start, stop, or move resources such as DRBD volumes, filesystems, floating IPs, and MQ queue managers. The `crm` utility allows administrators to view cluster status, inspect configuration, manage resources, and influence where services run within the cluster. In RDQM environments it is commonly used for tasks such as checking cluster health (`crm status` or `crm_mon`), moving resources between nodes, clearing resource failures, and examining the cluster configuration that Pacemaker uses to orchestrate failover.

```
crm status
Cluster Summary:
  * Stack: corosync
  * Current DC: kc1 (version 2.1.2.linbit-4.el9-ada5c3b36e2) - partition with quorum
  * Last updated: Fri Mar  6 16:35:55 2026
  * Last change:  Fri Mar  6 16:32:47 2026 by root via crm_attribute on kc1
  * 3 nodes configured
  * 6 resource instances configured

Node List:
  * Online: [ srvmq1 srvmq2 srvmq3 ]

Full List of Resources:
  * p_fs_qm1	(ocf:heartbeat:Filesystem):	 Started srvmq2
  * p_rdqmx_qm1	(ocf:ibm:rdqmx):	 Started srvmq2
  * qm1	(ocf:ibm:rdqm):	 Started srvmq2
  * Clone Set: ms_drbd_qm1 [p_drbd_qm1] (promotable):
    * Promoted: [ srvmq2 ]
    * Unpromoted: [ srvmq1 srvmq3 ]
```
## crm_mon
The crm_mon command is the most important diagnostic tool for RDQM clusters. It displays the real-time state of the Pacemaker cluster, including node health, quorum status, and the placement of cluster resources.

When run with out any commands it will not exit and will provide real time view of the cluster status. This often useful during controlled failovers so the failover can be monitored. 

To display the output once and then exit use the -1 switch:
```
crm_mon -1
Cluster Summary:
  * Stack: corosync
  * Current DC: kc1 (version 2.1.2.linbit-4.el9-ada5c3b36e2) - partition with quorum
  * Last updated: Fri Mar  6 16:49:24 2026
  * Last change:  Fri Mar  6 16:32:47 2026 by root via crm_attribute on kc1
  * 3 nodes configured
  * 6 resource instances configured

Node List:
  * Online: [ kc1 tejas1 tejas2 ]

Active Resources:
  * p_fs_qm1	(ocf:heartbeat:Filesystem):	 Started tejas2
  * p_rdqmx_qm1	(ocf:ibm:rdqmx):	 Started tejas2
  * qm1	(ocf:ibm:rdqm):	 Started tejas2
  * Clone Set: ms_drbd_qm1 [p_drbd_qm1] (promotable):
    * Promoted: [ tejas2 ]
    * Unpromoted: [ kc1 tejas1 ]
```
crm_mon has a number of options and provides a good deal of flexibility. Those options can be found by the command:
```
crm_mon --help-all
```
For example, to keep a web page updated with the current status of the cluster, 

```
crm_mon --daemonize --output-as html --output-to /path/to/docroot/filename.html
```

That command makes crm_mon run in the background and update an html with the current status. 



## rdqmadm

Used to configure and manage RDQM.



### Configure RDQM cluster

The rdqmadm -c command initializes the Replicated Data Queue Manager (RDQM) subsystem on a server and prepares it to participate in an RDQM high-availability cluster. Internally, RDQM uses DRBD for block replication and Pacemaker/Corosync for cluster orchestration, but rdqmadm -c automates the complex setup of these components so administrators do not need to configure the cluster manually.

In a traditional Linux HA environment, and older versions of MQ RDQM, building a Pacemaker cluster requires several manual steps such as installing cluster software, configuring Corosync membership, defining DRBD resources, and creating Pacemaker resource groups and ordering constraints. RDQM simplifies this process by providing rdqmadm -c, which performs all these steps automatically using IBM-provided configuration templates tailored specifically for MQ queue managers.

```
rdqmadm -c
```

Creates:

* DRBD configuration
* Pacemaker resources
* Corosync cluster

---

### Unconfigure RDQM

```
rdqmadm -u
```

Removes RDQM configuration.

Use carefully.

---

# 3. Managing RDQM Queue Managers

## Create RDQM Queue Manager

If running the commands as root, you will create both secondary instances and then create the primary. 

Create secondary instances:
```
crtmqm -sxs QM1
```

Meaning of flags:

| Option | Meaning                                     |
| ------ | ------------------------------------------- |
| -sxs   | Replicated data HA secondary queue manager. |

---

Create secondary instances:
```
crtmqm -sx QM1
```

Meaning of flags:

| Option | Meaning                                  |
| ------ | ---------------------------------------- |
| -sx   | Replicated data HA primary queue manager. |

---


## Start Queue Manager

```
strmqm QM1
```

Pacemaker will determine the node that becomes active.

---

## Stop Queue Manager

```
endmqm QM1
```

Graceful stop.

Immediate stop:

```
endmqm -i QM1
```

---

## Delete Queue Manager

```
dltmqm MQ1
Removing replicated data queue manager configuration.
IBM MQ queue manager 'MQ1' deleted.
Command '/opt/mqm/bin/dltmqm' run with sudo.
```

---

# 4. Monitoring the Cluster

## crm_mon (recommended)

Shows cluster status.

```
crm_mon -1
```

Example:

```
Cluster Summary:
 Stack: corosync
 Current DC: srvmq1
 3 nodes configured

Online: [ srvmq1 srvmq2 srvmq3 ]

Resources:
 p_fs_qm1
 p_drbd_qm1
 p_ip_qm1
```

---

## Continuous monitoring

```
crm_mon
```

Live cluster view.

---

# 5. Pacemaker Commands

Pacemaker manages MQ resources.

## Show cluster status

```
crm status
```


---

## Check cluster configuration

```
crm configure show
```

---

## Move queue manager to another node

```
crm resource move <resource> <node>
```

Example:

```
crm resource move p_ip_qm1 srvmq2
```

---

## Clear manual resource move

```
crm resource clear <resource>
```

---

# 6. DRBD Diagnostics

RDQM uses **DRBD** for block replication.

## Check DRBD status

```
cat /proc/drbd
```

Example:

```
0: cs:Connected ro:Primary/Secondary ds:UpToDate/UpToDate
```

Key fields:

| Field | Meaning          |
| ----- | ---------------- |
| cs    | connection state |
| ro    | role             |
| ds    | disk state       |

---

Healthy replication:

```
cs:Connected
ds:UpToDate/UpToDate
```

---

## DRBD resource status

### drbdadm status command
Use the **drbdadm status** command to get the current status of disk replication
```
drbdadm status
qm1 role:Primary
  disk:UpToDate open:yes
  kc1 role:Secondary
    peer-disk:UpToDate
  tejas1 role:Secondary
    peer-disk:UpToDate
```

# 7. Corosync Cluster Checks

Corosync maintains node membership.

## Check corosync service

```
systemctl status corosync
```

---

## Check pacemaker

```
systemctl status pacemaker
```

---

## Corosync configuration

```
/etc/corosync/corosync.conf
```

---

# 8. Network and Firewall Checks

RDQM requires node-to-node communication.

Required ports:

| Port | Protocol | Purpose     |
| ---- | -------- | ----------- |
| 5404 | UDP      | Corosync    |
| 5405 | UDP      | Corosync    |
| 7789 | TCP      | DRBD        |
| 1414 | TCP      | MQ listener |

Example firewall configuration:

```
firewall-cmd --permanent --add-port=5404/udp
firewall-cmd --permanent --add-port=5405/udp
firewall-cmd --permanent --add-port=7789/tcp
firewall-cmd --permanent --add-port=1414/tcp
firewall-cmd --reload
```

---

# 9. Kernel Module Checks

RDQM requires **DRBD kernel modules**.

## List loaded modules

```
lsmod | grep drbd
drbd_transport_tcp     40960  2
drbd                 1019904  3 drbd_transport_tcp
libcrc32c              12288  2 xfs,drbd
```

The important output is the list of the two key modules:

```
drbd
drbd_transport_tcp
```

---

## Load modules
We can manually force the loading of a module. This can be helpful during troubleshooting. 
```
modprobe drbd
modprobe drbd_transport_tcp
```

---

## Show module details
A full description of each module, including signatures, can be acquired through the use of the modinfo command. A lot of output is generated. 
```
modinfo drbd
modinfo drbd_transport_tcp
```

---

# 10. Secure Boot / Module Signing

If Secure Boot is enabled, unsigned modules fail to load.

Typical error:

```
Operation not permitted
```

Check Secure Boot:

```
mokutil --sb-state
SecureBoot enabled
```

If Secure Boot is off:
```
mokutil --sb-state
This system doesn't support Secure Boot
```

If enabled, modules must be signed for them to load.

---

# 11. Library Dependency Checks

When binaries fail to run, check libraries.

## Show shared libraries

```
ldd /opt/mqm/bin/rdqmadm
```

Example:

```
libc.so.6
libpthread.so.0
```

---

## Check missing libraries

```
ldd /opt/mqm/bin/crtmqm | grep "not found"
```

---

# 12. Useful Log Locations

MQ logs:

```
/var/mqm/errors
```

System logs:

```
journalctl -xe
```

Pacemaker logs:

```
journalctl -u pacemaker
```

Corosync logs:

```
journalctl -u corosync
```

---

# 13. RDQM Troubleshooting Workflow

When a queue manager fails to start:

### Step 1 — Check MQ

```
rdqmstatus
```

---

### Step 2 — Check cluster

```
crm_mon -1
```

---

### Step 3 — Check DRBD

```
cat /proc/drbd
```

---

### Step 4 — Check services

```
systemctl status pacemaker
systemctl status corosync
```

---

### Step 5 — Check kernel modules

```
lsmod | grep drbd
```

---

### Step 6 — Check firewall

```
firewall-cmd --list-all
```

---

# 14. Useful Diagnostic Commands

## Check ports

```
ss -lntp
```

---

## Verify DRBD port connectivity

```
nc -zv othernode 7789
```

---

## Verify corosync connectivity

```
nc -zvu othernode 5404
```

---

# 15. RDQM Best Practices

1. Always run RDQM on **three nodes**.
2. Ensure **NTP time synchronization** across nodes.
3. Use **consistent hostnames and DNS**.
4. Ensure **firewalls allow cluster traffic**.
5. Monitor **DRBD replication health** regularly.

---

# 16. Quick Health Check Script

A simple quick check:

```
rdqmstatus
crm_mon -1
cat /proc/drbd
systemctl status pacemaker
systemctl status corosync
```

If all look healthy, RDQM should be operational.

