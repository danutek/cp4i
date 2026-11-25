# Development Guide: Extending the IBM MQ MCP Server

This guide provides the tactical steps and best practices for adding new IBM MQ capabilities to the FastMCP server. 

## The Workflow

Before writing any Python code, follow this development lifecycle:

1. **Document the Blueprint:** If you are adding a new feature (e.g., Topic Management), first write the raw `curl` commands and JSON payloads in a `skill.md` file located in `skills/`. Prove the REST API calls work against a real queue manager.
2. **Write the Tool:** Wrap those proven REST API calls into a new Python function using the `@mcp.tool()` decorator.
3. **Test Manually:** Test the tool directly in Python before exposing it to an LLM.
4. **Test with LLM:** Use the MCP Inspector or Claude Desktop to test the tool with natural language.
5. **Document:** Update README.md with the new tool's capabilities.

## Anatomy of an MCP Tool

Every tool in this repository must follow a strict anatomical structure. The LLM relies entirely on your Python docstrings and type hints to understand how to use the tool.

### The Template

```python
@mcp.tool()
async def action_target_name(
    qmgr_name: str, 
    required_param: str, 
    optional_param: int = 50
) -> str:
    """
    Clear, single-sentence description of what this tool does.
    Add a second sentence noting any idempotency or side-effects.
    
    Args:
        qmgr_name: The name of the queue manager (e.g., 'QM1').
        required_param: Explicitly state what this is and format expectations.
        optional_param: State the default value and what it controls (defaults to 50).
        
    Returns:
        JSON string containing the data, or a plain text success/error message.
    """
    # 1. Idempotency Check (if modifying state)
    if await check_queue_exists(qmgr_name, queue_name):
        return f"Notice: Already exists."
    
    # 2. Build URL and Payload
    config = get_mq_config()
    url = f"{get_base_url(config['host'], config['port'])}/qmgr/{qmgr_name}/..."
    payload = {"key": "value"}
    
    # 3. Execute Async HTTP Request
    try:
        async with httpx.AsyncClient(verify=False) as client:
            response = await client.post(
                url,
                auth=(config["user"], config["pass"]),
                headers=get_headers(),
                json=payload
            )
            
            # 4. Handle Response
            if response.status_code == 201:
                return f"Success: Operation completed."
            else:
                return await handle_mq_response(response, [201])
                
    except Exception as e:
        return f"Failed to connect to MQ REST API: {str(e)}"
```

### Naming Conventions

Tool names should follow the pattern: `verb_noun_modifier`

**Good Examples:**
- `create_local_queue` - Clear action and target
- `get_queue_status` - Obvious what it retrieves
- `set_queue_inhibit_state` - Specific about what it modifies
- `monitor_queue_depths` - Indicates ongoing observation

**Bad Examples:**
- `queue` - Too vague
- `do_queue_stuff` - Not descriptive
- `queueCreate` - Wrong case convention
- `create_queue_local` - Modifier in wrong position

### Parameter Ordering

Always order parameters from most to least important:

1. **Queue Manager Name** - Almost always first
2. **Primary Target** - The object being acted upon (queue name, channel name)
3. **Required Configuration** - Essential parameters
4. **Optional Configuration** - Parameters with defaults
5. **Metadata** - Descriptions, tags, etc.

**Example:**
```python
async def create_remote_queue(
    qmgr_name: str,              # 1. Queue manager
    queue_name: str,              # 2. Primary target
    remote_queue_name: str,       # 3. Required config
    remote_qmgr_name: str,        # 3. Required config
    transmission_queue: str,      # 3. Required config
    desc: str = "Created via MCP" # 5. Metadata
) -> str:
```

## Returning Data to the LLM

The return type of every tool should strictly be a `str`. How you format that string dictates how well the LLM performs.

### For Data Retrieval (GET)

Always return a nicely formatted JSON string. The LLM can parse JSON effortlessly to extract exact values or summarize the data for the user.

