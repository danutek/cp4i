# StreamSage Architecture Overview

**Version:** 1.0  
**Last Updated:** 2026-03-21  
**Owner:** Platform Team

---

## Overview

StreamSage is an event-driven platform for processing and managing healthcare transactions using Apache Kafka, IBM Event Streams, and microservices architecture deployed on OpenShift.

---

## High-Level Architecture

```
┌─────────────────────────────────────────────────────────────────────┐
│                         StreamSage Platform                          │
└─────────────────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────────────────┐
│                          Presentation Layer                          │
├─────────────────────────────────────────────────────────────────────┤
│                                                                       │
│  ┌──────────────────────────────────────────────────────────────┐  │
│  │              StreamSage Console (Next.js)                     │  │
│  │  - Transaction Management UI                                  │  │
│  │  - Real-time Monitoring Dashboard                            │  │
│  │  - User Management                                            │  │
│  └──────────────────────────────────────────────────────────────┘  │
│                                                                       │
└─────────────────────────────────────────────────────────────────────┘
                                  │
                                  ▼
┌─────────────────────────────────────────────────────────────────────┐
│                          Application Layer                           │
├─────────────────────────────────────────────────────────────────────┤
│                                                                       │
│  ┌──────────────┐  ┌──────────────┐  ┌──────────────┐             │
│  │ API Gateway  │  │ ingest-      │  │ outbox-      │             │
│  │ (FastAPI)    │  │ service      │  │ publisher    │             │
│  └──────┬───────┘  └──────┬───────┘  └──────┬───────┘             │
│         │                  │                  │                      │
│  ┌──────┴──────────────────┴──────────────────┴──────┐             │
│  │                                                      │             │
│  │  ┌──────────────┐  ┌──────────────┐  ┌──────────┐ │             │
│  │  │ LLM          │  │ Policy       │  │ Human    │ │             │
│  │  │ Orchestration│  │ Guardrails   │  │ Review   │ │             │
│  │  └──────────────┘  └──────────────┘  └──────────┘ │             │
│  │                                                      │             │
│  │              StreamSage Services                    │             │
│  └──────────────────────────────────────────────────────┘             │
│                                                                       │
└─────────────────────────────────────────────────────────────────────┘
                                  │
                                  ▼
┌─────────────────────────────────────────────────────────────────────┐
│                          Integration Layer                           │
├─────────────────────────────────────────────────────────────────────┤
│                                                                       │
│  ┌──────────────────────────────────────────────────────────────┐  │
│  │                    Apache Kafka (Event Streams)               │  │
│  │                                                                │  │
│  │  Topics:                                                       │  │
│  │  - streamsage.ingest.transaction                              │  │
│  │  - streamsage.transaction.event                               │  │
│  │  - streamsage.ai.event                                        │  │
│  │  - streamsage.approval.event                                  │  │
│  │  - streamsage.audit.event                                     │  │
│  │                                                                │  │
│  │  Components:                                                   │  │
│  │  - 3 Kafka Brokers (HA)                                       │  │
│  │  - Cruise Control (Rebalancing)                               │  │
│  │  - Schema Registry                                            │  │
│  └──────────────────────────────────────────────────────────────┘  │
│                                                                       │
│  ┌──────────────────────────────────────────────────────────────┐  │
│  │                    Kafka Connect                              │  │
│  │  - JDBC Sink Connector (PostgreSQL)                           │  │
│  │  - JDBC Source Connector (External DBs)                       │  │
│  └──────────────────────────────────────────────────────────────┘  │
│                                                                       │
└─────────────────────────────────────────────────────────────────────┘
                                  │
                                  ▼
┌─────────────────────────────────────────────────────────────────────┐
│                            Data Layer                                │
├─────────────────────────────────────────────────────────────────────┤
│                                                                       │
│  ┌──────────────────────────────────────────────────────────────┐  │
│  │                    PostgreSQL Database                        │  │
│  │  - Transactions                                                │  │
│  │  - Transaction Families                                        │  │
│  │  - Audit Logs                                                  │  │
│  │  - Outbox Pattern                                              │  │
│  └──────────────────────────────────────────────────────────────┘  │
│                                                                       │
│  ┌──────────────────────────────────────────────────────────────┐  │
│  │                    Redis (Caching)                            │  │
│  │  - Session Cache                                               │  │
│  │  - Query Cache                                                 │  │
│  └──────────────────────────────────────────────────────────────┘  │
│                                                                       │
└─────────────────────────────────────────────────────────────────────┘
```

