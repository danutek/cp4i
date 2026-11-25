# IBM MQ MCP Server

A comprehensive Model Context Protocol (MCP) server that provides intent-based integration with IBM MQ, enabling LLMs to automatically provision, configure, and monitor IBM MQ estates using the IBM MQ REST API.

## Overview

This MCP server acts as an intelligent bridge between Large Language Models and IBM MQ infrastructure, allowing natural language commands to be translated into precise MQ REST API operations. Built using the FastMCP framework, it provides 30+ tools covering queue management, RDQM high availability monitoring, channel operations, and estate-wide health checks.

## Features

### Queue Management
- **Create Queues**: Local, remote, alias, and model queues with full attribute control
- **Modify Queues**: Update attributes, set inhibit states, manage queue properties
- **Monitor Queues**: Real-time depth monitoring, status checks, threshold alerting
- **Delete Queues**: Safe deletion with optional message purging
- **Batch Operations**: Export definitions, compare configurations across queue managers

### RDQM High Availability
- **HA Status Monitoring**: Track primary/secondary roles, failover detection
- **Estate-Wide Visibility**: Monitor all queue managers across the infrastructure
- **Health Checks**: Automated monitoring with threshold-based alerting

### Channel & Listener Management
- **Channel Operations**: List, monitor, and manage MQ channels
- **Listener Management**: View and configure network listeners

### Advanced Features
- **Idempotent Operations**: Safe to retry without side effects
- **Error Handling**: Comprehensive error detection and reporting
- **Configuration Comparison**: Detect drift between environments
- **Bulk Monitoring**: Track multiple queues simultaneously

## Installation

### Prerequisites
- Python 3.8 or later
- IBM MQ v9.0 or later with REST API enabled
- Valid MQ credentials with appropriate authorities

### Install Dependencies

```bash
pip install mcp httpx
```

Or using the FastMCP framework:

```bash
pip install fastmcp httpx
```

## Configuration

Set the following environment variables to configure the MQ connection:

```bash
export MQ_REST_HOST="your-mq-host.example.com"
export MQ_REST_PORT="9443"
export MQ_REST_USER="mqadmin"
export MQ_REST_PASS="your_secure_password"
```

### Using a .env File

Create a `.env` file in the project directory:

```env
MQ_REST_HOST=your-mq-host.example.com
MQ_REST_PORT=9443
MQ_REST_USER=mqadmin
MQ_REST_PASS=your_secure_password
```

## Running the Server

### Standard Mode

```bash
python mq_mcp_server.py
```

### With MCP Client

The server communicates via standard input/output, which is the MCP protocol standard:

```bash
# Example with Claude Desktop or other MCP clients
# Add to your MCP client configuration
```

### MCP Client Configuration

Add to your MCP client's configuration file (e.g., Claude Desktop):

```json
{
  "mcpServers": {
    "ibm-mq": {
      "command": "python",
      "args": ["/path/to/mq_mcp_server.py"],
      "env": {
        "MQ_REST_HOST": "your-mq-host.example.com",
        "MQ_REST_PORT": "9443",
        "MQ_REST_USER": "mqadmin",
        "MQ_REST_PASS": "your_secure_password"
      }
    }
  }
}
```

## Available Tools

### Queue Listing & Information

#### `list_queues`
Lists queues on a queue manager with optional filtering.

**Parameters:**
- `qmgr_name` (required): Queue manager name
- `queue_pattern` (optional): Wildcard pattern (e.g., 'APP.*')
- `queue_type` (optional): Filter by type ('local', 'alias', 'remote', 'model')

**Example:**
```
List all application queues on QM1 matching APP.*
```

#### `get_queue_details`
Retrieves detailed configuration for a specific queue.

**Parameters:**
- `qmgr_name` (required): Queue manager name
- `queue_name` (required): Queue name
- `attributes` (optional): Comma-separated attribute list

**Example:**
```
Get details for queue APP.REQUEST.QUEUE on QM1
```

#### `get_queue_status`
Retrieves runtime status including depth and open handles.

**Parameters:**
- `qmgr_name` (required): Queue manager name
- `queue_name` (required): Queue name
- `status_attributes` (optional): Specific status attributes or '*' for all

