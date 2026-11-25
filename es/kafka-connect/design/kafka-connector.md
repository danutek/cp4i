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