---

## Component Details

### Presentation Layer

#### StreamSage Console
- **Technology:** Next.js, React, TypeScript
- **Purpose:** Web-based user interface
- **Features:**
  - Transaction management
  - Real-time monitoring
  - User administration
  - Reporting and analytics
- **Deployment:** OpenShift Route with TLS

### Application Layer

#### API Gateway
- **Technology:** FastAPI (Python)
- **Purpose:** Central API entry point
- **Responsibilities:**
  - Request routing
  - Authentication/Authorization
  - Rate limiting
  - API versioning
- **Scaling:** Horizontal (3+ replicas)

#### ingest-service (Consumer Service)
- **Technology:** Python, Kafka Consumer
- **Purpose:** Consume and process transactions
- **Responsibilities:**
  - Consume from Kafka topics
  - Validate transactions
  - Store in PostgreSQL
  - Publish to outbox
- **Scaling:** Horizontal based on consumer lag

#### outbox-publisher
- **Technology:** Python
- **Purpose:** Implement outbox pattern
- **Responsibilities:**
  - Poll outbox table
  - Publish events to Kafka
  - Ensure at-least-once delivery
- **Scaling:** Single instance with leader election

#### LLM Orchestration
- **Technology:** Python
- **Purpose:** AI/ML integration
- **Responsibilities:**
  - Route tasks to LLM
  - Build case packets
  - Validate outputs
- **Integration:** External LLM APIs

#### Policy Guardrails
- **Technology:** Python
- **Purpose:** Business rule enforcement
- **Responsibilities:**
  - Validate transactions
  - Apply business rules
  - Compliance checks

#### Human Review
- **Technology:** Python
- **Purpose:** Manual review workflow
- **Responsibilities:**
  - Queue items for review
  - Track review status
  - Escalation management

### Integration Layer

#### IBM Event Streams (Kafka)
- **Version:** 11.x
- **Configuration:**
  - 3 Kafka brokers (HA)
  - 3 ZooKeeper nodes
  - Cruise Control enabled
  - TLS encryption
  - SCRAM-SHA-512 authentication
- **Storage:** 50Gi per broker (dev), 100Gi+ (prod)
- **Replication Factor:** 3
- **Min ISR:** 2

#### Kafka Connect
- **Configuration:**
  - 2 replicas (HA)
  - JDBC connectors
  - Custom plugins
- **Connectors:**
  - PostgreSQL Sink
  - External DB Sources

### Data Layer

#### PostgreSQL
- **Version:** 14+
- **Configuration:**
  - Primary-replica setup
  - Connection pooling
  - Automated backups
- **Schema:**
  - Transactions
  - Transaction families
  - Audit logs
  - Outbox table
  - Flexible attributes

#### Redis
- **Purpose:** Caching layer
- **Configuration:**
  - Sentinel for HA
  - Persistence enabled
- **Use Cases:**
  - Session management
  - Query caching
  - Rate limiting

---

## Deployment Architecture

### GitOps with ArgoCD

