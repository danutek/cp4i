# IBM MQ REST API Basics

## Description
This skill provides foundational knowledge for interacting with IBM MQ's administrative REST API. It covers authentication, common endpoints, and basic operations for managing queue managers.

## Prerequisites
- IBM MQ v9.0 or later with REST API enabled
- Queue manager running with mqweb server active
- Valid credentials with appropriate MQ authorities

## Authentication

### Basic Authentication
```bash
# Set credentials
MQ_USER="mqadmin"
MQ_PASS="your_password"
MQ_HOST="localhost"
MQ_PORT="9443"

# Test connection
curl -k -u ${MQ_USER}:${MQ_PASS} \
  https://${MQ_HOST}:${MQ_PORT}/ibmmq/rest/v2/admin/qmgr
```

### Token-Based Authentication (LTPA)
```bash
# 1. Login and capture cookies/headers
curl -k -X POST \
  -H "Content-Type: application/json" \
  -d '{"username":"'${MQ_USER}'","password":"'${MQ_PASS}'"}' \
  -c mq_cookies.txt -D mq_headers.txt \
  https://${MQ_HOST}:${MQ_PORT}/ibmmq/rest/v2/login

# 2. Extract the CSRF token from the saved headers
CSRF_TOKEN=$(grep -i "ibm-mq-rest-csrf-token" mq_headers.txt | cut -d' ' -f2 | tr -d '\r')

# 3. Use the cookie jar and CSRF token in subsequent requests
curl -k -b mq_cookies.txt \
  -H "ibm-mq-rest-csrf-token: ${CSRF_TOKEN}" \
  https://${MQ_HOST}:${MQ_PORT}/ibmmq/rest/v2/admin/qmgr

# Alternative: Extract and use cookies manually
LTPA_TOKEN=$(grep -i "LtpaToken2" mq_cookies.txt | awk '{print $7}')
curl -k \
  -H "ibm-mq-rest-csrf-token: ${CSRF_TOKEN}" \
  -b "LtpaToken2=${LTPA_TOKEN}" \
  https://${MQ_HOST}:${MQ_PORT}/ibmmq/rest/v2/admin/qmgr
```

## Common Endpoints

### Queue Manager Information
```bash
# Get queue manager details
curl -k -u ${MQ_USER}:${MQ_PASS} \
  https://${MQ_HOST}:${MQ_PORT}/ibmmq/rest/v2/admin/qmgr/QM1

# Get queue manager status
curl -k -u ${MQ_USER}:${MQ_PASS} \
  https://${MQ_HOST}:${MQ_PORT}/ibmmq/rest/v2/admin/qmgr/QM1/status
```

### List Objects
```bash
# List all queues
curl -k -u ${MQ_USER}:${MQ_PASS} \
  https://${MQ_HOST}:${MQ_PORT}/ibmmq/rest/v2/admin/qmgr/QM1/queue

# List all channels
curl -k -u ${MQ_USER}:${MQ_PASS} \
  https://${MQ_HOST}:${MQ_PORT}/ibmmq/rest/v2/admin/qmgr/QM1/channel

# List listeners
curl -k -u ${MQ_USER}:${MQ_PASS} \
  https://${MQ_HOST}:${MQ_PORT}/ibmmq/rest/v2/admin/qmgr/QM1/listener
```

### Create a Local Queue (POST)
```bash
# Create a simple local queue
curl -k -X POST -u ${MQ_USER}:${MQ_PASS} \
  -H "ibm-mq-rest-csrf-token: blank" \
  -H "Content-Type: application/json" \
  -d '{"name":"DEV.TEST.LOCAL.QUEUE"}' \
  https://${MQ_HOST}:${MQ_PORT}/ibmmq/rest/v2/admin/qmgr/QM1/queue

# Create a queue with additional attributes
curl -k -X POST -u ${MQ_USER}:${MQ_PASS} \
  -H "ibm-mq-rest-csrf-token: blank" \
  -H "Content-Type: application/json" \
  -d '{
    "name":"DEV.TEST.LOCAL.QUEUE",
    "maximumDepth": 5000,
    "maximumMessageLength": 4194304,
    "defaultPersistence": "persistent"
  }' \
  https://${MQ_HOST}:${MQ_PORT}/ibmmq/rest/v2/admin/qmgr/QM1/queue
```

