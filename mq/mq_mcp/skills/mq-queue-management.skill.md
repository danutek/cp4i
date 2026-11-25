# IBM MQ Queue Management Operations

## Description
This skill provides comprehensive guidance for managing IBM MQ queues via REST API, including creation, modification, monitoring, and deletion. Essential for maintaining consistent queue configurations across multiple queue managers.

## Prerequisites
- IBM MQ REST API access (see `mq-rest-api-basics.skill.md`)
- Authority to manage queues (minimum: +chg, +dsp, +crt, +dlt)
- Queue manager running and accessible

## Environment Setup
```bash
# Source from mq-rest-api-basics or set directly
export MQ_REST_HOST="your-mq-host.example.com"
export MQ_REST_PORT="9443"
export MQ_REST_USER="mqadmin"
export MQ_REST_PASS="secure_password"
export MQ_QMGR_NAME="QM1"

# Base URL for convenience
MQ_BASE_URL="https://${MQ_REST_HOST}:${MQ_REST_PORT}/ibmmq/rest/v2/admin"
```

## List Queues

### List All Queues
```bash
# Get all queues
curl -k -u ${MQ_REST_USER}:${MQ_REST_PASS} \
  "${MQ_BASE_URL}/qmgr/${MQ_QMGR_NAME}/queue"

# Filter by queue name pattern
curl -k -u ${MQ_REST_USER}:${MQ_REST_PASS} \
  "${MQ_BASE_URL}/qmgr/${MQ_QMGR_NAME}/queue?name=APP.*"

# Get specific queue types only
curl -k -u ${MQ_REST_USER}:${MQ_REST_PASS} \
  "${MQ_BASE_URL}/qmgr/${MQ_QMGR_NAME}/queue?type=local"
```

### Get Queue Details
```bash
# Get specific queue configuration
curl -k -u ${MQ_REST_USER}:${MQ_REST_PASS} \
  "${MQ_BASE_URL}/qmgr/${MQ_QMGR_NAME}/queue/MY.QUEUE"

# Get queue with specific attributes
curl -k -u ${MQ_REST_USER}:${MQ_REST_PASS} \
  "${MQ_BASE_URL}/qmgr/${MQ_QMGR_NAME}/queue/MY.QUEUE?attributes=currentDepth,maximumDepth,openInputCount,openOutputCount"
```

## Create Queues

### Create Local Queue
```bash
curl -k -u ${MQ_REST_USER}:${MQ_REST_PASS} \
  -X POST \
  -H "Content-Type: application/json" \
  -H "ibm-mq-rest-csrf-token: value" \
  "${MQ_BASE_URL}/qmgr/${MQ_QMGR_NAME}/queue" \
  -d '{
    "name": "MY.NEW.QUEUE",
    "type": "local",
    "maximumDepth": 5000,
    "maximumMessageLength": 4194304,
    "defaultPersistence": "persistent",
    "description": "Application queue for processing"
  }'
```

### Create Remote Queue Definition
```bash
curl -k -u ${MQ_REST_USER}:${MQ_REST_PASS} \
  -X POST \
  -H "Content-Type: application/json" \
  -H "ibm-mq-rest-csrf-token: value" \
  "${MQ_BASE_URL}/qmgr/${MQ_QMGR_NAME}/queue" \
  -d '{
    "name": "REMOTE.QUEUE",
    "type": "remote",
    "remoteQueueName": "TARGET.QUEUE",
    "remoteQueueManagerName": "QM2",
    "transmissionQueueName": "QM2.XMIT"
  }'
```

### Create Alias Queue
```bash
curl -k -u ${MQ_REST_USER}:${MQ_REST_PASS} \
  -X POST \
  -H "Content-Type: application/json" \
  -H "ibm-mq-rest-csrf-token: value" \
  "${MQ_BASE_URL}/qmgr/${MQ_QMGR_NAME}/queue" \
  -d '{
    "name": "ALIAS.QUEUE",
    "type": "alias",
    "targetName": "MY.NEW.QUEUE",
    "targetType": "queue"
  }'
```

### Create Model Queue
```bash
curl -k -u ${MQ_REST_USER}:${MQ_REST_PASS} \
  -X POST \
  -H "Content-Type: application/json" \
  -H "ibm-mq-rest-csrf-token: value" \
  "${MQ_BASE_URL}/qmgr/${MQ_QMGR_NAME}/queue" \
  -d '{
    "name": "MODEL.QUEUE",
    "type": "model",
    "maximumDepth": 1000,
    "defaultPersistence": "nonPersistent",
    "definesType": "temporary"
  }'
```

## Modify Queues