```
┌─────────────────────────────────────────────────────────────────────┐
│                          Git Repository                              │
│                    (Source of Truth)                                 │
├─────────────────────────────────────────────────────────────────────┤
│                                                                       │
│  deploy/                                                              │
│  ├── apps/                                                            │
│  │   ├── base/                    # Base configurations              │
│  │   │   ├── event-streams/                                          │
│  │   │   ├── kafka-connect/                                          │
│  │   │   ├── kafka-topics/                                           │
│  │   │   ├── streamsage-console/                                     │
│  │   │   └── network-policies/                                       │
│  │   │                                                                │
│  │   ├── overlays/                # Environment-specific             │
│  │   │   ├── dev/                                                    │
│  │   │   ├── test/                                                   │
│  │   │   ├── staging/                                                │
│  │   │   └── prod/                                                   │
│  │   │                                                                │
│  │   └── argocd/                  # ArgoCD configuration             │
│  │       ├── applicationsets/                                        │
│  │       └── projects/                                               │
│  │                                                                    │
│  └── clusters/                    # Cluster resources                │
│      └── cluster-config/                                             │
│                                                                       │
└─────────────────────────────────────────────────────────────────────┘
                                  │
                                  │ Git Pull
                                  ▼
┌─────────────────────────────────────────────────────────────────────┐
│                            ArgoCD                                     │
├─────────────────────────────────────────────────────────────────────┤
│                                                                       │
│  ┌──────────────────────────────────────────────────────────────┐  │
│  │                    ApplicationSets                            │  │
│  │  - event-streams-appset                                       │  │
│  │  - kafka-connect-appset                                       │  │
│  │  - kafka-topics-appset                                        │  │
│  │  - streamsage-console-appset                                  │  │
│  │  - network-policies-appset                                    │  │
│  └──────────────────────────────────────────────────────────────┘  │
│                                                                       │
│  ┌──────────────────────────────────────────────────────────────┐  │
│  │                    Generated Applications                     │  │
│  │  - dev-event-streams                                          │  │
│  │  - dev-kafka-connect                                          │  │
│  │  - test-event-streams                                         │  │
│  │  - prod-event-streams                                         │  │
│  │  - (auto-generated for each environment)                      │  │
│  └──────────────────────────────────────────────────────────────┘  │
│                                                                       │
└─────────────────────────────────────────────────────────────────────┘
                                  │
                                  │ Apply
                                  ▼
┌─────────────────────────────────────────────────────────────────────┐
│                        OpenShift Cluster                             │
├─────────────────────────────────────────────────────────────────────┤
│                                                                       │
│  Namespaces:                                                          │
│  - kafka-{env}         # Kafka resources                             │
│  - streamsage-{env}    # StreamSage services                         │
│  - openshift-gitops    # ArgoCD                                      │
│  - openshift-monitoring # Prometheus, Grafana                        │
│                                                                       │
└─────────────────────────────────────────────────────────────────────┘
```

### Network Architecture

```
┌─────────────────────────────────────────────────────────────────────┐
│                        External Traffic                              │
└─────────────────────────────────────────────────────────────────────┘
                                  │
                                  ▼
┌─────────────────────────────────────────────────────────────────────┐
│                    OpenShift Router/Ingress                          │
│                         (TLS Termination)                            │
└─────────────────────────────────────────────────────────────────────┘
                                  │
                                  ▼
┌─────────────────────────────────────────────────────────────────────┐
│                    Network Policies (Zero-Trust)                     │
├─────────────────────────────────────────────────────────────────────┤
│                                                                       │
│  Default: Deny All                                                    │
│                                                                       │
│  Allowed Traffic:                                                     │
│  ┌────────────────────────────────────────────────────────────┐    │
│  │ Router → Console                                            │    │
│  │ Console → API Gateway                                       │    │
│  │ API Gateway → Services                                      │    │
│  │ Services → Kafka                                            │    │
│  │ Services → PostgreSQL                                       │    │
│  │ Services → Redis                                            │    │
│  │ Kafka Connect → Kafka                                       │    │
│  │ Kafka Connect → PostgreSQL                                  │    │
│  │ Prometheus → All (metrics)                                  │    │
│  └────────────────────────────────────────────────────────────┘    │
│                                                                       │
└─────────────────────────────────────────────────────────────────────┘
```

---

## Data Flow

### Transaction Ingestion Flow

```
1. External System
       │
       │ HTTP POST
       ▼
2. API Gateway
       │
       │ Validate & Route
       ▼
3. Kafka Topic (streamsage.ingest.transaction)
       │
       │ Consume
       ▼
4. ingest-service
       │
       ├─► Validate Transaction
       │
       ├─► Store in PostgreSQL
       │
       └─► Write to Outbox Table
              │
              ▼
5. outbox-publisher
       │
       │ Poll Outbox
       ▼
6. Kafka Topic (streamsage.transaction.event)
       │
       ├─► LLM Orchestration
       │
       ├─► Policy Guardrails
       │
       └─► Human Review (if needed)
```

### Event Processing Flow

```
Kafka Topic
    │
    ├─► Consumer Group 1 (ingest-service)
    │   └─► Process & Store
    │
    ├─► Consumer Group 2 (event-monitor)
    │   └─► Monitor & Alert
    │
    └─► Consumer Group 3 (analytics)
        └─► Aggregate & Report
```

---

## Security Architecture

### Authentication & Authorization

```
┌─────────────────────────────────────────────────────────────────────┐
│                          User/Service                                │
└─────────────────────────────────────────────────────────────────────┘
                                  │
                                  │ JWT Token
                                  ▼
┌─────────────────────────────────────────────────────────────────────┐
│                          API Gateway                                 │
│                    (Token Validation)                                │
└─────────────────────────────────────────────────────────────────────┘
                                  │
                                  │ Validated Request
                                  ▼
┌─────────────────────────────────────────────────────────────────────┐
│                        RBAC Enforcement                              │
│                                                                       │
│  Roles:                                                               │
│  - Admin: Full access                                                │
│  - Operator: Read/Write transactions                                 │
│  - Viewer: Read-only access                                          │
│  - Service: Service-to-service                                       │
│                                                                       │
└─────────────────────────────────────────────────────────────────────┘
```

