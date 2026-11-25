import os
import httpx
from typing import Optional, Dict, Any, List
from mcp.server.fastmcp import FastMCP
import warnings
import json

# Suppress insecure request warnings for the prototype (mimics curl -k)
# In production, you would point verify to your CA bundle.
warnings.filterwarnings("ignore")

# Initialize the MCP Server
mcp = FastMCP("IBM MQ Manager")

def get_mq_config() -> Dict[str, str]:
    """Helper to fetch MQ connection details from environment variables."""
    return {
        "host": os.getenv("MQ_REST_HOST", "localhost"),
        "port": os.getenv("MQ_REST_PORT", "9443"),
        "user": os.getenv("MQ_REST_USER", "mqadmin"),
        "pass": os.getenv("MQ_REST_PASS", "password"),
    }

def get_base_url(host: str, port: str) -> str:
    """Constructs the base URL for the MQ REST API."""
    return f"https://{host}:{port}/ibmmq/rest/v2/admin"

def get_headers() -> Dict[str, str]:
    """Returns required headers, including the blank CSRF token for Basic Auth."""
    return {
        "Accept": "application/json",
        "Content-Type": "application/json",
        "ibm-mq-rest-csrf-token": "blank"
    }

async def handle_mq_response(response: httpx.Response, success_codes: List[int] = [200, 201, 204]) -> str:
    """
    Helper function to handle MQ REST API responses consistently.
    
    Args:
        response: The httpx Response object
        success_codes: List of HTTP status codes considered successful
        
    Returns:
        String representation of the response or error message
    """
    if response.status_code in success_codes:
        if response.text:
            return response.text
        return f"Success: Operation completed with status {response.status_code}"
    else:
        return f"Error {response.status_code}: {response.text}"

async def check_queue_exists(qmgr_name: str, queue_name: str) -> bool:
    """
    Helper function to check if a queue exists.
    
    Args:
        qmgr_name: The name of the queue manager
        queue_name: The name of the queue to check
        
    Returns:
        True if queue exists, False otherwise
    """
    config = get_mq_config()
    url = f"{get_base_url(config['host'], config['port'])}/qmgr/{qmgr_name}/queue/{queue_name}"
    
    try:
        async with httpx.AsyncClient(verify=False) as client:
            response = await client.get(
                url,
                auth=(config["user"], config["pass"]),
                headers=get_headers()
            )
            return response.status_code == 200
    except Exception:
        return False

# ============================================================================
# QUEUE LISTING AND INFORMATION TOOLS
# ============================================================================

@mcp.tool()
async def list_queues(qmgr_name: str, queue_pattern: Optional[str] = None, queue_type: Optional[str] = None) -> str:
    """
    Retrieves a list of queues from a specified IBM MQ Queue Manager.
    
    Args:
        qmgr_name: The name of the queue manager (e.g., 'QM1').
        queue_pattern: Optional wildcard pattern to filter by name (e.g., 'APP.*').
        queue_type: Optional filter for queue type (e.g., 'local', 'alias', 'remote', 'model').
        
    Returns:
        JSON string containing queue information or error message.
    """
    config = get_mq_config()
    url = f"{get_base_url(config['host'], config['port'])}/qmgr/{qmgr_name}/queue"
    
    # Build query parameters based on user intent
    params = {}
    if queue_pattern:
        params["name"] = queue_pattern
    if queue_type:
        params["type"] = queue_type

    try:
        async with httpx.AsyncClient(verify=False) as client:
            response = await client.get(
                url,
                auth=(config["user"], config["pass"]),
                headers=get_headers(),
                params=params
            )
            return await handle_mq_response(response)
                
    except Exception as e:
        return f"Failed to connect to MQ REST API: {str(e)}"

@mcp.tool()
async def get_queue_details(qmgr_name: str, queue_name: str, attributes: Optional[str] = None) -> str:
    """
    Retrieves detailed configuration information for a specific queue.
    
    Args:
        qmgr_name: The name of the queue manager (e.g., 'QM1').
        queue_name: The name of the queue to query.
        attributes: Optional comma-separated list of specific attributes to retrieve 
                   (e.g., 'currentDepth,maximumDepth,openInputCount').
        
    Returns:
        JSON string containing queue details or error message.
    """
    config = get_mq_config()
    url = f"{get_base_url(config['host'], config['port'])}/qmgr/{qmgr_name}/queue/{queue_name}"
    
    params = {}
    if attributes:
        params["attributes"] = attributes

    try:
        async with httpx.AsyncClient(verify=False) as client:
            response = await client.get(
                url,
                auth=(config["user"], config["pass"]),
                headers=get_headers(),
                params=params
            )
            return await handle_mq_response(response)
                
    except Exception as e:
        return f"Failed to connect to MQ REST API: {str(e)}"