**Example:**
```
Check the current depth and open handles for APP.REQUEST.QUEUE on QM1
```

### Queue Creation

#### `create_local_queue`
Creates a new local queue (idempotent).

**Parameters:**
- `qmgr_name` (required): Queue manager name
- `queue_name` (required): New queue name
- `max_depth` (optional): Maximum depth (default: 5000)
- `max_message_length` (optional): Max message size in bytes (default: 4194304)
- `default_persistence` (optional): 'persistent' or 'nonPersistent' (default: 'persistent')
- `desc` (optional): Queue description

**Example:**
```
Create a local queue named APP.NEW.QUEUE on QM1 with max depth 10000
```

#### `create_remote_queue`
Creates a remote queue definition (idempotent).

**Parameters:**
- `qmgr_name` (required): Local queue manager name
- `queue_name` (required): Remote queue definition name
- `remote_queue_name` (required): Target queue name on remote QM
- `remote_qmgr_name` (required): Remote queue manager name
- `transmission_queue` (required): Transmission queue for routing
- `desc` (optional): Description

**Example:**
```
Create a remote queue definition REMOTE.APP.QUEUE pointing to TARGET.QUEUE on QM2 using QM2.XMIT
```

#### `create_alias_queue`
Creates an alias queue (idempotent).

**Parameters:**
- `qmgr_name` (required): Queue manager name
- `queue_name` (required): Alias queue name
- `target_name` (required): Target queue or topic name
- `target_type` (optional): 'queue' or 'topic' (default: 'queue')
- `desc` (optional): Description

**Example:**
```
Create an alias queue ALIAS.APP pointing to APP.REQUEST.QUEUE on QM1
```

#### `create_model_queue`
Creates a model queue for dynamic queue templates (idempotent).

**Parameters:**
- `qmgr_name` (required): Queue manager name
- `queue_name` (required): Model queue name
- `defines_type` (optional): 'temporary' or 'permanent' (default: 'temporary')
- `max_depth` (optional): Max depth (default: 1000)
- `default_persistence` (optional): Persistence setting
- `desc` (optional): Description

**Example:**
```
Create a model queue MODEL.TEMP for temporary dynamic queues on QM1
```

### Queue Modification

#### `update_queue_attributes`
Updates queue attributes using PATCH operation.

**Parameters:**
- `qmgr_name` (required): Queue manager name
- `queue_name` (required): Queue name
- `max_depth` (optional): New maximum depth
- `max_message_length` (optional): New max message size
- `desc` (optional): New description

**Example:**
```
Update APP.REQUEST.QUEUE on QM1 to have max depth 15000
```

#### `set_queue_inhibit_state`
Controls GET and PUT operations on a queue.

**Parameters:**
- `qmgr_name` (required): Queue manager name
- `queue_name` (required): Queue name
- `inhibit_get` (optional): 'allowed' or 'inhibited'
- `inhibit_put` (optional): 'allowed' or 'inhibited'

**Example:**
```
Inhibit PUT operations on APP.REQUEST.QUEUE on QM1
```

### Queue Deletion & Clearing

#### `clear_queue_messages`
Removes all messages from a queue without deleting it.

**Parameters:**
- `qmgr_name` (required): Queue manager name
- `queue_name` (required): Queue name

**Example:**
```
Clear all messages from APP.REQUEST.QUEUE on QM1
```

#### `delete_queue`
Deletes a queue from the queue manager.

**Parameters:**
- `qmgr_name` (required): Queue manager name
- `queue_name` (required): Queue name
- `purge` (optional): If true, purges messages before deleting (default: false)

**Example:**
```
Delete queue APP.OLD.QUEUE on QM1 with purge
```

### Queue Manager Status

#### `get_qmgr_status`
Retrieves queue manager status and configuration.

**Parameters:**
- `qmgr_name` (required): Queue manager name

**Example:**
```
Get status of queue manager QM1
```

#### `list_queue_managers`
Lists all accessible queue managers.

**Parameters:**
- `status_filter` (optional): 'running', 'stopped', or '*' for all

**Example:**
```
List all running queue managers
```

### RDQM High Availability

#### `get_qmgr_ha_status`
Retrieves HA status for an RDQM queue manager.

**Parameters:**
- `qmgr_name` (required): RDQM queue manager name