### Update Queue Attributes
```bash
# Change maximum depth
curl -k -u ${MQ_REST_USER}:${MQ_REST_PASS} \
  -X PATCH \
  -H "Content-Type: application/json" \
  -H "ibm-mq-rest-csrf-token: value" \
  "${MQ_BASE_URL}/qmgr/${MQ_QMGR_NAME}/queue/MY.QUEUE" \
  -d '{
    "maximumDepth": 10000
  }'

# Update multiple attributes
curl -k -u ${MQ_REST_USER}:${MQ_REST_PASS} \
  -X PATCH \
  -H "Content-Type: application/json" \
  -H "ibm-mq-rest-csrf-token: value" \
  "${MQ_BASE_URL}/qmgr/${MQ_QMGR_NAME}/queue/MY.QUEUE" \
  -d '{
    "maximumDepth": 10000,
    "maximumMessageLength": 10485760,
    "description": "Updated queue configuration"
  }'
```

### Enable/Disable Queue
```bash
# Disable GET operations (inhibit gets)
curl -k -u ${MQ_REST_USER}:${MQ_REST_PASS} \
  -X PATCH \
  -H "Content-Type: application/json" \
  -H "ibm-mq-rest-csrf-token: value" \
  "${MQ_BASE_URL}/qmgr/${MQ_QMGR_NAME}/queue/MY.QUEUE" \
  -d '{
    "inhibitGet": "inhibited"
  }'

# Enable GET operations (allow gets)
curl -k -u ${MQ_REST_USER}:${MQ_REST_PASS} \
  -X PATCH \
  -H "Content-Type: application/json" \
  -H "ibm-mq-rest-csrf-token: value" \
  "${MQ_BASE_URL}/qmgr/${MQ_QMGR_NAME}/queue/MY.QUEUE" \
  -d '{
    "inhibitGet": "allowed"
  }'

# Disable PUT operations (inhibit puts)
curl -k -u ${MQ_REST_USER}:${MQ_REST_PASS} \
  -X PATCH \
  -H "Content-Type: application/json" \
  -H "ibm-mq-rest-csrf-token: value" \
  "${MQ_BASE_URL}/qmgr/${MQ_QMGR_NAME}/queue/MY.QUEUE" \
  -d '{
    "inhibitPut": "inhibited"
  }'

# Enable PUT operations (allow puts)
curl -k -u ${MQ_REST_USER}:${MQ_REST_PASS} \
  -X PATCH \
  -H "Content-Type: application/json" \
  -H "ibm-mq-rest-csrf-token: value" \
  "${MQ_BASE_URL}/qmgr/${MQ_QMGR_NAME}/queue/MY.QUEUE" \
  -d '{
    "inhibitPut": "allowed"
  }'
```

## Monitor Queues

### Get Queue Status
```bash
# Get current depth and open handles
curl -k -u ${MQ_REST_USER}:${MQ_REST_PASS} \
  "${MQ_BASE_URL}/qmgr/${MQ_QMGR_NAME}/queue/MY.QUEUE?status=*"

# Monitor specific status attributes
curl -k -u ${MQ_REST_USER}:${MQ_REST_PASS} \
  "${MQ_BASE_URL}/qmgr/${MQ_QMGR_NAME}/queue/MY.QUEUE?status=currentDepth,oldestMessageAge,openInputCount,openOutputCount"
```

### Check Queue Depth
```bash
# Simple depth check
DEPTH=$(curl -sk -u ${MQ_REST_USER}:${MQ_REST_PASS} \
  "${MQ_BASE_URL}/qmgr/${MQ_QMGR_NAME}/queue/MY.QUEUE?attributes=currentDepth" \
  | jq -r '.queue[0].status.currentDepth')

echo "Current depth: ${DEPTH}"

# Alert if depth exceeds threshold
THRESHOLD=4000
if [ ${DEPTH} -gt ${THRESHOLD} ]; then
  echo "WARNING: Queue depth ${DEPTH} exceeds threshold ${THRESHOLD}"
fi
```

### Monitor Multiple Queues
```bash
# Get depth for all application queues
curl -sk -u ${MQ_REST_USER}:${MQ_REST_PASS} \
  "${MQ_BASE_URL}/qmgr/${MQ_QMGR_NAME}/queue?name=APP.*&status=currentDepth,maximumDepth" \
  | jq -r '.queue[] | "\(.name): \(.status.currentDepth)/\(.maximumDepth)"'
```

## Clear Queues

### Clear Queue Messages
```bash
# Clear all messages from queue
curl -k -u ${MQ_REST_USER}:${MQ_REST_PASS} \
  -X DELETE \
  -H "ibm-mq-rest-csrf-token: value" \
  "${MQ_BASE_URL}/qmgr/${MQ_QMGR_NAME}/queue/MY.QUEUE/message"
```

## Delete Queues

### Delete Queue
```bash
# Delete queue (must be empty and closed)
curl -k -u ${MQ_REST_USER}:${MQ_REST_PASS} \
  -X DELETE \
  -H "ibm-mq-rest-csrf-token: value" \
  "${MQ_BASE_URL}/qmgr/${MQ_QMGR_NAME}/queue/MY.QUEUE"

# Force delete (purge messages first)
curl -k -u ${MQ_REST_USER}:${MQ_REST_PASS} \
  -X DELETE \
  -H "ibm-mq-rest-csrf-token: value" \
  "${MQ_BASE_URL}/qmgr/${MQ_QMGR_NAME}/queue/MY.QUEUE?purge=true"
```

