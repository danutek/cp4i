# Event-Driven Data Pipeline

## Kafka → PostgreSQL using IBM Event Streams and Kafka Connect

---

# 1. Introduction

This guide demonstrates how to build a simple **event-driven data pipeline** using:

* **IBM Event Streams (Kafka)**
* **Kafka Connect**
* **JDBC Sink Connector**
* **PostgreSQL**

The pipeline consumes messages from a Kafka topic and writes them into a PostgreSQL table using **upsert semantics**.

This pattern is commonly used for:

* Event-driven data integration
* Operational data replication
* Building queryable projections of event streams
* Microservice state persistence

---

# 2. Final Architecture

```id="arch-flow"
Producer
   │
   ▼
Kafka Topic (pnames)
   │
   ▼
Kafka Connect Worker
   │
   ▼
JDBC Sink Connector
   │
   ▼
PostgreSQL Database
```

---

# 3. Component Overview

| Component           | Purpose                               |
| ------------------- | ------------------------------------- |
| Kafka Producer      | Publishes event messages              |
| Kafka Topic         | Event transport layer                 |
| Kafka Connect       | Integration framework                 |
| JDBC Sink Connector | Writes records to relational database |
| PostgreSQL          | Data storage                          |

---

# 4. Data Flow

```id="data-flow"
Application Event
      │
      ▼
Kafka Producer
      │
      ▼
Kafka Topic
      │
      ▼
Kafka Connect Worker
      │
      ▼
JDBC Sink Connector
      │
      ▼
SQL INSERT / UPSERT
      │
      ▼
PostgreSQL Table
```

---

# 5. PostgreSQL Setup

## Create Database

Connect to PostgreSQL.

```bash
psql -U postgres
```

Create the database.

```sql id="create-db"
CREATE DATABASE pnames;
```

Switch to the database.

```sql id="connect-db"
\c pnames
```

---

## Create Table

```sql id="create-table"
CREATE TABLE public.test_events (
    id INTEGER PRIMARY KEY,
    name VARCHAR(100),
    description VARCHAR(255),
    amount DOUBLE PRECISION,
    quantity INTEGER,
    active BOOLEAN
);
```

---

## Grant Permissions

Allow the application user to modify the table.

```sql id="grant-table-owner"
ALTER TABLE public.test_events OWNER TO app;
```

---

# 6. Kafka Connect Image

Kafka Connect requires:

* JDBC Sink connector
* PostgreSQL JDBC driver

These must be placed in the **same plugin directory**.

---

## Dockerfile

```dockerfile id="dockerfile-connect"
FROM FROM cp.icr.io/cp/ibm-eventstreams-kafka:12.2.2

USER root

RUN mkdir -p /opt/kafka/plugins/jdbc

COPY jdbc-connector-for-apache-kafka-6.10.0.jar /opt/kafka/plugins/jdbc/
COPY postgresql-42.7.10.jar /opt/kafka/plugins/jdbc/

USER 1001
```

---

## Build and Push Image

```bash
docker build -t quay.io/danutek_us/kc1:4 .
docker push quay.io/danutek_us/kc1:4
```

---

# 7. KafkaConnect Deployment

Create a KafkaConnect cluster using the custom image.

## kafkaconnect.yaml

```yaml id="kafkaconnect-yaml"
apiVersion: eventstreams.ibm.com/v1beta2
kind: KafkaConnect
metadata:
  name: kc
  namespace: kafka
  annotations:
    eventstreams.ibm.com/use-connector-resources: "true"
spec:
  replicas: 1
  image: quay.io/danutek_us/kc1:4

  bootstrapServers: kafka-es-kafka-bootstrap.kafka.svc:9093

  authentication:
    type: scram-sha-512
    username: danutek
    passwordSecret:
      secretName: danutek
      password: password

  tls:
    trustedCertificates:
      - secretName: kafka-es-cluster-ca-cert
        certificate: ca.crt

  config:
    group.id: connect-cluster

    config.storage.topic: connect-cluster-configs
    offset.storage.topic: connect-cluster-offsets
    status.storage.topic: connect-cluster-status

    config.storage.replication.factor: 1
    offset.storage.replication.factor: 1
    status.storage.replication.factor: 1

    key.converter: org.apache.kafka.connect.storage.StringConverter
    value.converter: org.apache.kafka.connect.json.JsonConverter
    value.converter.schemas.enable: "true"
```