@mcp.tool()
async def get_queue_status(qmgr_name: str, queue_name: str, status_attributes: Optional[str] = None) -> str:
    """
    Retrieves runtime status information for a queue including current depth, open handles, and age.
    
    Args:
        qmgr_name: The name of the queue manager (e.g., 'QM1').
        queue_name: The name of the queue to query.
        status_attributes: Optional comma-separated list of status attributes to retrieve
                          (e.g., 'currentDepth,oldestMessageAge,openInputCount,openOutputCount').
                          Use '*' to retrieve all status attributes.
        
    Returns:
        JSON string containing queue status information or error message.
    """
    config = get_mq_config()
    url = f"{get_base_url(config['host'], config['port'])}/qmgr/{qmgr_name}/queue/{queue_name}"
    
    params = {}
    if status_attributes:
        params["status"] = status_attributes
    else:
        params["status"] = "*"

    try:
        async with httpx.AsyncClient(verify=False) as client:
            response = await client.get(
                url,
                auth=(config["user"], config["pass"]),
                headers=get_headers(),
                params=params
            )
            return await handle_mq_response(response)
                
    except Exception as e:
        return f"Failed to connect to MQ REST API: {str(e)}"

# ============================================================================
# QUEUE CREATION TOOLS
# ============================================================================