**Returns:**
- haRole: primary, secondary, or unknown
- haStatus: normal, error, or other states
- haCurrentLocation: Current node
- haPreferredLocation: Preferred node

**Example:**
```
Get HA status for RDQM queue manager QM1
```

#### `get_estate_qmgr_status`
Retrieves status for all queue managers in the estate.

**Example:**
```
Show me the status of all queue managers including HA information
```

### Monitoring & Alerting

#### `monitor_queue_depths`
Monitors queue depths and identifies those exceeding thresholds.

**Parameters:**
- `qmgr_name` (required): Queue manager name
- `queue_pattern` (optional): Wildcard pattern (default: 'APP.*')
- `threshold_percent` (optional): Alert threshold percentage (default: 80)

**Example:**
```
Monitor all APP.* queues on QM1 and alert if any exceed 80% capacity
```

### Channel Management

#### `list_channels`
Lists channels on a queue manager.

**Parameters:**
- `qmgr_name` (required): Queue manager name
- `channel_pattern` (optional): Wildcard pattern
- `channel_type` (optional): Channel type filter

**Example:**
```
List all sender channels on QM1
```

#### `get_channel_status`
Retrieves runtime status of a channel.

**Parameters:**
- `qmgr_name` (required): Queue manager name
- `channel_name` (required): Channel name

**Example:**
```
Get status of channel TO.QM2 on QM1
```

### Listener Management

#### `list_listeners`
Lists all listeners on a queue manager.

**Parameters:**
- `qmgr_name` (required): Queue manager name

**Example:**
```
List all listeners on QM1
```

### Batch Operations

#### `compare_queue_configs`
Compares queue configuration across two queue managers.

**Parameters:**
- `qmgr1_name` (required): First queue manager name
- `qmgr2_name` (required): Second queue manager name
- `queue_name` (required): Queue name to compare

**Example:**
```
Compare configuration of APP.REQUEST.QUEUE between QM1 and QM2
```

#### `export_queue_definitions`
Exports queue definitions to JSON format.

**Parameters:**
- `qmgr_name` (required): Queue manager name
- `queue_pattern` (optional): Wildcard pattern (default: '*')

**Example:**
```
Export all APP.* queue definitions from QM1
```

## Usage Examples

### Natural Language Commands

The MCP server enables natural language interaction with IBM MQ:

```
"Create a local queue named ORDERS.PROCESSING on QM1 with max depth 10000"

"Show me all queues starting with APP on QM1"

"What's the current depth of ORDERS.PROCESSING?"

"Inhibit PUT operations on ORDERS.PROCESSING for maintenance"

"Compare the configuration of ORDERS.PROCESSING between QM1 and QM2"

"Monitor all application queues and alert if any are over 80% full"

"Get the HA status of all RDQM queue managers"

"Export all queue definitions from QM1 for backup"
```

### Programmatic Usage

```python
import asyncio
from mq_mcp_server import create_local_queue, get_queue_status

async def main():
    # Create a queue
    result = await create_local_queue(
        qmgr_name="QM1",
        queue_name="TEST.QUEUE",
        max_depth=5000,
        desc="Test queue"
    )
    print(result)
    
    # Check its status
    status = await get_queue_status(
        qmgr_name="QM1",
        queue_name="TEST.QUEUE"
    )
    print(status)

asyncio.run(main())
```

## Security Considerations

### TLS/SSL Configuration

The current implementation uses `verify=False` for SSL verification (mimics `curl -k`). For production:

1. **Use proper CA certificates:**
```python
async with httpx.AsyncClient(verify="/path/to/ca-bundle.crt") as client:
    # ... requests
```

2. **Enable certificate validation:**
```python
# Remove verify=False from all httpx.AsyncClient() calls
async with httpx.AsyncClient() as client:
    # ... requests
```

### Credential Management

- Never hardcode credentials in the script
- Use environment variables or secure credential stores
- Rotate passwords regularly
- Use least-privilege MQ authorities

### MQ Authorities Required

The MQ user needs the following minimum authorities:

- **Queue operations**: +chg, +dsp, +crt, +dlt
- **Queue manager operations**: +dsp, +connect
- **Channel operations**: +dsp (for monitoring)

## Error Handling