```python
# Good: Return formatted JSON
result = {
    "queueManager": qmgr_name,
    "queues": queue_list,
    "count": len(queue_list)
}
return json.dumps(result, indent=2)

# Bad: Return raw response text
return response.text

# Bad: Return Python dict (not serializable)
return {"data": queue_list}
```

### For State Changes (POST, PATCH, DELETE)

Return a clear, human-readable plain text string starting with a status keyword.

```python
# Good: Clear status with context
return "Success: Queue APP.TEST created on QM1."
return "Notice: Queue APP.TEST already exists on QM1."
return "Error 403: User mqadmin lacks +crt authority."

# Bad: Vague or inconsistent
return "Done"
return "Queue created"
return "Failed"
```

### Status Keywords

Use these standard prefixes:

- **Success:** - Operation completed as intended
- **Notice:** - Operation was idempotent (already in desired state)
- **Error XXX:** - Operation failed with HTTP status code
- **Warning:** - Operation succeeded but with caveats

## Building Compound Tools

Do not force the LLM to make 10 sequential REST calls if the logic can be handled in Python. Building "Compound Tools" saves LLM token costs, reduces latency, and prevents AI logic loops.

### When to Build a Compound Tool

Build a compound tool when:
1. A common workflow requires 3+ sequential tool calls
2. The workflow has conditional logic based on intermediate results
3. The workflow requires aggregation or analysis of multiple responses
4. The workflow is a frequent user request

### Example: Queue Health Diagnosis

Instead of requiring the LLM to:
1. Call `get_queue_status` to check depth
2. Call `get_queue_details` to check max depth
3. Call `get_channel_status` to check if consumers are connected
4. Perform calculations and comparisons

Build a single tool:

```python
@mcp.tool()
async def diagnose_queue_health(
    qmgr_name: str,
    queue_name: str,
    depth_threshold: int = 80
) -> str:
    """
    Performs comprehensive health check on a queue including depth analysis,
    consumer status, and channel connectivity.
    
    Args:
        qmgr_name: The name of the queue manager.
        queue_name: The name of the queue to diagnose.
        depth_threshold: Alert threshold as percentage of max depth (default 80%).
        
    Returns:
        JSON string containing health status, issues found, and recommendations.
    """
    config = get_mq_config()
    base_url = get_base_url(config['host'], config['port'])
    
    health_report = {
        "queue": queue_name,
        "queueManager": qmgr_name,
        "status": "healthy",
        "issues": [],
        "recommendations": []
    }
    
    try:
        async with httpx.AsyncClient(verify=False) as client:
            # Get queue status
            status_response = await client.get(
                f"{base_url}/qmgr/{qmgr_name}/queue/{queue_name}?status=*",
                auth=(config["user"], config["pass"]),
                headers=get_headers()
            )
            
            if status_response.status_code == 200:
                queue_data = status_response.json()["queue"][0]
                current_depth = queue_data["status"]["currentDepth"]
                max_depth = queue_data["maximumDepth"]
                open_input = queue_data["status"]["openInputCount"]
                open_output = queue_data["status"]["openOutputCount"]
                
                # Analyze depth
                depth_percent = (current_depth / max_depth * 100) if max_depth > 0 else 0
                health_report["depthPercent"] = round(depth_percent, 2)
                
                if depth_percent >= depth_threshold:
                    health_report["status"] = "warning"
                    health_report["issues"].append(
                        f"Queue is {depth_percent:.1f}% full ({current_depth}/{max_depth})"
                    )
                    health_report["recommendations"].append(
                        "Consider increasing max depth or investigating slow consumers"
                    )
                
                # Analyze consumers
                if current_depth > 0 and open_output == 0:
                    health_report["status"] = "critical"
                    health_report["issues"].append(
                        f"Queue has {current_depth} messages but no active consumers"
                    )
                    health_report["recommendations"].append(
                        "Check if consumer applications are running and connected"
                    )
                
                health_report["openInputCount"] = open_input
                health_report["openOutputCount"] = open_output
            
            return json.dumps(health_report, indent=2)
            
    except Exception as e:
        return f"Failed to diagnose queue health: {str(e)}"
```

## Implementing Idempotency