@mcp.tool()
async def create_local_queue(
    qmgr_name: str, 
    queue_name: str, 
    max_depth: int = 5000, 
    max_message_length: int = 4194304,
    default_persistence: str = "persistent",
    desc: str = "Created via MCP"
) -> str:
    """
    Creates a new Local Queue on the specified IBM MQ Queue Manager.
    This operation is idempotent - if the queue already exists, it returns a notice.
    
    Args:
        qmgr_name: The name of the queue manager (e.g., 'QM1').
        queue_name: The name of the new queue to create.
        max_depth: Maximum message depth (defaults to 5000).
        max_message_length: Maximum message size in bytes (defaults to 4194304 = 4MB).
        default_persistence: Message persistence setting ('persistent' or 'nonPersistent').
        desc: Description of the queue's purpose.
        
    Returns:
        Success message, notice if queue exists, or error message.
    """
    # Check if queue already exists (idempotency)
    if await check_queue_exists(qmgr_name, queue_name):
        return f"Notice: Queue {queue_name} already exists on {qmgr_name}."
    
    config = get_mq_config()
    url = f"{get_base_url(config['host'], config['port'])}/qmgr/{qmgr_name}/queue"
    
    payload = {
        "name": queue_name,
        "type": "local",
        "maximumDepth": max_depth,
        "maximumMessageLength": max_message_length,
        "defaultPersistence": default_persistence,
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
                return f"Success: Local queue {queue_name} created successfully on {qmgr_name}."
            elif response.status_code == 400 and "MQRC_Q_ALREADY_EXISTS" in response.text:
                return f"Notice: Queue {queue_name} already exists on {qmgr_name}."
            else:
                return await handle_mq_response(response, [201])
                
    except Exception as e:
        return f"Failed to connect to MQ REST API: {str(e)}"

@mcp.tool()
async def create_remote_queue(
    qmgr_name: str,
    queue_name: str,
    remote_queue_name: str,
    remote_qmgr_name: str,
    transmission_queue: str,
    desc: str = "Remote queue created via MCP"
) -> str:
    """
    Creates a Remote Queue Definition on the specified IBM MQ Queue Manager.
    Remote queues are used to send messages to queues on other queue managers.
    
    Args:
        qmgr_name: The name of the local queue manager where the definition is created.
        queue_name: The name of the remote queue definition to create locally.
        remote_queue_name: The name of the actual queue on the remote queue manager.
        remote_qmgr_name: The name of the remote queue manager.
        transmission_queue: The name of the transmission queue to use for routing.
        desc: Description of the remote queue definition.
        
    Returns:
        Success message, notice if queue exists, or error message.
    """
    # Check if queue already exists (idempotency)
    if await check_queue_exists(qmgr_name, queue_name):
        return f"Notice: Remote queue definition {queue_name} already exists on {qmgr_name}."
    
    config = get_mq_config()
    url = f"{get_base_url(config['host'], config['port'])}/qmgr/{qmgr_name}/queue"
    
    payload = {
        "name": queue_name,
        "type": "remote",
        "remoteQueueName": remote_queue_name,
        "remoteQueueManagerName": remote_qmgr_name,
        "transmissionQueueName": transmission_queue,
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
                return f"Success: Remote queue definition {queue_name} created successfully on {qmgr_name}."
            elif response.status_code == 400 and "MQRC_Q_ALREADY_EXISTS" in response.text:
                return f"Notice: Remote queue definition {queue_name} already exists on {qmgr_name}."
            else:
                return await handle_mq_response(response, [201])
                
    except Exception as e:
        return f"Failed to connect to MQ REST API: {str(e)}"

@mcp.tool()
async def create_alias_queue(
    qmgr_name: str,
    queue_name: str,
    target_name: str,
    target_type: str = "queue",
    desc: str = "Alias queue created via MCP"
) -> str:
    """
    Creates an Alias Queue on the specified IBM MQ Queue Manager.
    Alias queues provide an alternative name for accessing another queue or topic.
    
    Args:
        qmgr_name: The name of the queue manager.
        queue_name: The name of the alias queue to create.
        target_name: The name of the target queue or topic that this alias points to.
        target_type: The type of target ('queue' or 'topic'). Defaults to 'queue'.
        desc: Description of the alias queue.
        
    Returns:
        Success message, notice if queue exists, or error message.
    """
    # Check if queue already exists (idempotency)
    if await check_queue_exists(qmgr_name, queue_name):
        return f"Notice: Alias queue {queue_name} already exists on {qmgr_name}."
    
    config = get_mq_config()
    url = f"{get_base_url(config['host'], config['port'])}/qmgr/{qmgr_name}/queue"
    
    payload = {
        "name": queue_name,
        "type": "alias",
        "targetName": target_name,
        "targetType": target_type,
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
                return f"Success: Alias queue {queue_name} created successfully on {qmgr_name}, pointing to {target_name}."
            elif response.status_code == 400 and "MQRC_Q_ALREADY_EXISTS" in response.text:
                return f"Notice: Alias queue {queue_name} already exists on {qmgr_name}."
            else:
                return await handle_mq_response(response, [201])
                
    except Exception as e:
        return f"Failed to connect to MQ REST API: {str(e)}"

@mcp.tool()
async def create_model_queue(
    qmgr_name: str,
    queue_name: str,
    defines_type: str = "temporary",
    max_depth: int = 1000,
    default_persistence: str = "nonPersistent",
    desc: str = "Model queue created via MCP"
) -> str:
    """
    Creates a Model Queue on the specified IBM MQ Queue Manager.
    Model queues serve as templates for creating dynamic queues.
    
    Args:
        qmgr_name: The name of the queue manager.
        queue_name: The name of the model queue to create.
        defines_type: Type of dynamic queue this model defines ('temporary' or 'permanent').
        max_depth: Maximum message depth for queues created from this model (defaults to 1000).
        default_persistence: Message persistence for dynamic queues ('persistent' or 'nonPersistent').
        desc: Description of the model queue.
        
    Returns:
        Success message, notice if queue exists, or error message.
    """
    # Check if queue already exists (idempotency)
    if await check_queue_exists(qmgr_name, queue_name):
        return f"Notice: Model queue {queue_name} already exists on {qmgr_name}."
    
    config = get_mq_config()
    url = f"{get_base_url(config['host'], config['port'])}/qmgr/{qmgr_name}/queue"
    
    payload = {
        "name": queue_name,
        "type": "model",
        "maximumDepth": max_depth,
        "defaultPersistence": default_persistence,
        "definesType": defines_type,
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
                return f"Success: Model queue {queue_name} created successfully on {qmgr_name}."
            elif response.status_code == 400 and "MQRC_Q_ALREADY_EXISTS" in response.text:
                return f"Notice: Model queue {queue_name} already exists on {qmgr_name}."
            else:
                return await handle_mq_response(response, [201])
                
    except Exception as e:
        return f"Failed to connect to MQ REST API: {str(e)}"

# ============================================================================
# QUEUE MODIFICATION TOOLS
# ============================================================================

@mcp.tool()
async def update_queue_attributes(
    qmgr_name: str,
    queue_name: str,
    max_depth: Optional[int] = None,
    max_message_length: Optional[int] = None,
    desc: Optional[str] = None
) -> str:
    """
    Updates attributes of an existing queue using PATCH operation.
    Only the specified attributes will be modified; others remain unchanged.
    
    Args:
        qmgr_name: The name of the queue manager.
        queue_name: The name of the queue to update.
        max_depth: New maximum message depth (optional).
        max_message_length: New maximum message size in bytes (optional).
        desc: New description for the queue (optional).
        
    Returns:
        Success message or error message.
    """
    config = get_mq_config()
    url = f"{get_base_url(config['host'], config['port'])}/qmgr/{qmgr_name}/queue/{queue_name}"
    
    # Build payload with only specified attributes
    payload = {}
    if max_depth is not None:
        payload["maximumDepth"] = max_depth
    if max_message_length is not None:
        payload["maximumMessageLength"] = max_message_length
    if desc is not None:
        payload["description"] = desc
    
    if not payload:
        return "Error: No attributes specified for update. Please provide at least one attribute to modify."

    try:
        async with httpx.AsyncClient(verify=False) as client:
            response = await client.patch(
                url,
                auth=(config["user"], config["pass"]),
                headers=get_headers(),
                json=payload
            )
            
            if response.status_code in [200, 204]:
                updated_attrs = ", ".join(payload.keys())
                return f"Success: Queue {queue_name} updated successfully on {qmgr_name}. Modified attributes: {updated_attrs}"
            else:
                return await handle_mq_response(response, [200, 204])
                
    except Exception as e:
        return f"Failed to connect to MQ REST API: {str(e)}"

@mcp.tool()
async def set_queue_inhibit_state(
    qmgr_name: str,
    queue_name: str,
    inhibit_get: Optional[str] = None,
    inhibit_put: Optional[str] = None
) -> str:
    """
    Controls whether GET and/or PUT operations are allowed on a queue.
    Useful for maintenance, troubleshooting, or controlling message flow.
    
    Args:
        qmgr_name: The name of the queue manager.
        queue_name: The name of the queue to modify.
        inhibit_get: Control GET operations ('allowed' or 'inhibited'). None = no change.
        inhibit_put: Control PUT operations ('allowed' or 'inhibited'). None = no change.
        
    Returns:
        Success message or error message.
    """
    config = get_mq_config()
    url = f"{get_base_url(config['host'], config['port'])}/qmgr/{qmgr_name}/queue/{queue_name}"
    
    # Build payload with only specified inhibit settings
    payload = {}
    if inhibit_get is not None:
        if inhibit_get not in ["allowed", "inhibited"]:
            return "Error: inhibit_get must be 'allowed' or 'inhibited'"
        payload["inhibitGet"] = inhibit_get
    if inhibit_put is not None:
        if inhibit_put not in ["allowed", "inhibited"]:
            return "Error: inhibit_put must be 'allowed' or 'inhibited'"
        payload["inhibitPut"] = inhibit_put
    
    if not payload:
        return "Error: No inhibit state specified. Please provide inhibit_get and/or inhibit_put."

    try:
        async with httpx.AsyncClient(verify=False) as client:
            response = await client.patch(
                url,
                auth=(config["user"], config["pass"]),
                headers=get_headers(),
                json=payload
            )
            
            if response.status_code in [200, 204]:
                changes = []
                if inhibit_get:
                    changes.append(f"GET operations {inhibit_get}")
                if inhibit_put:
                    changes.append(f"PUT operations {inhibit_put}")
                return f"Success: Queue {queue_name} on {qmgr_name} updated. {', '.join(changes)}."
            else:
                return await handle_mq_response(response, [200, 204])
                
    except Exception as e:
        return f"Failed to connect to MQ REST API: {str(e)}"

# ============================================================================
# QUEUE DELETION AND CLEARING TOOLS
# ============================================================================

@mcp.tool()
async def clear_queue_messages(qmgr_name: str, queue_name: str) -> str:
    """
    Clears all messages from a queue without deleting the queue itself.
    This operation removes all messages currently on the queue.
    
    Args:
        qmgr_name: The name of the queue manager.
        queue_name: The name of the queue to clear.
        
    Returns:
        Success message or error message.
    """
    config = get_mq_config()
    url = f"{get_base_url(config['host'], config['port'])}/qmgr/{qmgr_name}/queue/{queue_name}/message"

    try:
        async with httpx.AsyncClient(verify=False) as client:
            response = await client.delete(
                url,
                auth=(config["user"], config["pass"]),
                headers=get_headers()
            )
            
            if response.status_code in [200, 204]:
                return f"Success: All messages cleared from queue {queue_name} on {qmgr_name}."
            else:
                return await handle_mq_response(response, [200, 204])
                
    except Exception as e:
        return f"Failed to connect to MQ REST API: {str(e)}"

@mcp.tool()
async def delete_queue(qmgr_name: str, queue_name: str, purge: bool = False) -> str:
    """
    Deletes a queue from the queue manager.
    By default, the queue must be empty and closed. Use purge=True to force deletion.
    
    Args:
        qmgr_name: The name of the queue manager.
        queue_name: The name of the queue to delete.
        purge: If True, purges all messages before deleting. If False, queue must be empty.
        
    Returns:
        Success message or error message.
    """
    config = get_mq_config()
    url = f"{get_base_url(config['host'], config['port'])}/qmgr/{qmgr_name}/queue/{queue_name}"
    
    params = {}
    if purge:
        params["purge"] = "true"

    try:
        async with httpx.AsyncClient(verify=False) as client:
            response = await client.delete(
                url,
                auth=(config["user"], config["pass"]),
                headers=get_headers(),
                params=params
            )
            
            if response.status_code in [200, 204]:
                purge_msg = " (with purge)" if purge else ""
                return f"Success: Queue {queue_name} deleted from {qmgr_name}{purge_msg}."
            else:
                return await handle_mq_response(response, [200, 204])
                
    except Exception as e:
        return f"Failed to connect to MQ REST API: {str(e)}"

# ============================================================================
# QUEUE MANAGER STATUS AND INFORMATION TOOLS
# ============================================================================

@mcp.tool()
async def get_qmgr_status(qmgr_name: str) -> str:
    """
    Retrieves the status and configuration of a queue manager.
    Returns information including running status, connection count, and channel initiator status.
    
    Args:
        qmgr_name: The name of the queue manager to query.
        
    Returns:
        JSON string containing queue manager status or error message.
    """
    config = get_mq_config()
    url = f"{get_base_url(config['host'], config['port'])}/qmgr/{qmgr_name}/status"

    try:
        async with httpx.AsyncClient(verify=False) as client:
            response = await client.get(
                url,
                auth=(config["user"], config["pass"]),
                headers=get_headers()
            )
            return await handle_mq_response(response)
                
    except Exception as e:
        return f"Failed to connect to MQ REST API: {str(e)}"

@mcp.tool()
async def list_queue_managers(status_filter: Optional[str] = None) -> str:
    """
    Lists all queue managers accessible via the REST API.
    Optionally filters by status to show only running, stopped, or all queue managers.
    
    Args:
        status_filter: Optional status filter ('running', 'stopped', or '*' for all).
        
    Returns:
        JSON string containing list of queue managers or error message.
    """
    config = get_mq_config()
    url = f"{get_base_url(config['host'], config['port'])}/qmgr"
    
    params = {}
    if status_filter:
        params["status"] = status_filter

    try:
        async with httpx.AsyncClient(verify=False) as client:
            response = await client.get(
                url,
                auth=(config["user"], config["pass"]),
                headers=get_headers(),
                params=params
            )
            return await handle_mq_response(response)
                
    except Exception as e:
        return f"Failed to connect to MQ REST API: {str(e)}"

# ============================================================================
# RDQM HIGH AVAILABILITY STATUS TOOLS
# ============================================================================

@mcp.tool()
async def get_qmgr_ha_status(qmgr_name: str) -> str:
    """
    Retrieves High Availability (HA) status for an RDQM queue manager.
    Returns HA role (primary/secondary), HA status (normal/error), and current location.
    Essential for monitoring RDQM cluster health and detecting failover conditions.
    
    Args:
        qmgr_name: The name of the RDQM queue manager to query.
        
    Returns:
        JSON string containing HA status information including:
        - haRole: primary, secondary, or unknown
        - haStatus: normal, error, or other states
        - haCurrentLocation: node where QM is currently running
        - haPreferredLocation: preferred node for this QM
        Returns error message if query fails.
    """
    config = get_mq_config()
    url = f"{get_base_url(config['host'], config['port'])}/qmgr/{qmgr_name}/status"

    try:
        async with httpx.AsyncClient(verify=False) as client:
            response = await client.get(
                url,
                auth=(config["user"], config["pass"]),
                headers=get_headers()
            )
            
            if response.status_code == 200:
                # Parse and extract HA-specific information
                data = response.json()
                if "qmgr" in data and len(data["qmgr"]) > 0:
                    qmgr_info = data["qmgr"][0]
                    ha_info = {
                        "name": qmgr_info.get("name"),
                        "status": qmgr_info.get("status"),
                        "haRole": qmgr_info.get("haRole", "N/A"),
                        "haStatus": qmgr_info.get("haStatus", "N/A"),
                        "haCurrentLocation": qmgr_info.get("haCurrentLocation", "N/A"),
                        "haPreferredLocation": qmgr_info.get("haPreferredLocation", "N/A")
                    }
                    return json.dumps(ha_info, indent=2)
                return response.text
            else:
                return await handle_mq_response(response)
                
    except Exception as e:
        return f"Failed to connect to MQ REST API: {str(e)}"

@mcp.tool()
async def get_estate_qmgr_status() -> str:
    """
    Retrieves status for all queue managers in the MQ estate.
    Queries the /qmgr?status=* endpoint to get a comprehensive view of all queue managers,
    including their HA status if they are RDQM instances.
    
    Useful for:
    - Estate-wide health monitoring
    - Detecting failover events across multiple queue managers
    - Identifying queue managers not running on preferred nodes
    - Centralized dashboard data collection
    
    Returns:
        JSON string containing status of all queue managers including:
        - name: Queue manager name
        - status: running, stopped, etc.
        - haRole: HA role if RDQM (primary/secondary)
        - haStatus: HA health status if RDQM
        - haCurrentLocation: Current node location if RDQM
        Returns error message if query fails.
    """
    config = get_mq_config()
    url = f"{get_base_url(config['host'], config['port'])}/qmgr"
    
    params = {"status": "*"}

    try:
        async with httpx.AsyncClient(verify=False) as client:
            response = await client.get(
                url,
                auth=(config["user"], config["pass"]),
                headers=get_headers(),
                params=params
            )
            
            if response.status_code == 200:
                # Parse and format for easier consumption
                data = response.json()
                if "qmgr" in data:
                    estate_status = []
                    for qm in data["qmgr"]:
                        qm_info = {
                            "name": qm.get("name"),
                            "status": qm.get("status"),
                            "haRole": qm.get("haRole", "N/A"),
                            "haStatus": qm.get("haStatus", "N/A"),
                            "haCurrentLocation": qm.get("haCurrentLocation", "N/A"),
                            "connectionCount": qm.get("connectionCount", 0)
                        }
                        estate_status.append(qm_info)
                    return json.dumps({"queueManagers": estate_status, "count": len(estate_status)}, indent=2)
                return response.text
            else:
                return await handle_mq_response(response)
                
    except Exception as e:
        return f"Failed to connect to MQ REST API: {str(e)}"

@mcp.tool()
async def monitor_queue_depths(qmgr_name: str, queue_pattern: str = "APP.*", threshold_percent: int = 80) -> str:
    """
    Monitors queue depths across multiple queues and identifies those exceeding a threshold.
    Useful for proactive alerting and capacity management.
    
    Args:
        qmgr_name: The name of the queue manager.
        queue_pattern: Wildcard pattern to match queue names (e.g., 'APP.*', 'PROD.*').
        threshold_percent: Alert threshold as percentage of maximum depth (default 80%).
        
    Returns:
        JSON string containing:
        - queues: List of queues with their depth information
        - alerts: List of queues exceeding the threshold
        - summary: Overall statistics
        Returns error message if query fails.
    """
    config = get_mq_config()
    url = f"{get_base_url(config['host'], config['port'])}/qmgr/{qmgr_name}/queue"
    
    params = {
        "name": queue_pattern,
        "status": "currentDepth,maximumDepth"
    }

    try:
        async with httpx.AsyncClient(verify=False) as client:
            response = await client.get(
                url,
                auth=(config["user"], config["pass"]),
                headers=get_headers(),
                params=params
            )
            
            if response.status_code == 200:
                data = response.json()
                if "queue" in data:
                    queues_info = []
                    alerts = []
                    
                    for queue in data["queue"]:
                        if "status" in queue:
                            current = queue["status"].get("currentDepth", 0)
                            maximum = queue.get("maximumDepth", 5000)
                            percent = (current / maximum * 100) if maximum > 0 else 0
                            
                            queue_info = {
                                "name": queue.get("name"),
                                "currentDepth": current,
                                "maximumDepth": maximum,
                                "percentFull": round(percent, 2)
                            }
                            queues_info.append(queue_info)
                            
                            if percent >= threshold_percent:
                                alerts.append({
                                    "queue": queue.get("name"),
                                    "percentFull": round(percent, 2),
                                    "currentDepth": current,
                                    "maximumDepth": maximum
                                })
                    
                    result = {
                        "queueManager": qmgr_name,
                        "pattern": queue_pattern,
                        "threshold": threshold_percent,
                        "queues": queues_info,
                        "alerts": alerts,
                        "summary": {
                            "totalQueues": len(queues_info),
                            "queuesOverThreshold": len(alerts)
                        }
                    }
                    return json.dumps(result, indent=2)
                return response.text
            else:
                return await handle_mq_response(response)
                
    except Exception as e:
        return f"Failed to connect to MQ REST API: {str(e)}"

# ============================================================================
# CHANNEL MANAGEMENT TOOLS
# ============================================================================

@mcp.tool()
async def list_channels(qmgr_name: str, channel_pattern: Optional[str] = None, channel_type: Optional[str] = None) -> str:
    """
    Lists channels on the specified queue manager.
    Channels are used for communication between queue managers or with client applications.
    
    Args:
        qmgr_name: The name of the queue manager.
        channel_pattern: Optional wildcard pattern to filter by channel name (e.g., 'TO.*').
        channel_type: Optional filter for channel type (e.g., 'sender', 'receiver', 'svrconn').
        
    Returns:
        JSON string containing channel information or error message.
    """
    config = get_mq_config()
    url = f"{get_base_url(config['host'], config['port'])}/qmgr/{qmgr_name}/channel"
    
    params = {}
    if channel_pattern:
        params["name"] = channel_pattern
    if channel_type:
        params["type"] = channel_type

    try:
        async with httpx.AsyncClient(verify=False) as client:
            response = await client.get(
                url,
                auth=(config["user"], config["pass"]),
                headers=get_headers(),
                params=params
            )
            return await handle_mq_response(response)
                
    except Exception as e:
        return f"Failed to connect to MQ REST API: {str(e)}"

@mcp.tool()
async def get_channel_status(qmgr_name: str, channel_name: str) -> str:
    """
    Retrieves the runtime status of a specific channel.
    Returns information about channel state, messages sent/received, and connection details.
    
    Args:
        qmgr_name: The name of the queue manager.
        channel_name: The name of the channel to query.
        
    Returns:
        JSON string containing channel status or error message.
    """
    config = get_mq_config()
    url = f"{get_base_url(config['host'], config['port'])}/qmgr/{qmgr_name}/channel/{channel_name}"
    
    params = {"status": "*"}

    try:
        async with httpx.AsyncClient(verify=False) as client:
            response = await client.get(
                url,
                auth=(config["user"], config["pass"]),
                headers=get_headers(),
                params=params
            )
            return await handle_mq_response(response)
                
    except Exception as e:
        return f"Failed to connect to MQ REST API: {str(e)}"

# ============================================================================
# LISTENER MANAGEMENT TOOLS
# ============================================================================

@mcp.tool()
async def list_listeners(qmgr_name: str) -> str:
    """
    Lists all listeners configured on the specified queue manager.
    Listeners accept incoming network connections from MQ clients and other queue managers.
    
    Args:
        qmgr_name: The name of the queue manager.
        
    Returns:
        JSON string containing listener information or error message.
    """
    config = get_mq_config()
    url = f"{get_base_url(config['host'], config['port'])}/qmgr/{qmgr_name}/listener"

    try:
        async with httpx.AsyncClient(verify=False) as client:
            response = await client.get(
                url,
                auth=(config["user"], config["pass"]),
                headers=get_headers()
            )
            return await handle_mq_response(response)
                
    except Exception as e:
        return f"Failed to connect to MQ REST API: {str(e)}"

# ============================================================================
# BATCH AND UTILITY OPERATIONS
# ============================================================================

@mcp.tool()
async def compare_queue_configs(qmgr1_name: str, qmgr2_name: str, queue_name: str) -> str:
    """
    Compares the configuration of a queue across two queue managers.
    Useful for ensuring consistency across environments (dev, test, prod) or HA pairs.
    
    Args:
        qmgr1_name: The name of the first queue manager.
        qmgr2_name: The name of the second queue manager.
        queue_name: The name of the queue to compare.
        
    Returns:
        JSON string showing configuration differences or error message.
    """
    config = get_mq_config()
    base_url = get_base_url(config['host'], config['port'])
    
    try:
        async with httpx.AsyncClient(verify=False) as client:
            # Get queue config from first QM
            response1 = await client.get(
                f"{base_url}/qmgr/{qmgr1_name}/queue/{queue_name}",
                auth=(config["user"], config["pass"]),
                headers=get_headers()
            )
            
            # Get queue config from second QM
            response2 = await client.get(
                f"{base_url}/qmgr/{qmgr2_name}/queue/{queue_name}",
                auth=(config["user"], config["pass"]),
                headers=get_headers()
            )
            
            if response1.status_code == 200 and response2.status_code == 200:
                config1 = response1.json()
                config2 = response2.json()
                
                # Extract queue attributes for comparison
                q1 = config1.get("queue", [{}])[0] if "queue" in config1 else {}
                q2 = config2.get("queue", [{}])[0] if "queue" in config2 else {}
                
                # Compare key attributes
                comparison = {
                    "queueName": queue_name,
                    "queueManager1": qmgr1_name,
                    "queueManager2": qmgr2_name,
                    "differences": [],
                    "identical": True
                }
                
                # Attributes to compare
                attrs_to_compare = ["type", "maximumDepth", "maximumMessageLength", 
                                   "defaultPersistence", "inhibitGet", "inhibitPut"]
                
                for attr in attrs_to_compare:
                    val1 = q1.get(attr)
                    val2 = q2.get(attr)
                    if val1 != val2:
                        comparison["identical"] = False
                        comparison["differences"].append({
                            "attribute": attr,
                            f"{qmgr1_name}": val1,
                            f"{qmgr2_name}": val2
                        })
                
                return json.dumps(comparison, indent=2)
            else:
                errors = []
                if response1.status_code != 200:
                    errors.append(f"{qmgr1_name}: {response1.status_code} - {response1.text}")
                if response2.status_code != 200:
                    errors.append(f"{qmgr2_name}: {response2.status_code} - {response2.text}")
                return f"Error comparing queues: {'; '.join(errors)}"
                
    except Exception as e:
        return f"Failed to connect to MQ REST API: {str(e)}"

@mcp.tool()
async def export_queue_definitions(qmgr_name: str, queue_pattern: str = "*") -> str:
    """
    Exports queue definitions matching a pattern to JSON format.
    Useful for backup, documentation, or replicating configurations to other queue managers.
    
    Args:
        qmgr_name: The name of the queue manager.
        queue_pattern: Wildcard pattern to match queue names (default '*' for all queues).
        
    Returns:
        JSON string containing queue definitions or error message.
    """
    config = get_mq_config()
    url = f"{get_base_url(config['host'], config['port'])}/qmgr/{qmgr_name}/queue"
    
    params = {"name": queue_pattern}

    try:
        async with httpx.AsyncClient(verify=False) as client:
            response = await client.get(
                url,
                auth=(config["user"], config["pass"]),
                headers=get_headers(),
                params=params
            )
            
            if response.status_code == 200:
                data = response.json()
                if "queue" in data:
                    # Extract key configuration attributes
                    definitions = []
                    for queue in data["queue"]:
                        definition = {
                            "name": queue.get("name"),
                            "type": queue.get("type"),
                            "maximumDepth": queue.get("maximumDepth"),
                            "maximumMessageLength": queue.get("maximumMessageLength"),
                            "defaultPersistence": queue.get("defaultPersistence"),
                            "description": queue.get("description", "")
                        }
                        
                        # Add type-specific attributes
                        if queue.get("type") == "remote":
                            definition["remoteQueueName"] = queue.get("remoteQueueName")
                            definition["remoteQueueManagerName"] = queue.get("remoteQueueManagerName")
                            definition["transmissionQueueName"] = queue.get("transmissionQueueName")
                        elif queue.get("type") == "alias":
                            definition["targetName"] = queue.get("targetName")
                            definition["targetType"] = queue.get("targetType")
                        
                        definitions.append(definition)
                    
                    export = {
                        "queueManager": qmgr_name,
                        "exportDate": "Generated via MCP",
                        "queueCount": len(definitions),
                        "queues": definitions
                    }
                    return json.dumps(export, indent=2)
                return response.text
            else:
                return await handle_mq_response(response)
                
    except Exception as e:
        return f"Failed to connect to MQ REST API: {str(e)}"

if __name__ == "__main__":
    # This runs the server using standard input/output, which is how MCP communicates
    mcp.run()
