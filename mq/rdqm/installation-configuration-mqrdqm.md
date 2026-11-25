# IBM MQ RDQM Complete Installation, Configuration, and Troubleshooting Guide

**ExampleCo**
**For Linux Administrators with Limited MQ Experience**

---

## Document Overview

This comprehensive guide provides step-by-step instructions for installing, configuring, and troubleshooting IBM MQ Replicated Data Queue Managers (RDQM) on Red Hat Enterprise Linux. It is specifically designed for Linux system administrators who may have limited experience with IBM MQ but need to manage RDQM clusters.

**Key Topics Covered:**
- Complete installation procedures
- Cluster configuration
- Queue manager management
- Monitoring and operations
- Comprehensive troubleshooting
- Kernel module signing for Secure Boot
- Best practices and quick reference

---

## Table of Contents

1. [Introduction](#1-introduction)
2. [What is RDQM?](#2-what-is-rdqm)
3. [Architecture Overview](#3-architecture-overview)
4. [Prerequisites and Requirements](#4-prerequisites-and-requirements)
5. [Installation Procedure](#5-installation-procedure)
6. [Kernel Module Signing for Secure Boot](#6-kernel-module-signing-for-secure-boot)
7. [Initial Configuration](#7-initial-configuration)
8. [Creating and Managing Queue Managers](#8-creating-and-managing-queue-managers)
9. [Monitoring and Operations](#9-monitoring-and-operations)
10. [Troubleshooting Guide](#10-troubleshooting-guide)
11. [Common Administrative Tasks](#11-common-administrative-tasks)
12. [Best Practices](#12-best-practices)
13. [Quick Reference](#13-quick-reference)
14. [Glossary](#14-glossary)

---

## 1. Introduction

### 1.1 Document Purpose

This guide serves as the primary reference for:
- **Installation**: Complete step-by-step installation of all RDQM components
- **Configuration**: Setting up three-node high availability clusters
- **Operations**: Day-to-day management, monitoring, and maintenance
- **Troubleshooting**: Diagnosing and resolving common and complex issues

### 1.2 Target Audience

This document is written for Linux system administrators who:
- Have experience with Red Hat Enterprise Linux administration
- May have limited or no experience with IBM MQ
- Are responsible for installing and maintaining RDQM clusters
- Need to perform routine monitoring and troubleshooting tasks

### 1.3 How to Use This Guide

- **New Installations**: Follow sections 1-8 sequentially
- **Troubleshooting**: Jump directly to section 10
- **Daily Operations**: Reference sections 9 and 13
- **Quick Answers**: Use section 13 (Quick Reference)

---

## 2. What is RDQM?

### 2.1 Overview

RDQM (Replicated Data Queue Manager) is IBM MQ's high availability solution that provides automatic failover capabilities across a three-node cluster. It ensures continuous availability of your message queuing infrastructure even when individual servers fail.

### 2.2 Key Concepts for Linux Administrators

**Think of RDQM as:**
- A clustered application similar to clustered databases you may already know
- Automatic failover without manual intervention (like Pacemaker-managed services)
- Block-level data replication (similar to DRBD or RAID across servers)
- A three-node quorum-based cluster (prevents split-brain scenarios)

**What RDQM Provides:**
- Three synchronized copies of queue manager data
- Automatic queue manager startup on healthy nodes during failures
- Quorum-based decision making (requires 2 of 3 nodes)
- Seamless failover for client applications

**What RDQM Does NOT Provide:**
- Shared storage (each node has independent local storage)
- Support for 2-node or 4+ node configurations (must be exactly 3 nodes)
- Compatibility with standard (non-replicated) queue managers

### 2.3 Use Cases

RDQM is ideal for:
- Mission-critical messaging infrastructure requiring high availability
- Applications that cannot tolerate message loss
- Environments requiring automatic failover
- Systems needing data center-level redundancy

---

## 3. Architecture Overview

### 3.1 Component Stack

RDQM is built on multiple layers of open-source and IBM technologies:

```
┌─────────────────────────────────────┐
│   IBM MQ Queue Manager              │  ← Application layer (message queuing)
├─────────────────────────────────────┤
│   Pacemaker (Resource Manager)      │  ← Cluster orchestration & failover
├─────────────────────────────────────┤
│   Corosync (Cluster Membership)     │  ← Node communication & heartbeat
├─────────────────────────────────────┤
│   DRBD (Block Replication)          │  ← Real-time data synchronization
├─────────────────────────────────────┤
│   LVM (Logical Volume Manager)      │  ← Storage management (drbdpool)
├─────────────────────────────────────┤
│   Filesystem (EXT4)                 │  ← File storage layer
└─────────────────────────────────────┘
```

**Component Descriptions:**

- **IBM MQ**: The message queue manager application
- **Pacemaker**: Manages cluster resources, decides where queue managers run
- **Corosync**: Maintains cluster membership, provides heartbeat communication
- **DRBD**: Replicates block devices in real-time across nodes
- **LVM**: Manages logical volumes in the drbdpool volume group
- **EXT4**: Filesystem for queue manager data (only EXT4 is supported)

### 3.2 Three-Node Cluster Design

```
┌──────────────┐         ┌──────────────┐         ┌──────────────┐
│   Node 1     │◄───────►│   Node 2     │◄───────►│   Node 3     │
│  (Primary)   │         │ (Secondary)  │         │ (Secondary)  │
│              │         │              │         │              │
│  QM1: Active │         │ QM1: Standby │         │ QM1: Standby │
│  QM2: Standby│         │ QM2: Active  │         │ QM2: Standby │
│  QM3: Standby│         │ QM3: Standby │         │ QM3: Active  │
└──────────────┘         └──────────────┘         └──────────────┘
       │                        │                        │
       └────────────────────────┴────────────────────────┘
              Pacemaker Cluster Communication
              DRBD Replication Network
```

**Key Points:**
- Each queue manager runs on one node (Primary) at a time
- Two other nodes maintain synchronized copies (Secondary)
- Multiple queue managers can run across the cluster
- Load can be distributed by running different QMs on different nodes

### 3.3 How Failover Works

**Normal Operation:**
1. One node runs the queue manager as Primary
2. Two nodes maintain synchronized replicas as Secondary
3. All three nodes continuously monitor each other via Pacemaker heartbeat
4. DRBD keeps data synchronized in real-time

**When a Node Fails:**
1. **Detection** (1-5 seconds): Pacemaker detects node failure via missed heartbeats
2. **Quorum Check**: Remaining nodes verify they have quorum (2 out of 3 nodes)
3. **Resource Selection**: Pacemaker selects which secondary becomes new primary
4. **DRBD Promotion**: DRBD promotes the replica volume to primary
5. **Filesystem Mount**: Filesystem is mounted on the new primary
6. **Queue Manager Start**: MQ queue manager starts on new primary node
7. **Service Restoration**: Applications reconnect and resume operations

**Typical Failover Time:** 30-60 seconds (depending on queue manager size and configuration)

### 3.4 Quorum and Split-Brain Prevention

**Quorum Requirement:**
- Minimum 2 out of 3 nodes must be online and communicating
- Prevents split-brain scenarios where multiple nodes think they're primary
- If only 1 node remains, it cannot start queue managers (no quorum)

**Split-Brain Prevention:**
- Three-node design ensures clear majority
- Quorum-based decisions prevent conflicting states
- DRBD fencing prevents data corruption

**Scenarios:**
- **3 nodes online**: Full redundancy, any node can fail
- **2 nodes online**: Cluster operational, no further redundancy
- **1 node online**: Cluster cannot operate (no quorum)

---

## 4. Prerequisites and Requirements

### 4.1 Hardware Requirements

#### Per Node Specifications

**CPU:**
- Architecture: x86-64 (Intel/AMD 64-bit)
- Minimum: 4 cores
- Recommended: 8+ cores for production workloads

**Memory:**
- Minimum: 8 GB RAM
- Recommended: 16 GB or more
- Additional RAM needed based on queue manager workload

**Storage:**
- **System Disk**: For OS and MQ binaries (50+ GB)
- **Data Disk(s)**: For drbdpool volume group
  - SSD strongly recommended for performance
  - Size based on queue manager data requirements
  - Example: 100-500 GB for typical deployments

**Network:**
- Three network interfaces (can use same physical interface):
  - **Primary Interface**: Pacemaker heartbeat
  - **Alternate Interface**: Redundant heartbeat (optional but recommended)
  - **Replication Interface**: DRBD data replication (dedicated recommended)
- Requirements:
  - Low latency: < 5ms (< 2ms preferred)
  - Sufficient bandwidth for replication workload
  - 1 Gbps minimum, 10 Gbps recommended for high throughput

### 4.2 Operating System Requirements

**Supported Platforms:**
- Red Hat Enterprise Linux (RHEL) 8.8 or later
- Red Hat Enterprise Linux (RHEL) 9.2 or later

**Critical Requirements:**
- All three nodes must run identical RHEL version
- Kernel versions should be synchronized across nodes
- DRBD kernel modules must match running kernel version

### 4.3 Software Prerequisites

#### RHEL 8 Required Packages

```bash
dnf install -y \
    cifs-utils \
    libtool-ltdl \
    libxslt \
    net-snmp-libs \
    nfs-utils \
    perl-TimeDate \
    psmisc \
    python36 \
    python3-lxml
```

#### RHEL 9 Required Packages

```bash
dnf install -y \
    libxslt \
    net-snmp-libs \
    nfs-utils \
    nfs-utils-coreos \
    perl-TimeDate \
    python3-lxml \
    python-unversioned-command
```

#### SELinux Additional Packages

If using SELinux in Enforcing mode:

```bash
dnf install -y \
    selinux-policy \
    selinux-policy-base \
    rpm-plugin-selinux \
    selinux-policy-targeted
```

### 4.4 User and Group Configuration

#### Before Installation

Create mqm user and group with **consistent IDs across all nodes**:

```bash
# Execute on all three nodes with SAME UID/GID
groupadd -g 1001 mqm
useradd -u 1001 -g mqm -d /home/mqm -m -s /bin/bash mqm
```

**Critical Requirements:**
- mqm user must have identical UID on all nodes
- mqm group must have identical GID on all nodes
- Pacemaker installation will create hacluster user (UID 189) and haclient group (GID 189)

#### After Installation

Users managing RDQM must belong to both groups:

```bash
# Add user to required groups
usermod -a -G mqm,haclient <username>

# User must log out and back in for group changes to take effect
```

### 4.5 Storage Configuration

#### drbdpool Volume Group

Each node requires a volume group named **drbdpool**:

```bash
# Example: Create drbdpool from dedicated disk /dev/sdb
pvcreate /dev/sdb
vgcreate drbdpool /dev/sdb

# Verify configuration
vgs drbdpool
```

**Expected Output:**
```
VG       #PV #LV #SN Attr   VSize    VFree
drbdpool   1   0   0 wz--n- <100.00g <100.00g
```

**Critical Requirements:**
- Volume group MUST be named `drbdpool` (exact name)
- Do NOT enable clustering on volume group (no 'c' in Attr field)
- Use local storage only (not SAN or shared storage)
- SSD storage strongly recommended for performance
- Do NOT manually create logical volumes (MQ manages this automatically)

**Verify No Clustering Flag:**
```bash
vgs drbdpool -o vg_name,vg_attr
```

If you see `wz--nc` (note the 'c'), recreate without clustering:
```bash
vgremove drbdpool
vgcreate drbdpool /dev/sdb
```

### 4.6 Network Configuration

#### Required Ports

| Port Range | Protocol | Purpose | Notes |
|------------|----------|---------|-------|
| 5404-5407 | UDP | Corosync/Pacemaker | Cluster heartbeat communication |
| 7000-7100 | TCP | DRBD | Data replication traffic |
| 1414 | TCP | IBM MQ | Client connections (default, adjust as needed) |

#### Firewall Configuration

**Automated Setup (Recommended):**
```bash
# Run on each node as root
/opt/mqm/samp/rdqm/firewalld/configure.sh
firewall-cmd --reload
```

**Manual Configuration:**
```bash
# Add RDQM firewall services
firewall-cmd --permanent --add-service=rdqm-drbd
firewall-cmd --permanent --add-service=rdqm-pacemaker
firewall-cmd --permanent --add-service=rdqm-mq
firewall-cmd --reload

# Verify configuration
firewall-cmd --list-all
```

#### Hostname Requirements

**Each node must have:**
- Valid hostname returned by `uname -n`
- Hostname compliant with RFC 952/1123
- Hostname resolvable via DNS or /etc/hosts
- All nodes able to resolve each other's hostnames

**Verification:**
```bash
# On each node
uname -n
hostname -f

# Test resolution from each node
ping -c 1 node1
ping -c 1 node2
ping -c 1 node3
```

### 4.7 SELinux Configuration

If SELinux is enabled in Enforcing mode:

```bash
# Check SELinux status
getenforce

# Configure DRBD for SELinux
semanage permissive -a drbd_t

# Alternative: Install drbd-selinux package (preferred)
# This package is included in RDQM installation media
```

### 4.8 Secure Boot Considerations

If UEFI Secure Boot is enabled:

```bash
# Check Secure Boot status
mokutil --sb-state
```

**If Secure Boot is enabled:**
- DRBD kernel modules must be properly signed
- See Section 6 "Kernel Module Signing for Secure Boot"
- Without proper signing: `modprobe: ERROR: could not insert 'drbd': Required key not available`

### 4.9 Time Synchronization

**Critical Requirement:** All nodes must have synchronized time.

```bash
# Install and enable chronyd
dnf install -y chrony
systemctl enable chronyd
systemctl start chronyd

# Verify synchronization
chronyc tracking
chronyc sources
```

**Expected Output:**
```
Reference ID    : <NTP server>
Stratum         : 3
System time     : 0.000000XXX seconds slow/fast of NTP time
```

---

## 5. Installation Procedure

### 5.1 Installation Overview

Installation must be performed on all three nodes in the following order:
1. System preparation
2. DRBD kernel module installation
3. DRBD utilities installation
4. Pacemaker installation
5. IBM MQ installation
6. RDQM component installation

### 5.2 Pre-Installation Checklist

Verify on each node before starting:

- [ ] RHEL 8.8+ or RHEL 9.2+ installed and updated
- [ ] All prerequisite packages installed
- [ ] mqm user and group created with consistent UID/GID (1001)
- [ ] drbdpool volume group created and verified
- [ ] Firewall configured to allow required ports
- [ ] Hostnames configured and resolvable
- [ ] Time synchronized via NTP/Chrony
- [ ] Installation media available and accessible
- [ ] Root access or sudo privileges available

### 5.3 Step 1: Prepare YUM/DNF Repositories

RDQM includes specific versions of DRBD and Pacemaker. Prevent system from using alternative versions:

**For RHEL 8:**

Edit `/etc/yum.repos.d/redhat.repo` and add to `[rhel-8-for-x86_64-appstream-rpms]` section:

```ini
exclude=cluster* corosync* drbd kmod-drbd libqb* pacemaker* resource-agents* ktls-utils*
```

**For RHEL 9:**

Edit `/etc/yum.repos.d/redhat.repo` and add to `[rhel-9-for-x86_64-appstream-rpms]` section:

```ini
exclude=cluster* corosync* crm* libknet* libnozzle* libqb* pacemaker* python3-parallax* resource-agents* ktls-utils*
```

### 5.4 Step 2: Import LINBIT GPG Key

DRBD and Pacemaker packages are signed by LINBIT:

```bash
rpm --import https://packages.linbit.com/package-signing-pubkey.asc
```

### 5.5 Step 3: Mount Installation Media

```bash
# Create mount point
mkdir -p /mnt/mqinstall

# Mount ISO
mount -o loop /path/to/IBM_MQ_9.4.x_LINUX_X86-64.iso /mnt/mqinstall

# Or mount physical media
mount /dev/sr0 /mnt/mqinstall

# Navigate to installation directory
cd /mnt/mqinstall
```

### 5.6 Step 4: Identify and Install DRBD Kernel Module

**The DRBD kernel module MUST match your running kernel version.**

**Determine Required Module:**

```bash
# For RHEL 8
cd /mnt/mqinstall/Advanced/RDQM/PreReqs/el8/kmod-drbd-9
./modver

# For RHEL 9
cd /mnt/mqinstall/Advanced/RDQM/PreReqs/el9/kmod-drbd-9
./modver
```

Output example:
```
kmod-drbd-9.0.23_4.18.0-553-1.x86_64.rpm
```

**Install the Identified Module:**

```bash
# For RHEL 8 (use filename from modver output)
dnf install /mnt/mqinstall/Advanced/RDQM/PreReqs/el8/kmod-drbd-9/kmod-drbd-9.0.23_4.18.0-553-1.x86_64.rpm

# For RHEL 9 (use filename from modver output)
dnf install /mnt/mqinstall/Advanced/RDQM/PreReqs/el9/kmod-drbd-9/kmod-drbd-9.x.xx_x.xx.x-xxx-1.x86_64.rpm
```

**Verify Installation:**
```bash
rpm -qa | grep kmod-drbd
modinfo drbd
lsmod | grep drbd
```

### 5.7 Step 5: Install DRBD Utilities

```bash
# For RHEL 8
dnf install /mnt/mqinstall/Advanced/RDQM/PreReqs/el8/drbd-utils-9/*

# For RHEL 9
dnf install /mnt/mqinstall/Advanced/RDQM/PreReqs/el9/drbd-utils-9/*
```

**Verify Installation:**
```bash
rpm -qa | grep drbd-utils
drbdadm --version
```

### 5.8 Step 6: Install Pacemaker

```bash
# For RHEL 8
dnf install /mnt/mqinstall/Advanced/RDQM/PreReqs/el8/pacemaker-2/*

# For RHEL 9
dnf install /mnt/mqinstall/Advanced/RDQM/PreReqs/el9/pacemaker-2/*
```

**Note:** DNF will automatically resolve and install dependencies.

**Verify Installation:**
```bash
rpm -qa | grep pacemaker
rpm -qa | grep corosync
systemctl status pacemaker
systemctl status corosync
```

### 5.9 Step 7: Accept IBM MQ License

```bash
cd /mnt/mqinstall
./mqlicense.sh
```

Read and accept the license agreement when prompted.

### 5.10 Step 8: Install IBM MQ

**Minimum Required Components:**

```bash
dnf install /mnt/mqinstall/MQSeriesGSKit* \
            /mnt/mqinstall/MQSeriesServer* \
            /mnt/mqinstall/MQSeriesRuntime*
```

**Optional Components (Recommended):**

```bash
dnf install /mnt/mqinstall/MQSeriesSamples* \
            /mnt/mqinstall/MQSeriesJava* \
            /mnt/mqinstall/MQSeriesJRE*
```

**Verify Installation:**
```bash
/opt/mqm/bin/dspmqver
```

Expected output shows IBM MQ version information.

### 5.11 Step 9: Install RDQM

```bash
dnf install /mnt/mqinstall/Advanced/RDQM/MQSeriesRDQM*
```

**Verify Installation:**
```bash
rpm -qa | grep MQSeriesRDQM
/opt/mqm/bin/rdqmstatus
```

### 5.12 Step 10: Verify Installation on All Nodes

Run on each node:

```bash
# Check DRBD module loaded
lsmod | grep drbd

# Check Pacemaker (should be inactive until configured)
systemctl status pacemaker

# Check MQ version
/opt/mqm/bin/dspmqver

# Check RDQM status
/opt/mqm/bin/rdqmstatus
```

**Expected rdqmstatus Output (before configuration):**
```
Node:                                   <hostname>
OS kernel version:                      5.14.0-xxx
DRBD OS kernel version:                 5.14.0-xxx
DRBD version:                           9.x.xx
DRBD kernel module status:              Loaded

No queue managers are configured.
```

### 5.13 Post-Installation Tasks

**On each node:**

1. **Unmount Installation Media:**
```bash
cd /
umount /mnt/mqinstall
```

2. **Verify Kernel Modules:**
```bash
lsmod | grep drbd
modinfo drbd
modinfo drbd_transport_tcp
```

3. **Do NOT Start Pacemaker Yet:**
   - Pacemaker will be started during cluster configuration
   - Starting it prematurely can cause issues

---

## 6. Kernel Module Signing for Secure Boot

### 6.1 Overview

If your systems have UEFI Secure Boot enabled, kernel modules must be properly signed to load. The DRBD kernel modules provided by LINBIT are signed with their key, which must be enrolled in your system's Machine Owner Key (MOK) database.

**Note:** This section covers viewing, signing, and verifying module signatures. For detailed key generation and enrollment procedures, refer to the Red Hat Enterprise Linux documentation "Managing, monitoring, and updating the kernel" (included in the IbmDocs folder).

### 6.2 Checking Secure Boot Status

**Verify if Secure Boot is enabled:**

```bash
mokutil --sb-state
```

**Possible Outputs:**
- `SecureBoot enabled` - Secure Boot is active, modules must be signed
- `SecureBoot disabled` - Secure Boot is not active
- `This system doesn't support Secure Boot` - System doesn't have UEFI Secure Boot

### 6.3 Viewing Module Signatures

**Check if DRBD module is signed:**

```bash
# View DRBD module signature information
modinfo drbd | grep -E 'sig|signer'

# Check signature details
modinfo -F sig_key drbd
modinfo -F signer drbd
modinfo -F sig_hashalgo drbd
```

**Expected Output for Signed Module:**
```
signer:         LINBIT Information Technologies GmbH
sig_key:        XX:XX:XX:XX:XX:XX:XX:XX:XX:XX:XX:XX:XX:XX:XX:XX:XX:XX:XX:XX
sig_hashalgo:   sha256
```

**If module is not signed, output will be empty.**

**Check DRBD transport module:**
```bash
modinfo drbd_transport_tcp | grep -E 'sig|signer'
```

### 6.4 Signing DRBD Kernel Modules

If you need to sign the DRBD modules with your own key (after generating keys per Red Hat documentation):

**Locate the Modules:**
```bash
# Find DRBD module location
MODULE_PATH=$(modinfo -n drbd)
echo "DRBD module: $MODULE_PATH"

# Find transport module location
TRANSPORT_PATH=$(modinfo -n drbd_transport_tcp)
echo "Transport module: $TRANSPORT_PATH"
```

**Sign the DRBD Module:**
```bash
# Sign with your private key
/usr/src/kernels/$(uname -r)/scripts/sign-file \
    sha256 \
    /path/to/your/private-key.priv \
    /path/to/your/public-key.der \
    $MODULE_PATH
```

**Sign the DRBD Transport Module:**
```bash
# Sign transport module
/usr/src/kernels/$(uname -r)/scripts/sign-file \
    sha256 \
    /path/to/your/private-key.priv \
    /path/to/your/public-key.der \
    $TRANSPORT_PATH
```

**Note:** The signing keys must be generated and enrolled according to Red Hat documentation procedures.

### 6.5 Verifying Module Signatures

**After signing, verify the signature:**

```bash
# Check DRBD module signature
modinfo drbd | grep -E 'sig|signer'

# Verify signature is recognized
modprobe --dry-run --show-depends drbd
```

**If signature is valid:**
```
insmod /lib/modules/.../drbd.ko
insmod /lib/modules/.../drbd_transport_tcp.ko
```

**If signature is invalid or missing with Secure Boot enabled:**
```
modprobe: ERROR: could not insert 'drbd': Required key not available
```

### 6.6 Loading Signed Modules

**After modules are properly signed and keys enrolled:**

```bash
# Load DRBD modules
modprobe drbd
modprobe drbd_transport_tcp

# Verify modules loaded successfully
lsmod | grep drbd
```

**Expected Output:**
```
drbd_transport_tcp     40960  0
drbd                 1019904  0 drbd_transport_tcp
libcrc32c              12288  2 xfs,drbd
```

### 6.7 Troubleshooting Module Signing Issues

**Issue: Module won't load with "Required key not available"**

```bash
# Verify Secure Boot is enabled
mokutil --sb-state

# Check if module has signature
modinfo drbd | grep sig

# Check kernel ring buffer for details
dmesg | grep -i drbd | tail -20

# Solution options:
# 1. Sign the module with your key
# 2. Enroll LINBIT's public key in MOK
# 3. Disable Secure Boot (not recommended for production)
```

**Issue: Module signature verification fails**

```bash
# Check for signature errors in logs
dmesg | grep -i "signature"

# Verify signing key is enrolled
mokutil --list-enrolled | grep -i linbit

# Re-sign module if needed
```

**Issue: Wrong kernel version after update**

```bash
# Check running kernel
uname -r

# Check DRBD module kernel version
modinfo drbd | grep vermagic

# If mismatch, install correct kmod-drbd package
# See https://ibm.biz/mqrdqmkernelmods
```

### 6.8 Best Practices for Module Signing

1. **Secure Key Storage**: Store signing keys in secure location with restricted access
2. **Document Procedures**: Maintain clear documentation of signing process
3. **Test After Signing**: Always verify modules load correctly after signing
4. **Plan for Updates**: When kernel updates, modules must be re-signed
5. **Automate When Possible**: Consider automation for consistency
6. **Backup Keys**: Maintain secure backups of signing keys

### 6.9 Reference Documentation

For complete details on key generation, enrollment, and advanced signing procedures:
- **Red Hat Documentation**: "Managing, monitoring, and updating the kernel" (included in IbmDocs folder)
- **LINBIT Documentation**: https://linbit.com/drbd-user-guide/drbd-guide-9_0-en/#s-linbit-packages
- **IBM MQ RDQM Kernel Modules**: https://ibm.biz/mqrdqmkernelmods

---

## 7. Initial Configuration

### 7.1 Overview

After installing RDQM on all three nodes, you must configure the Pacemaker cluster (HA group). This creates the cluster configuration that allows the three nodes to work together.

### 7.2 Configuration File: rdqm.ini

The cluster configuration is defined in `/var/mqm/rdqm.ini`. This file must be created on one node and will be distributed to the others during configuration.

### 7.3 Creating rdqm.ini

**On the first node, create `/var/mqm/rdqm.ini`:**

```bash
# Create directory if it doesn't exist
mkdir -p /var/mqm

# Create configuration file
vi /var/mqm/rdqm.ini
```

### 7.4 Configuration Examples

#### Basic Configuration (Single Network)

**Minimal configuration using one network interface:**

```ini
# Node definitions
Node:
  Name=node1
  HA_Replication=192.168.1.101

Node:
  Name=node2
  HA_Replication=192.168.1.102

Node:
  Name=node3
  HA_Replication=192.168.1.103
```

#### Recommended Configuration (Separate Networks)

**Configuration with separate heartbeat and replication networks:**

```ini
# Node 1 configuration
Node:
  Name=node1
  HA_Primary=192.168.1.101
  HA_Alternate=192.168.2.101
  HA_Replication=10.10.10.101

# Node 2 configuration
Node:
  Name=node2
  HA_Primary=192.168.1.102
  HA_Alternate=192.168.2.102
  HA_Replication=10.10.10.102

# Node 3 configuration
Node:
  Name=node3
  HA_Primary=192.168.1.103
  HA_Alternate=192.168.2.103
  HA_Replication=10.10.10.103
```

### 7.5 Configuration Parameters

| Parameter | Required | Description |
|-----------|----------|-------------|
| `Name` | Yes | Hostname of the node (must match `uname -n`) |
| `HA_Primary` | No | Primary IP for Pacemaker heartbeat |
| `HA_Alternate` | No | Alternate IP for Pacemaker heartbeat (redundancy) |
| `HA_Replication` | Yes | IP address for DRBD replication traffic |

**Network Design Recommendations:**

1. **Single Network (Simple):**
   - Use only `HA_Replication`
   - All traffic uses one network
   - Suitable for testing or low-traffic environments

2. **Dual Network (Recommended):**
   - Use `HA_Primary` and `HA_Replication`
   - Separates heartbeat from replication traffic
   - Better performance and fault tolerance

3. **Triple Network (Maximum Redundancy):**
   - Use all three parameters
   - Provides redundant heartbeat paths
   - Best for production environments

### 7.6 Configuring the Cluster

**Run on the first node only (as root or with sudo):**

```bash
# Configure the cluster
rdqmadm -c
```

**What this command does:**
- Reads `/var/mqm/rdqm.ini`
- Configures DRBD on all three nodes
- Configures Pacemaker cluster
- Starts cluster services
- Verifies connectivity between nodes

**Expected Output:**
```
Configuring RDQM HA group.
Creating DRBD configuration.
Starting DRBD.
Creating Pacemaker configuration.
Starting Pacemaker.
RDQM HA group configuration complete.
```

**If configuration fails:**
- Check network connectivity between nodes
- Verify firewall rules
- Ensure hostnames resolve correctly
- Check `/var/log/messages` for errors

### 7.7 Verifying Cluster Configuration

**Check cluster status:**

```bash
# Quick status check
rdqmstatus

# Detailed cluster view
crm_mon -1

# Check DRBD status
drbdadm status
```

**Expected rdqmstatus Output:**
```
Node:                                   node1
OS kernel version:                      5.14.0-xxx
DRBD OS kernel version:                 5.14.0-xxx
DRBD version:                           9.x.xx
DRBD kernel module status:              Loaded

No queue managers are configured.
```

**Expected crm_mon Output:**
```
Cluster Summary:
  * Stack: corosync
  * Current DC: node1
  * Last updated: <timestamp>
  * 3 nodes configured
  * 0 resource instances configured

Node List:
  * Online: [ node1 node2 node3 ]
```

### 7.8 Troubleshooting Configuration Issues

**Cluster won't form:**
```bash
# Check Pacemaker status on each node
systemctl status pacemaker
systemctl status corosync

# Check logs
journalctl -u pacemaker -n 50
journalctl -u corosync -n 50

# Verify network connectivity
ping node2
ping node3
```

**DRBD issues:**
```bash
# Check DRBD module
lsmod | grep drbd

# Check DRBD configuration
cat /etc/drbd.d/global_common.conf

# View DRBD logs
journalctl -u drbd -n 50
```

**Hostname resolution issues:**
```bash
# Verify hostname
uname -n

# Test resolution
getent hosts node1
getent hosts node2
getent hosts node3
```

### 7.9 Reconfiguring the Cluster

**If you need to change the configuration:**

```bash
# Unconfigure the cluster (WARNING: Destroys all queue managers)
rdqmadm -u

# Edit rdqm.ini
vi /var/mqm/rdqm.ini

# Reconfigure
rdqmadm -c
```

**⚠️ WARNING:** `rdqmadm -u` will delete all queue manager data. Only use this if you need to completely rebuild the cluster.

---

## 8. Creating and Managing Queue Managers

### 8.1 Understanding RDQM Queue Manager Creation

Unlike standard IBM MQ, RDQM queue managers are created in a specific sequence:
1. Create secondary instances on two nodes
2. Create primary instance on one node
3. Start the queue manager

### 8.2 Creating Your First RDQM

#### Step 1: Create Secondary Instances

Run on two of the three nodes (as root or mqm user with sudo):

```bash
# On node2
crtmqm -sxs -fs 5G QM1

# On node3
crtmqm -sxs -fs 5G QM1
```

**Parameters:**
- `-sxs`: Creates a secondary instance for replicated data HA
- `-fs 5G`: Allocates 5GB for queue manager data (adjust as needed)
- `QM1`: Queue manager name (must be same on all nodes)

**Expected Output:**
```
Creating replicated data queue manager configuration.
Secondary queue manager created.
```

#### Step 2: Create Primary Instance

Run on the node where you want the queue manager to initially run (node1):

```bash
# On node1
crtmqm -sx -fs 5G QM1
```

**Parameters:**
- `-sx`: Creates a primary instance for replicated data HA
- `-fs 5G`: Must match the size used for secondaries
- `QM1`: Queue manager name

**Expected Output:**
```
Creating replicated data queue manager configuration.
IBM MQ queue manager 'QM1' created.
Directory '/var/mqm/vols/qm1/qmgr/qm1' created.
Replication is being configured.
```

#### Step 3: Verify Creation

```bash
# Check status on any node
rdqmstatus -m QM1
```

**Expected Output:**
```
Node:                                   node1
Queue manager name:                     QM1
Queue manager status:                   Ended normally
HA status:                              Normal
HA current location:                    This node
HA preferred location:                  This node
HA blocked location:                    None
```

### 8.3 Starting a Queue Manager

```bash
# Start the queue manager
strmqm QM1
```

**What happens:**
- Pacemaker determines which node should run the queue manager
- DRBD promotes the volume to primary on that node
- Filesystem is mounted
- Queue manager starts
- Replication begins to secondary nodes

**Verify it's running:**
```bash
rdqmstatus -m QM1
```

**Expected Output:**
```
Queue manager status:                   Running
HA status:                              Normal
HA current location:                    This node
```

### 8.4 Stopping a Queue Manager

**Graceful stop:**
```bash
endmqm QM1
```

**Immediate stop (use with caution):**
```bash
endmqm -i QM1
```

**Forced stop (emergency only):**
```bash
endmqm -p QM1
```

### 8.5 Deleting a Queue Manager

**⚠️ WARNING:** This permanently deletes all queue manager data.

```bash
# Stop the queue manager first
endmqm -i QM1

# Delete from any node
dltmqm QM1
```

**Expected Output:**
```
Removing replicated data queue manager configuration.
IBM MQ queue manager 'QM1' deleted.
```

### 8.6 Setting Preferred Location

The preferred location determines which node the queue manager should run on when that node is available.

```bash
# Set node1 as preferred location for QM1
rdqmadm -m QM1 -p -n node1
```

**Verify:**
```bash
rdqmstatus -m QM1
```

Look for:
```
HA preferred location:                  node1
```

### 8.7 Basic Queue Manager Configuration

After creating a queue manager, configure it for use:

**Example: Basic configuration for client connections**

```bash
# Start runmqsc
runmqsc QM1

# Define a listener
DEFINE LISTENER(QM1.LISTENER) TRPTYPE(TCP) PORT(1414) CONTROL(QMGR)
START LISTENER(QM1.LISTENER)

# Define a server connection channel
DEFINE CHANNEL(QM1.SVRCONN) CHLTYPE(SVRCONN)

# Set channel authentication
SET CHLAUTH(QM1.SVRCONN) TYPE(ADDRESSMAP) ADDRESS('*') USERSRC(CHANNEL)

# Define a local queue for testing
DEFINE QLOCAL(TEST.QUEUE)

# Exit runmqsc
END
```

### 8.8 Managing Multiple Queue Managers

You can run multiple queue managers in the same HA group:

```bash
# Create QM2 on different nodes
# Secondaries on node1 and node3
crtmqm -sxs -fs 5G QM2  # on node1
crtmqm -sxs -fs 5G QM2  # on node3

# Primary on node2
crtmqm -sx -fs 5G QM2   # on node2

# Start QM2
strmqm QM2
```

**Best practice:** Distribute queue managers across nodes for load balancing.

---

## 9. Monitoring and Operations

### 9.1 Daily Health Checks

**Quick cluster health check script:**

```bash
#!/bin/bash
# Save as /usr/local/bin/rdqm-health-check.sh

echo "=== RDQM Health Check ==="
echo "Date: $(date)"
echo ""

echo "--- Node Status ---"
rdqmstatus
echo ""

echo "--- Cluster Status ---"
crm_mon -1
echo ""

echo "--- DRBD Status ---"
drbdadm status
echo ""

echo "--- Pacemaker Service ---"
systemctl status pacemaker --no-pager
echo ""

echo "--- Corosync Service ---"
systemctl status corosync --no-pager
```

### 9.2 Key Monitoring Commands

#### rdqmstatus

**Check overall RDQM status:**
```bash
rdqmstatus
```

**Check specific queue manager:**
```bash
rdqmstatus -m QM1
```

**Key fields to monitor:**
- `Queue manager status`: Should be "Running" or "Running elsewhere"
- `HA status`: Should be "Normal"
- `HA current location`: Shows which node is primary
- `DRBD kernel module status`: Should be "Loaded"

#### crm_mon

**Real-time cluster monitoring:**
```bash
crm_mon
```
Press Ctrl+C to exit.

**One-time status check:**
```bash
crm_mon -1
```

**Key information:**
- `Current DC`: Designated Coordinator (cluster leader)
- `partition with quorum`: Confirms cluster has quorum
- `Online`: List of online nodes
- `Resource status`: Shows where queue managers are running

#### drbdadm status

**Check DRBD replication status:**
```bash
drbdadm status
```

**Example healthy output:**
```
qm1 role:Primary
  disk:UpToDate
  node2 role:Secondary
    peer-disk:UpToDate
  node3 role:Secondary
    peer-disk:UpToDate
```

**Key fields:**
- `role`: Primary (active) or Secondary (standby)
- `disk`: Should be "UpToDate"
- `peer-disk`: Should be "UpToDate" for all peers

**Warning signs:**
- `Inconsistent`: Data is not synchronized
- `Diskless`: No storage available
- `StandAlone`: Node is disconnected from cluster

### 9.3 Log File Locations

**IBM MQ logs:**
```bash
# Queue manager errors
/var/mqm/qmgrs/<QMNAME>/errors/AMQERR01.LOG

# System-wide MQ errors
/var/mqm/errors/AMQERR01.LOG
```

**Pacemaker logs:**
```bash
# View recent Pacemaker logs
journalctl -u pacemaker -n 100

# Follow Pacemaker logs in real-time
journalctl -u pacemaker -f
```

**Corosync logs:**
```bash
# View recent Corosync logs
journalctl -u corosync -n 100

# Follow Corosync logs in real-time
journalctl -u corosync -f
```

**DRBD logs:**
```bash
# View DRBD messages
journalctl -u drbd -n 100

# System messages related to DRBD
grep drbd /var/log/messages
```

### 9.4 Performance Monitoring

**Check queue manager resource usage:**
```bash
# CPU and memory usage
ps aux | grep -E 'amqzxma0|amqzlaa0|amqzlsa0' | grep QM1

# Disk I/O
iostat -x 2 5

# Network traffic on replication interface
iftop -i eth1  # adjust interface name
```

**Monitor queue depths:**
```bash
# Display queue depths
echo "DISPLAY QLOCAL(*) CURDEPTH" | runmqsc QM1 | grep CURDEPTH
```

---

## 10. Troubleshooting Guide

### 10.1 Systematic Troubleshooting Approach

When issues occur, follow this systematic approach:

1. **Identify the symptom**
2. **Check cluster status**
3. **Check DRBD replication**
4. **Check services**
5. **Check logs**
6. **Check network connectivity**
7. **Check resources**

### 10.2 Troubleshooting Workflow Script

```bash
#!/bin/bash
# Quick troubleshooting script

echo "=== RDQM Troubleshooting ==="
echo ""

echo "Step 1: Check RDQM Status"
rdqmstatus
echo ""

echo "Step 2: Check Cluster Status"
crm_mon -1
echo ""

echo "Step 3: Check DRBD Status"
drbdadm status
echo ""

echo "Step 4: Check Services"
systemctl status pacemaker --no-pager
systemctl status corosync --no-pager
echo ""

echo "Step 5: Check Kernel Modules"
lsmod | grep drbd
echo ""

echo "Step 6: Check Firewall"
firewall-cmd --list-all
echo ""

echo "Step 7: Recent Errors"
journalctl -p err -n 20 --no-pager
```

### 10.3 Common Issues and Solutions

#### Issue 1: Queue Manager Won't Start

**Symptoms:**
- `strmqm` command fails
- Queue manager status shows "Ended normally" or "Ended unexpectedly"

**Diagnosis:**
```bash
# Check queue manager status
rdqmstatus -m QM1

# Check cluster resources
crm_mon -1

# Check for failed actions
crm status | grep -i failed

# Check MQ error logs
tail -100 /var/mqm/qmgrs/QM1/errors/AMQERR01.LOG
```

**Common Causes and Solutions:**

**A. Cluster doesn't have quorum**
```bash
# Check node status
crm_mon -1

# Solution: Ensure at least 2 nodes are online
# Check network connectivity between nodes
ping node2
ping node3
```

**B. DRBD not synchronized**
```bash
# Check DRBD status
drbdadm status

# If showing Inconsistent, force synchronization (CAUTION)
# Only do this if you're sure which node has good data
drbdadm invalidate qm1  # on the node with bad data
```

**C. Resource failures**
```bash
# Check for failed resources
crm status

# Clear failed actions
crm resource cleanup qm1
```

#### Issue 2: Node Not Joining Cluster

**Symptoms:**
- Node shows as offline in `crm_mon`
- Pacemaker service fails to start

**Diagnosis:**
```bash
# Check Pacemaker status
systemctl status pacemaker
systemctl status corosync

# Check logs
journalctl -u pacemaker -n 50
journalctl -u corosync -n 50

# Check network connectivity
ping node1
ping node2
ping node3
```

**Solutions:**

**A. Firewall blocking cluster traffic**
```bash
# Check firewall rules
firewall-cmd --list-all

# Add required ports
/opt/mqm/samp/rdqm/firewalld/configure.sh
firewall-cmd --reload
```

**B. Hostname resolution issues**
```bash
# Verify hostname
uname -n

# Check resolution
getent hosts node1
getent hosts node2
getent hosts node3

# Fix /etc/hosts if needed
vi /etc/hosts
```

**C. Time synchronization issues**
```bash
# Check time on all nodes
date

# Check NTP/Chrony status
chronyc tracking

# Restart chronyd if needed
systemctl restart chronyd
```

#### Issue 3: DRBD Replication Not Working

**Symptoms:**
- `drbdadm status` shows "Inconsistent" or "StandAlone"
- Replication lag increasing

**Diagnosis:**
```bash
# Check DRBD status
drbdadm status
cat /proc/drbd

# Check DRBD configuration
drbdadm dump qm1

# Check network connectivity on replication interface
ping -I eth1 node2  # adjust interface
```

**Solutions:**

**A. Network issues**
```bash
# Test replication network
ping -c 10 10.10.10.102  # replication IP of other node

# Check interface status
ip addr show eth1

# Check for packet loss
mtr 10.10.10.102
```

**B. Split-brain scenario**
```bash
# Check for split-brain
drbdadm status | grep -i split

# Resolve split-brain (CAUTION - data loss possible)
# On the node with outdated data:
drbdadm disconnect qm1
drbdadm secondary qm1
drbdadm connect --discard-my-data qm1
```

#### Issue 4: Kernel Module Not Loading

**Symptoms:**
- `lsmod | grep drbd` shows nothing
- `rdqmstatus` shows "DRBD kernel module status: Not loaded"

**Diagnosis:**
```bash
# Try to load module manually
modprobe drbd
modprobe drbd_transport_tcp

# Check for errors
dmesg | tail -20

# Check module info
modinfo drbd
```

**Solutions:**

**A. Wrong kernel module version**
```bash
# Check running kernel
uname -r

# Check installed DRBD module
rpm -qa | grep kmod-drbd

# Install correct module for your kernel
# See installation section for details
```

**B. Secure Boot blocking module**
```bash
# Check Secure Boot status
mokutil --sb-state

# If enabled, see Section 6 for module signing
```

---

## 11. Common Administrative Tasks

### 11.1 Performing Controlled Failover

**To move a queue manager to a different node:**

```bash
# Method 1: Using rdqmadm (recommended)
rdqmadm -m QM1 -p -n node2

# Method 2: Using crm resource move
crm resource move qm1 node2

# After failover, clear the constraint
crm resource clear qm1
```

**Monitor failover in real-time:**
```bash
# In one terminal
watch -n 1 'rdqmstatus -m QM1'

# In another terminal
crm_mon
```

### 11.2 Planned Maintenance on a Node

**To take a node offline for maintenance:**

```bash
# Step 1: Move all queue managers off the node
rdqmadm -m QM1 -p -n node2
rdqmadm -m QM2 -p -n node3

# Step 2: Put node in standby mode
crm node standby node1

# Step 3: Verify no resources running on node1
crm_mon -1

# Step 4: Perform maintenance
# ... do your maintenance work ...

# Step 5: Bring node back online
crm node online node1

# Step 6: Verify node rejoined cluster
crm_mon -1
```

### 11.3 Applying OS Updates

**IMPORTANT:** DRBD kernel modules must match the running kernel.

**Procedure:**

```bash
# Step 1: Check current kernel and DRBD module
uname -r
rpm -qa | grep kmod-drbd

# Step 2: Before updating kernel, check if matching DRBD module exists
# Visit: https://ibm.biz/mqrdqmkernelmods

# Step 3: If new DRBD module needed, obtain it first

# Step 4: Perform rolling update (one node at a time)

# On node1:
# Move queue managers to other nodes
rdqmadm -m QM1 -p -n node2

# Put node in standby
crm node standby node1

# Update OS
dnf update -y

# Install new DRBD module if kernel updated
dnf install /path/to/new-kmod-drbd-*.rpm

# Reboot
reboot

# After reboot, verify
uname -r
lsmod | grep drbd
rdqmstatus

# Bring node online
crm node online node1

# Repeat for node2 and node3
```

### 11.4 Backing Up Queue Manager Data

**Backup procedure:**

```bash
# Step 1: Stop the queue manager
endmqm QM1

# Step 2: Verify it's stopped
rdqmstatus -m QM1

# Step 3: Create backup
tar czf /backup/qm1-backup-$(date +%Y%m%d).tar.gz \
    /var/mqm/vols/qm1/qmgr

# Step 4: Restart queue manager
strmqm QM1

# Alternative: Use dmpmqcfg for configuration backup
dmpmqcfg -m QM1 -a > /backup/qm1-config-$(date +%Y%m%d).mqsc
```

---

## 12. Best Practices

### 12.1 Operational Best Practices

1. **Always Use Three Nodes**
   - Never attempt to run with fewer than three nodes
   - Two nodes cannot maintain quorum if one fails

2. **Monitor Regularly**
   - Set up automated monitoring
   - Check cluster status daily
   - Monitor DRBD replication health
   - Watch disk space usage

3. **Keep Systems Synchronized**
   - Maintain same OS version across all nodes
   - Keep kernel versions synchronized
   - Apply updates in rolling fashion

4. **Network Design**
   - Use dedicated network for DRBD replication
   - Ensure low latency between nodes (< 2ms preferred)
   - Use redundant network paths for heartbeat

5. **Storage Best Practices**
   - Use SSD for drbdpool
   - Size drbdpool appropriately for growth
   - Monitor disk I/O performance
   - Keep 20% free space in drbdpool

6. **Backup Strategy**
   - Regular backups of queue manager configurations
   - Test restore procedures
   - Document backup/restore process
   - Store backups off-cluster

7. **Change Management**
   - Test changes in non-production first
   - Perform changes during maintenance windows
   - Have rollback plan ready
   - Document all changes

8. **Security**
   - Keep systems patched
   - Use firewall rules
   - Implement proper authentication
   - Audit access regularly

### 12.2 Performance Best Practices

1. **Queue Manager Sizing**
   - Allocate sufficient space for growth
   - Monitor queue depths
   - Plan for peak loads

2. **Network Optimization**
   - Use jumbo frames if supported
   - Ensure sufficient bandwidth for replication
   - Monitor network latency

3. **Disk I/O Optimization**
   - Use SSD storage
   - Separate OS and data disks
   - Monitor I/O wait times

4. **Load Distribution**
   - Distribute queue managers across nodes
   - Balance workload
   - Use preferred locations strategically

---

## 13. Quick Reference

### 13.1 Essential Commands

**Status Checks:**
```bash
rdqmstatus                    # Overall RDQM status
rdqmstatus -m QM1            # Specific queue manager
crm_mon -1                   # Cluster status
drbdadm status               # DRBD replication status
```

**Queue Manager Operations:**
```bash
strmqm QM1                   # Start queue manager
endmqm QM1                   # Stop queue manager (graceful)
endmqm -i QM1                # Stop queue manager (immediate)
dspmq                        # Display queue managers
```

**Cluster Operations:**
```bash
crm node standby node1       # Put node in standby
crm node online node1        # Bring node online
crm resource cleanup qm1     # Clear failed actions
crm resource clear qm1       # Remove constraints
```

**Failover:**
```bash
rdqmadm -m QM1 -p -n node2   # Move QM1 to node2
```

**Service Management:**
```bash
systemctl status pacemaker   # Check Pacemaker
systemctl status corosync    # Check Corosync
systemctl restart pacemaker  # Restart Pacemaker
```

### 13.2 Important File Locations

**Configuration:**
```
/var/mqm/rdqm.ini                    # RDQM cluster configuration
/etc/drbd.d/                         # DRBD configuration
/etc/corosync/corosync.conf          # Corosync configuration
```

**Logs:**
```
/var/mqm/errors/                     # MQ system errors
/var/mqm/qmgrs/QM1/errors/          # Queue manager errors
journalctl -u pacemaker              # Pacemaker logs
journalctl -u corosync               # Corosync logs
```

**Data:**
```
/var/mqm/vols/qm1/                  # Queue manager data
```

### 13.3 Port Reference

| Port | Protocol | Service | Purpose |
|------|----------|---------|---------|
| 5404-5407 | UDP | Corosync | Cluster heartbeat |
| 7000-7100 | TCP | DRBD | Data replication |
| 1414 | TCP | IBM MQ | Client connections |

### 13.4 Common Error Messages

| Error | Meaning | Solution |
|-------|---------|----------|
| "Operation not permitted" | Permission issue | Check user groups, sudo config |
| "No quorum" | < 2 nodes online | Fix network, bring nodes online |
| "Inconsistent" | DRBD out of sync | Check network, resync DRBD |
| "Required key not available" | Secure Boot issue | Sign modules or enroll key |

### 13.5 Health Check Indicators

**Healthy System:**
- ✅ All 3 nodes online
- ✅ Cluster has quorum
- ✅ DRBD status: UpToDate/UpToDate
- ✅ Queue managers running
- ✅ No failed actions

**Warning Signs:**
- ⚠️ Only 2 nodes online (no redundancy)
- ⚠️ DRBD showing lag
- ⚠️ High disk I/O wait
- ⚠️ Network latency increasing

**Critical Issues:**
- ❌ Only 1 node online (no quorum)
- ❌ DRBD Inconsistent or StandAlone
- ❌ Queue manager won't start
- ❌ Failed resource actions

---

## 14. Glossary

**DRBD (Distributed Replicated Block Device)**: Software that replicates block devices between servers, providing the data synchronization for RDQM.

**Pacemaker**: Cluster resource manager that controls which node runs the queue manager and handles failover.

**Corosync**: Cluster communication layer that maintains node membership and provides messaging between cluster nodes.

**Quorum**: Minimum number of nodes (2 out of 3) required to make cluster decisions and prevent split-brain.

**Primary Node**: The node currently running the active queue manager.

**Secondary Node**: A node with a synchronized copy of the queue manager data, ready to take over if needed.

**Split-Brain**: A scenario where cluster nodes cannot communicate and multiple nodes try to run the same queue manager simultaneously (prevented by quorum).

**HA Group**: The three-node cluster configuration for high availability.

**drbdpool**: The LVM volume group used by RDQM to allocate storage for queue managers.

**Failover**: The automatic process of moving a queue manager from a failed node to a healthy node.

**Preferred Location**: The node where a queue manager should run when that node is available.

---

## Document Revision History

| Version | Date | Author | Changes |
|---------|------|--------|---------|
| 1.0 | 2026-03-09 | System Administrator | Initial comprehensive guide for ExampleCo |

---

## Emergency Contacts

**IBM Support:**
- Support Portal: https://www.ibm.com/mysupport
- Phone: [Your IBM support number]

**Internal Contacts:**
- Primary Admin: [Name/Contact]
- Secondary Admin: [Name/Contact]
- Manager: [Name/Contact]

---

## Useful Links

- IBM MQ Documentation: https://www.ibm.com/docs/en/ibm-mq/
- DRBD Documentation: https://docs.linbit.com/
- Pacemaker Documentation: https://clusterlabs.org/pacemaker/
- RDQM Kernel Modules: https://ibm.biz/mqrdqmkernelmods
- Red Hat Documentation: https://access.redhat.com/documentation/

---

**End of Document**

For questions or updates to this document, contact the ExampleCo IT Department.