Idempotency is critical for AI-driven operations. The LLM may retry operations, and we must ensure safe behavior.

### Pattern 1: Pre-Check with Helper Function

```python
@mcp.tool()
async def create_local_queue(qmgr_name: str, queue_name: str, ...) -> str:
    """Creates a new local queue (idempotent)."""
    
    # Check if queue already exists
    if await check_queue_exists(qmgr_name, queue_name):
        return f"Notice: Queue {queue_name} already exists on {qmgr_name}."
    
    # Proceed with creation...
```

### Pattern 2: Error Code Detection

```python
@mcp.tool()
async def create_local_queue(qmgr_name: str, queue_name: str, ...) -> str:
    """Creates a new local queue (idempotent)."""
    
    try:
        async with httpx.AsyncClient(verify=False) as client:
            response = await client.post(...)
            
            if response.status_code == 201:
                return f"Success: Queue created."
            elif response.status_code == 400 and "MQRC_Q_ALREADY_EXISTS" in response.text:
                return f"Notice: Queue already exists."
            else:
                return await handle_mq_response(response, [201])
    except Exception as e:
        return f"Failed: {str(e)}"
```

### Pattern 3: GET-then-PATCH for Updates

```python
@mcp.tool()
async def update_queue_attributes(qmgr_name: str, queue_name: str, ...) -> str:
    """Updates queue attributes (idempotent)."""
    
    # First, verify the queue exists
    existing = await get_queue_details(qmgr_name, queue_name)
    if "Error" in existing:
        return f"Error: Queue {queue_name} does not exist on {qmgr_name}."
    
    # Proceed with update...
```

## Error Handling Best Practices

### Always Use Try-Except

```python
try:
    async with httpx.AsyncClient(verify=False) as client:
        response = await client.get(...)
        return await handle_mq_response(response)
except httpx.ConnectError as e:
    return f"Failed to connect to MQ REST API at {url}: {str(e)}"
except httpx.TimeoutException as e:
    return f"Request timed out: {str(e)}"
except Exception as e:
    return f"Unexpected error: {str(e)}"
```

### Provide Context in Error Messages

```python
# Bad: Generic error
return f"Error: {str(e)}"

# Good: Contextual error
return f"Failed to create queue {queue_name} on {qmgr_name}: {str(e)}"
```

### Use the Helper Function

```python
# Instead of manual response handling
if response.status_code == 200:
    return response.text
else:
    return f"Error {response.status_code}: {response.text}"

# Use the helper
return await handle_mq_response(response)
```

## Testing Your Tools

### Unit Testing

Create a test file `test_mq_mcp_server.py`:

```python
import pytest
import asyncio
from mq_mcp_server import create_local_queue, list_queues

@pytest.mark.asyncio
async def test_create_local_queue():
    """Test queue creation with valid parameters."""
    result = await create_local_queue(
        qmgr_name="QM1",
        queue_name="TEST.QUEUE",
        max_depth=5000
    )
    assert "Success" in result or "Notice" in result

@pytest.mark.asyncio
async def test_list_queues():
    """Test listing queues with pattern."""
    result = await list_queues(
        qmgr_name="QM1",
        queue_pattern="TEST.*"
    )
    assert "queue" in result.lower()
```

### Manual Testing

```python
# Test directly in Python
import asyncio
from mq_mcp_server import create_local_queue

async def test():
    result = await create_local_queue("QM1", "TEST.QUEUE")
    print(result)

asyncio.run(test())
```

### Integration Testing with MCP Inspector

```bash
# Install MCP Inspector
npm install -g @modelcontextprotocol/inspector

# Run your server with inspector
mcp-inspector python mq_mcp_server.py
```

## Common Pitfalls and Solutions

### Pitfall 1: Forgetting Async/Await

```python
# Wrong: Missing async/await
@mcp.tool()
def create_queue(qmgr_name: str) -> str:
    client = httpx.AsyncClient()
    response = client.post(...)  # This won't work!

# Correct: Proper async/await
@mcp.tool()
async def create_queue(qmgr_name: str) -> str:
    async with httpx.AsyncClient() as client:
        response = await client.post(...)
```