### Network Security

- **Zero-Trust Model:** Default deny all traffic
- **Network Policies:** Explicit allow rules
- **TLS Encryption:** All inter-service communication
- **Secrets Management:** OpenShift Secrets, Sealed Secrets
- **Pod Security:** Security contexts, non-root users

---

## Monitoring & Observability

### Metrics Collection

```
┌─────────────────────────────────────────────────────────────────────┐
│                        Application Metrics                           │
│  - HTTP request rates                                                │
│  - Response times                                                    │
│  - Error rates                                                       │
│  - Business metrics                                                  │
└─────────────────────────────────────────────────────────────────────┘
                                  │
                                  │ /metrics endpoint
                                  ▼
┌─────────────────────────────────────────────────────────────────────┐
│                          Prometheus                                  │
│  - Scrape metrics                                                    │
│  - Evaluate alert rules                                              │
│  - Store time-series data                                            │
└─────────────────────────────────────────────────────────────────────┘
                                  │
                    ┌─────────────┴─────────────┐
                    │                           │
                    ▼                           ▼
┌──────────────────────────────┐  ┌──────────────────────────────┐
│         Grafana              │  │      Alertmanager            │
│  - Dashboards                │  │  - Route alerts              │
│  - Visualization             │  │  - Notifications             │
└──────────────────────────────┘  └──────────────────────────────┘
```

### Logging Architecture

```
┌─────────────────────────────────────────────────────────────────────┐
│                        Application Logs                              │
│  - Structured JSON logs                                              │
│  - Correlation IDs                                                   │
│  - Request tracing                                                   │
└─────────────────────────────────────────────────────────────────────┘
                                  │
                                  │ stdout/stderr
                                  ▼
┌─────────────────────────────────────────────────────────────────────┐
│                    OpenShift Logging (EFK)                           │
│  - Elasticsearch: Log storage                                        │
│  - Fluentd: Log collection                                           │
│  - Kibana: Log visualization                                         │
└─────────────────────────────────────────────────────────────────────┘
```

---

## Disaster Recovery

### Backup Strategy

- **Kafka:** Topic replication (RF=3)
- **PostgreSQL:** Daily automated backups
- **Configuration:** Git repository (version controlled)
- **Secrets:** Encrypted backups

### Recovery Procedures

1. **Kafka Failure:** Automatic failover to replica brokers
2. **Database Failure:** Restore from backup, replay Kafka events
3. **Service Failure:** Kubernetes auto-restart, horizontal scaling
4. **Cluster Failure:** DR cluster with MirrorMaker2 replication

---

## Scalability

### Horizontal Scaling

- **Services:** Scale replicas based on CPU/memory
- **Kafka:** Add brokers, rebalance partitions
- **Database:** Read replicas for read-heavy workloads

### Vertical Scaling

- **Increase resources:** CPU, memory per pod
- **Storage expansion:** Persistent volume resizing

---

## Technology Stack

| Layer | Technology | Version |
|-------|-----------|---------|
| **Container Platform** | OpenShift | 4.12+ |
| **GitOps** | ArgoCD | 2.8+ |
| **Event Streaming** | IBM Event Streams | 11.x |
| **Message Broker** | Apache Kafka | 3.6+ |
| **Database** | PostgreSQL | 14+ |
| **Cache** | Redis | 7+ |
| **Frontend** | Next.js | 14+ |
| **Backend** | Python/FastAPI | 3.11+/0.104+ |
| **Monitoring** | Prometheus/Grafana | Latest |
| **Service Mesh** | (Optional) Istio | 1.18+ |

---

## References

- [Deployment Runbook](runbooks/DEPLOYMENT_RUNBOOK.md)
- [Troubleshooting Guide](runbooks/TROUBLESHOOTING_GUIDE.md)
- [Migration Guide](../MIGRATION_GUIDE.md)
- [Phase Implementation Summaries](../)

---

**Document Control:**
- **Version:** 1.0
- **Last Review:** 2026-03-21
- **Next Review:** 2026-06-21
- **Approved By:** Platform Team Lead