The server implements comprehensive error handling:

- **Idempotent operations**: Safe to retry without side effects
- **Graceful degradation**: Returns informative error messages
- **MQ error code detection**: Recognizes common MQ errors (e.g., MQRC_Q_ALREADY_EXISTS)
- **Connection failures**: Clear error messages for network issues

## Troubleshooting

### Connection Issues

```bash
# Test REST API connectivity
curl -k -u ${MQ_REST_USER}:${MQ_REST_PASS} \
  https://${MQ_REST_HOST}:${MQ_REST_PORT}/ibmmq/rest/v2/admin/qmgr
```

### Enable mqweb Server

```bash
# Start mqweb server
strmqweb

# Check status
dspmqweb status

# View logs
tail -f /var/mqm/web/installations/Installation1/servers/mqweb/logs/messages.log
```

### Common Errors

| Error | Cause | Solution |
|-------|-------|----------|
| Connection refused | mqweb not running | Start mqweb server |
| 401 Unauthorized | Invalid credentials | Check MQ_REST_USER and MQ_REST_PASS |
| 403 Forbidden | Insufficient authorities | Grant required MQ authorities |
| MQRC_Q_ALREADY_EXISTS | Queue exists | Normal for idempotent operations |

## Architecture

### Component Overview

```
┌─────────────────┐
│   LLM Client    │
│  (Claude, etc)  │
└────────┬────────┘
         │ MCP Protocol (stdio)
         │
┌────────▼────────┐
│   FastMCP       │
│   Framework     │
└────────┬────────┘
         │
┌────────▼────────┐
│  MQ MCP Server  │
│  (30+ tools)    │
└────────┬────────┘
         │ HTTPS/REST
         │
┌────────▼────────┐
│  IBM MQ REST    │
│      API        │
└────────┬────────┘
         │
┌────────▼────────┐
│  IBM MQ Queue   │
│    Managers     │
└─────────────────┘
```

### Design Principles

1. **Idempotency**: Operations can be safely retried
2. **Type Safety**: Full Python type hints for all functions
3. **Documentation**: Comprehensive docstrings for LLM understanding
4. **Error Handling**: Graceful degradation with informative messages
5. **Modularity**: Each tool is independent and focused

## Development

### Adding New Tools

To add a new MCP tool:

1. Define the function with `@mcp.tool()` decorator
2. Add comprehensive docstring with Args section
3. Include full type hints
4. Implement error handling
5. Consider idempotency
6. Test with various inputs

Example:

```python
@mcp.tool()
async def my_new_tool(qmgr_name: str, param: str) -> str:
    """
    Brief description of what the tool does.
    
    Args:
        qmgr_name: The name of the queue manager.
        param: Description of parameter.
        
    Returns:
        Description of return value.
    """
    # Implementation
    pass
```

### Testing

```bash
# Run the server in test mode
python mq_mcp_server.py

# Test individual functions
python -c "
import asyncio
from mq_mcp_server import list_queues
print(asyncio.run(list_queues('QM1')))
"
```

## Related Documentation

- [IBM MQ REST API Documentation](https://www.ibm.com/docs/en/ibm-mq/latest?topic=api-rest-administration)
- [FastMCP Framework](https://github.com/jlowin/fastmcp)
- [Model Context Protocol](https://modelcontextprotocol.io/)
- [RDQM High Availability](https://www.ibm.com/docs/en/ibm-mq/latest?topic=multiplatforms-rdqm-high-availability)

## Skills Reference

This MCP server implements operations documented in:

- `skills/mq-rest-api-basics.skill.md` - REST API fundamentals
- `skills/mq-queue-management.skill.md` - Queue operations
- `skills/mq-rdqm-ha-status.skill.md` - RDQM HA monitoring

## License

[Specify your license here]

## Contributing

Contributions are welcome! Please ensure:

- All new tools have comprehensive docstrings
- Type hints are included for all parameters
- Error handling is implemented
- Idempotency is considered
- Documentation is updated

## Support

For issues or questions:
- Check the troubleshooting section
- Review IBM MQ documentation
- Consult the skill files in the `skills/` directory

## Version History

- **v1.0.0** - Initial release with 30+ tools covering queue management, RDQM HA, channels, and batch operations