Deploy it:

```bash
oc apply -f kafkaconnect.yaml
```

---

# 8. JDBC Sink Connector

## pnames-sink.yaml

```yaml id="connector-yaml"
apiVersion: kafka.strimzi.io/v1beta2
kind: KafkaConnector
metadata:
  name: pnames-sink
  namespace: kafka
  labels:
    strimzi.io/cluster: kc
spec:
  class: io.confluent.connect.jdbc.JdbcSinkConnector
  tasksMax: 1
  config:

    topics: pnames

    connection.url: jdbc:postgresql://pg-primary.tej-project.svc:5432/pnames
    connection.user: app
    connection.password: <password>

    table.name.format: public.test_events

    insert.mode: upsert
    pk.mode: record_value
    pk.fields: id

    auto.create: false
    auto.evolve: false

    errors.tolerance: all
    errors.log.enable: true
```

Deploy the connector:

```bash
oc apply -f pnames-sink.yaml
```

---

# 9. Producer Configuration

Create a producer configuration for TLS + SCRAM authentication.

## producer.properties

```properties id="producer-properties"
bootstrap.servers=kafka-es-kafka-bootstrap.kafka.svc:9093

security.protocol=SASL_SSL

ssl.truststore.location=/path/es.p12
ssl.truststore.password=<password>
ssl.truststore.type=PKCS12

sasl.mechanism=SCRAM-SHA-512
sasl.jaas.config=org.apache.kafka.common.security.scram.ScramLoginModule required \
  username="danutek" \
  password="<password>";

key.serializer=org.apache.kafka.common.serialization.StringSerializer
value.serializer=org.apache.kafka.common.serialization.StringSerializer
```

---

# 10. Test Message Format

Because the worker uses:

```id="schema-enabled"
value.converter.schemas.enable=true
```

messages must include a **Kafka Connect JSON schema envelope**.

Example:

```json id="sample-message"
{"schema":{"type":"struct","name":"test_events","fields":[{"field":"id","type":"int32"},{"field":"name","type":"string","optional":true},{"field":"description","type":"string","optional":true},{"field":"amount","type":"double","optional":true},{"field":"quantity","type":"int32","optional":true},{"field":"active","type":"boolean","optional":true}]},"payload":{"id":13,"name":"OrderA","description":"First","amount":125.5,"quantity":10,"active":true}}
```

---

# 11. Produce Test Event

```bash
kafka-console-producer.sh \
  --topic pnames \
  --producer.config producer.properties
```

Paste the JSON message and press **Enter**.

---

# 12. Verify Database Insert

Connect to PostgreSQL:

```sql
\c pnames
```

Query the table:

```sql id="verify-sql"
SELECT * FROM public.test_events;
```

Example output:

```id="result-table"
 id | name   | description | amount | quantity | active
----+--------+-------------+--------+----------+-------
 13 | OrderA | First       | 125.5  | 10       | true
```

---

# 13. Upsert Behavior

The connector uses:

```id="upsert-config"
insert.mode = upsert
pk.mode = record_value
pk.fields = id
```

Which generates SQL similar to:

```sql id="upsert-sql"
INSERT INTO public.test_events (...)
VALUES (...)
ON CONFLICT (id)
DO UPDATE SET ...
```

This ensures **idempotent updates**.

---

# 14. Common Troubleshooting

### JDBC Driver Not Found

```
No suitable driver found
```

Fix: place driver and connector jar in same plugin directory.

```
/opt/kafka/plugins/jdbc/
```

---

### Missing Schema

```
record value schema is missing
```

Cause:

```
schemas.enable=true
```

but message has no schema envelope.

---

### Invalid Schema Type

```
Unknown schema type: float64
```

Use:

```
double
```

instead.

---

### PostgreSQL Permission Error

```
permission denied for table
```

Fix:

```sql
ALTER TABLE public.test_events OWNER TO app;
```

---

# 15. Final Result

You now have a working event pipeline:

```id="final-flow"
Kafka Topic
   │
   ▼
Kafka Connect
   │
   ▼
JDBC Sink Connector
   │
   ▼
PostgreSQL
```

This pattern forms the basis of many **event-driven architectures**.