### Pitfall 2: Not Closing HTTP Clients

```python
# Wrong: Client not closed
client = httpx.AsyncClient()
response = await client.get(...)
return response.text

# Correct: Use context manager
async with httpx.AsyncClient() as client:
    response = await client.get(...)
    return response.text
```

### Pitfall 3: Vague Docstrings

```python
# Wrong: Vague and unhelpful
"""Creates a queue."""

# Correct: Detailed and specific
"""
Creates a new Local Queue on the specified IBM MQ Queue Manager.
This operation is idempotent - if the queue already exists, it returns a notice.

Args:
    qmgr_name: The name of the queue manager (e.g., 'QM1').
    queue_name: The name of the new queue to create.
    max_depth: Maximum message depth (defaults to 5000).
"""
```

### Pitfall 4: Returning Wrong Types

```python
# Wrong: Returning dict instead of string
return {"status": "success"}

# Correct: Return JSON string
return json.dumps({"status": "success"}, indent=2)
```

### Pitfall 5: Not Handling Idempotency

```python
# Wrong: Fails on duplicate
response = await client.post(...)
if response.status_code != 201:
    return f"Error: {response.text}"

# Correct: Handles duplicate gracefully
if response.status_code == 201:
    return "Success: Queue created."
elif response.status_code == 400 and "ALREADY_EXISTS" in response.text:
    return "Notice: Queue already exists."
else:
    return f"Error {response.status_code}: {response.text}"
```

## Adding a New Tool: Step-by-Step Example

Let's add a tool to manage MQ topics.

### Step 1: Document the REST API

Create `skills/mq-topic-management.skill.md`:

```markdown
# IBM MQ Topic Management

## Create Topic

```bash
curl -k -X POST -u ${MQ_USER}:${MQ_PASS} \
  -H "ibm-mq-rest-csrf-token: blank" \
  -H "Content-Type: application/json" \
  -d '{
    "name": "APP/EVENTS/ORDER",
    "topicString": "APP/EVENTS/ORDER"
  }' \
  https://${MQ_HOST}:${MQ_PORT}/ibmmq/rest/v2/admin/qmgr/QM1/topic
```

Test this against your queue manager first!
```

### Step 2: Write the Tool

Add to `mq_mcp_server.py`:

```python
@mcp.tool()
async def create_topic(
    qmgr_name: str,
    topic_name: str,
    topic_string: str,
    desc: str = "Created via MCP"
) -> str:
    """
    Creates a new Topic on the specified IBM MQ Queue Manager.
    Topics are used for publish/subscribe messaging patterns.
    
    Args:
        qmgr_name: The name of the queue manager (e.g., 'QM1').
        topic_name: The administrative name of the topic.
        topic_string: The topic string used for publishing/subscribing.
        desc: Description of the topic's purpose.
        
    Returns:
        Success message, notice if topic exists, or error message.
    """
    config = get_mq_config()
    url = f"{get_base_url(config['host'], config['port'])}/qmgr/{qmgr_name}/topic"
    
    payload = {
        "name": topic_name,
        "topicString": topic_string,
        "description": desc
    }

    try:
        async with httpx.AsyncClient(verify=False) as client:
            response = await client.post(
                url,
                auth=(config["user"], config["pass"]),
                headers=get_headers(),
                json=payload
            )
            
            if response.status_code == 201:
                return f"Success: Topic {topic_name} created on {qmgr_name}."
            elif response.status_code == 400 and "ALREADY_EXISTS" in response.text:
                return f"Notice: Topic {topic_name} already exists on {qmgr_name}."
            else:
                return await handle_mq_response(response, [201])
                
    except Exception as e:
        return f"Failed to connect to MQ REST API: {str(e)}"
```

### Step 3: Test Manually

```python
import asyncio
from mq_mcp_server import create_topic

async def test():
    result = await create_topic(
        qmgr_name="QM1",
        topic_name="APP.EVENTS.ORDER",
        topic_string="APP/EVENTS/ORDER",
        desc="Order events topic"
    )
    print(result)

asyncio.run(test())
```