### Clear a Queue (DELETE)
```bash
# Clear all messages from a queue
curl -k -X DELETE -u ${MQ_USER}:${MQ_PASS} \
  -H "ibm-mq-rest-csrf-token: blank" \
  https://${MQ_HOST}:${MQ_PORT}/ibmmq/rest/v2/admin/qmgr/QM1/queue/DEV.TEST.LOCAL.QUEUE/message

# Delete the queue itself (must be empty and closed)
curl -k -X DELETE -u ${MQ_USER}:${MQ_PASS} \
  -H "ibm-mq-rest-csrf-token: blank" \
  https://${MQ_HOST}:${MQ_PORT}/ibmmq/rest/v2/admin/qmgr/QM1/queue/DEV.TEST.LOCAL.QUEUE
```

**Note:** The `ibm-mq-rest-csrf-token: blank` header is required for POST, PATCH, and DELETE operations when using basic authentication. When using LTPA token authentication, use the actual CSRF token value extracted from the login response headers.

## Response Handling

### Successful Response (200 OK)
```json
{
  "qmgr": [{
    "name": "QM1",
    "status": "running",
    "connectionCount": 5,
    "channelInitiatorStatus": "running"
  }]
}
```

### Error Response (401 Unauthorized)
```json
{
  "error": [{
    "type": "unauthorized",
    "msgId": "MQWB0009E",
    "message": "User is not authorized"
  }]
}
```

## Environment Variables for Consistency

Create a `.env` file or export these variables:
```bash
export MQ_REST_HOST="your-mq-host.example.com"
export MQ_REST_PORT="9443"
export MQ_REST_USER="mqadmin"
export MQ_REST_PASS="secure_password"
export MQ_QMGR_NAME="QM1"
```

## Security Best Practices

1. **Always use HTTPS** - Never send credentials over HTTP
2. **Use TLS certificates** - Validate server certificates in production
3. **Rotate credentials** - Change passwords regularly
4. **Least privilege** - Grant minimum required authorities
5. **Audit logging** - Enable REST API audit logs

## Common HTTP Status Codes

| Code | Meaning | Action |
|------|---------|--------|
| 200 | Success | Process response data |
| 201 | Created | Object created successfully |
| 204 | No Content | Operation successful, no data returned |
| 400 | Bad Request | Check request syntax |
| 401 | Unauthorized | Verify credentials |
| 403 | Forbidden | Check MQ authorities |
| 404 | Not Found | Verify object name and queue manager |
| 500 | Server Error | Check MQ error logs |

## Troubleshooting

### Enable mqweb server
```bash
# Start mqweb server
strmqweb

# Check status
dspmqweb status

# View logs
tail -f /var/mqm/web/installations/Installation1/servers/mqweb/logs/messages.log
```

### Test REST API availability
```bash
# Check if REST API is responding
curl -k https://${MQ_HOST}:${MQ_PORT}/ibmmq/rest/v2/admin/installation

# Expected response includes MQ version information
```

## Integration with MCP Server

An MCP server can use these patterns to:
- Query multiple queue managers simultaneously
- Aggregate status across environments
- Perform batch configuration changes
- Monitor health and performance metrics

## Related Skills
- `mq-queue-management.skill.md` - Queue operations
- `mq-rdqm-ha-status.skill.md` - RDQM HA monitoring
- `mq-channel-management.skill.md` - Channel operations

## References
- [IBM MQ REST API Documentation](https://www.ibm.com/docs/en/ibm-mq/latest?topic=api-rest-administration)
- [mqweb server configuration](https://www.ibm.com/docs/en/ibm-mq/latest?topic=console-configuring-mqweb-server)