## Batch Operations

### Create Multiple Queues from Template
```bash
# Create queues for multiple applications
for APP in APP1 APP2 APP3; do
  curl -k -u ${MQ_REST_USER}:${MQ_REST_PASS} \
    -X POST \
    -H "Content-Type: application/json" \
    -H "ibm-mq-rest-csrf-token: value" \
    "${MQ_BASE_URL}/qmgr/${MQ_QMGR_NAME}/queue" \
    -d "{
      \"name\": \"${APP}.REQUEST\",
      \"type\": \"local\",
      \"maximumDepth\": 5000,
      \"maximumMessageLength\": 4194304,
      \"defaultPersistence\": \"persistent\"
    }"
  
  curl -k -u ${MQ_REST_USER}:${MQ_REST_PASS} \
    -X POST \
    -H "Content-Type: application/json" \
    -H "ibm-mq-rest-csrf-token: value" \
    "${MQ_BASE_URL}/qmgr/${MQ_QMGR_NAME}/queue" \
    -d "{
      \"name\": \"${APP}.REPLY\",
      \"type\": \"local\",
      \"maximumDepth\": 5000,
      \"maximumMessageLength\": 4194304,
      \"defaultPersistence\": \"persistent\"
    }"
done
```

### Export Queue Definitions
```bash
# Export all application queue configurations
curl -sk -u ${MQ_REST_USER}:${MQ_REST_PASS} \
  "${MQ_BASE_URL}/qmgr/${MQ_QMGR_NAME}/queue?name=APP.*" \
  | jq '.queue[] | {name, type, maximumDepth, maximumMessageLength, defaultPersistence}' \
  > queue_definitions.json
```

### Compare Queue Configurations
```bash
# Compare queue config between two queue managers
diff \
  <(curl -sk -u ${MQ_REST_USER}:${MQ_REST_PASS} \
    "${MQ_BASE_URL}/qmgr/QM1/queue/MY.QUEUE" | jq -S .) \
  <(curl -sk -u ${MQ_REST_USER}:${MQ_REST_PASS} \
    "${MQ_BASE_URL}/qmgr/QM2/queue/MY.QUEUE" | jq -S .)
```

## Common Queue Attributes

| Attribute | Description | Default |
|-----------|-------------|---------|
| maximumDepth | Maximum messages allowed | 5000 |
| maximumMessageLength | Max message size (bytes) | 4194304 (4MB) |
| defaultPersistence | Message persistence | persistent |
| inhibitGet | GET operations control | allowed/inhibited |
| inhibitPut | PUT operations control | allowed/inhibited |
| shareability | Queue sharing | shareable |
| triggerControl | Trigger monitoring | off |
| triggerType | Trigger type | first |

## Error Handling

### Common Errors
```bash
# 2085 - Queue already exists
# 2053 - Queue not found
# 2063 - Queue in use (cannot delete)
# 2046 - Queue depth exceeded

# Check for errors in response
RESPONSE=$(curl -sk -u ${MQ_REST_USER}:${MQ_REST_PASS} \
  -X POST \
  -H "Content-Type: application/json" \
  -H "ibm-mq-rest-csrf-token: value" \
  "${MQ_BASE_URL}/qmgr/${MQ_QMGR_NAME}/queue" \
  -d '{"name": "TEST.QUEUE", "type": "local"}')

if echo "$RESPONSE" | jq -e '.error' > /dev/null; then
  echo "Error: $(echo "$RESPONSE" | jq -r '.error[0].message')"
  exit 1
fi
```

## MCP Server Integration

An MCP server can leverage these operations to:
- **Standardize queue creation** across environments
- **Monitor queue depths** and alert on thresholds
- **Audit configurations** for compliance
- **Batch operations** across multiple queue managers
- **Configuration drift detection** between environments

## Best Practices

1. **Naming conventions** - Use consistent prefixes (APP.*, SYS.*, etc.)
2. **Depth monitoring** - Set alerts at 80% of maximumDepth
3. **Message size** - Set maximumMessageLength based on application needs
4. **Persistence** - Use persistent for critical messages
5. **Documentation** - Always include meaningful descriptions
6. **Backup configs** - Export definitions before major changes

## Related Skills
- `mq-rest-api-basics.skill.md` - REST API fundamentals
- `mq-rdqm-ha-status.skill.md` - RDQM monitoring
- `mq-channel-management.skill.md` - Channel operations
- `mq-security-management.skill.md` - Authority management

## References
- [IBM MQ Queue REST API](https://www.ibm.com/docs/en/ibm-mq/latest?topic=reference-rest-api-queue-resource)
- [Queue attributes](https://www.ibm.com/docs/en/ibm-mq/latest?topic=queues-attributes-local)