### Step 4: Update Documentation

Add to `README.md`:

```markdown
#### `create_topic`
Creates a new topic for publish/subscribe messaging.

**Parameters:**
- `qmgr_name` (required): Queue manager name
- `topic_name` (required): Administrative topic name
- `topic_string` (required): Topic string for pub/sub
- `desc` (optional): Topic description

**Example:**
```
Create a topic named APP.EVENTS.ORDER for order events on QM1
```
```

### Step 5: Test with LLM

Use Claude Desktop or MCP Inspector:
```
"Create a topic named APP.EVENTS.ORDER on QM1 for publishing order events"
```

## Code Review Checklist

Before submitting a pull request, verify:

- [ ] Tool has `@mcp.tool()` decorator
- [ ] Function is `async` and uses `await`
- [ ] All parameters have type hints
- [ ] Docstring includes clear description
- [ ] Docstring has complete `Args:` section
- [ ] Docstring has `Returns:` section
- [ ] Idempotency is handled for state changes
- [ ] HTTP client uses context manager (`async with`)
- [ ] Errors are caught and returned as strings
- [ ] Success/Notice/Error messages are clear
- [ ] Tool is tested manually
- [ ] README.md is updated
- [ ] Skill file exists (if new feature area)

## Performance Optimization Tips

### Use Connection Pooling (Future)

When implementing connection pooling:

```python
# Initialize once at module level
_http_client: Optional[httpx.AsyncClient] = None

async def get_http_client() -> httpx.AsyncClient:
    global _http_client
    if _http_client is None:
        _http_client = httpx.AsyncClient(
            verify=False,
            timeout=30.0,
            limits=httpx.Limits(max_connections=10)
        )
    return _http_client
```

### Batch Operations

When querying multiple objects, do it in one REST call:

```python
# Good: Single call with pattern
response = await client.get(f"{url}/queue?name=APP.*")

# Bad: Multiple calls
for queue in queue_list:
    response = await client.get(f"{url}/queue/{queue}")
```

### Parallel Queries

Use `asyncio.gather` for independent queries:

```python
async def get_multiple_qm_status(qmgr_list: List[str]) -> str:
    async with httpx.AsyncClient(verify=False) as client:
        tasks = [
            client.get(f"{base_url}/qmgr/{qm}/status", ...)
            for qm in qmgr_list
        ]
        responses = await asyncio.gather(*tasks, return_exceptions=True)
    # Process responses...
```

## Debugging Tips

### Enable Verbose Logging

```python
import logging
logging.basicConfig(level=logging.DEBUG)
```

### Print Request Details

```python
print(f"URL: {url}")
print(f"Payload: {json.dumps(payload, indent=2)}")
print(f"Response: {response.status_code} - {response.text}")
```

### Use MCP Inspector

The MCP Inspector shows exactly what the LLM sees:
- Tool descriptions
- Parameter types
- Response formats

### Test REST API Directly

Always verify the REST API works with `curl` before implementing:

```bash
curl -k -u mqadmin:password \
  https://localhost:9443/ibmmq/rest/v2/admin/qmgr/QM1/queue
```

## Resources

- [FastMCP Documentation](https://github.com/jlowin/fastmcp)
- [IBM MQ REST API Reference](https://www.ibm.com/docs/en/ibm-mq/latest?topic=api-rest-administration)
- [httpx Documentation](https://www.python-httpx.org/)
- [Python Type Hints](https://docs.python.org/3/library/typing.html)
- [MCP Protocol Specification](https://modelcontextprotocol.io/)

## Getting Help

If you encounter issues:

1. Check the skill files for working REST API examples
2. Test the REST API directly with `curl`
3. Review existing tools for patterns
4. Check the ARCHITECTURE.md for design principles
5. Open an issue with detailed error messages and context

## Contributing

We welcome contributions! Please:

1. Follow the patterns established in existing tools
2. Write comprehensive docstrings
3. Test thoroughly before submitting
4. Update documentation
5. Follow the code review checklist

Happy coding! 🚀