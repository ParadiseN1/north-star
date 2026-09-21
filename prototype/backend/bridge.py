#!/usr/bin/env python3
"""One-shot native UI bridge, or a newline-delimited stdio MCP server."""
import json
import sys
# The installed backend lives inside a signed app bundle, which must stay unchanged.
sys.dont_write_bytecode = True
from store import Store


def schema(properties, required=()):
    return {"type": "object", "properties": properties, "required": list(required), "additionalProperties": False}


def string(description):
    return {"type": "string", "description": description}


TOOLS = [
    {"name": "list_projects", "description": "List projects in stable order with current context and unread changes.", "inputSchema": schema({})},
    {"name": "get_context", "description": "Read intent, agreed unfinished plans, results, evidence, suggestions and source history. Does not mark the project seen.", "inputSchema": schema({"project_id": string("Project ID")}, ["project_id"])},
    {"name": "create_project", "description": "Create a project only when the user has asked to track it.", "inputSchema": schema({"name": string("Project name"), "purpose": string("Product, audience and purpose"), "goal": string("Nearest agreed goal")}, ["name", "purpose", "goal"])},
    {"name": "report_update", "description": "Append one product-level change. Record plans before results. Use an unchanged event_key for retries. Never rewrite the whole project. Verified/ready require verification and source. Suggestions are not commitments.", "inputSchema": schema({
        "project_id": string("Project ID"), "agent": string("Stable agent name"), "event_key": string("Unique per logical update; reuse on retry"),
        "kind": {"type": "string", "enum": ["plan", "progress", "completed", "blocked", "decision", "knowledge", "idea", "suggestion"]},
        "title": string("Brief product outcome, at most 200 characters"), "detail": string("Why it matters, remaining work, limitations"),
        "task_id": string("Stable ID required for plan/progress/completed/blocked"), "evidence": {"type": "string", "enum": ["claimed", "verified", "ready"]},
        "verification": string("What was actually checked; distinguish local from live"), "source": string("Relevant artifact path, URL or decision reference"),
        "agreement": string("For a plan: cite the user's authorization")}, ["project_id", "agent", "event_key", "kind", "title"])},
    {"name": "capture_thought", "description": "Save the user's original thought. Project selection is optional. Does not silently create a plan.", "inputSchema": schema({"text": string("Verbatim thought"), "project_id": string("Optional explicit project")}, ["text"])},
    {"name": "list_thoughts", "description": "Read captured thoughts and routing status. Pending or needs_context thoughts can be interpreted.", "inputSchema": schema({})},
    {"name": "resolve_thought", "description": "File a thought as idea, knowledge or explicit decision. Use unclear if project or intent is ambiguous. Preserve a project explicitly chosen by the user. This records context without creating tasks.", "inputSchema": schema({
        "thought_id": string("Captured thought ID"), "project_id": string("Relevant project ID"),
        "category": {"type": "string", "enum": ["idea", "decision", "knowledge", "unclear"]},
        "title": string("Short faithful summary"), "reason": string("Why this classification/project follows from the note")}, ["thought_id", "category", "reason"])}
]


def rpc(store, request):
    if not isinstance(request, dict) or request.get("jsonrpc") != "2.0" or not isinstance(request.get("method"), str):
        return {"jsonrpc": "2.0", "id": request.get("id") if isinstance(request, dict) else None, "error": {"code": -32600, "message": "Invalid request"}}
    if "id" not in request:
        return None
    response = {"jsonrpc": "2.0", "id": request["id"]}
    method = request["method"]
    params = request.get("params", {})
    if not isinstance(params, dict):
        return {**response, "error": {"code": -32602, "message": "params must be an object"}}
    if method == "initialize":
        versions = ["2024-11-05", "2025-03-26", "2025-06-18", "2025-11-25"]
        version = params.get("protocolVersion")
        return {**response, "result": {"protocolVersion": version if version in versions else versions[-1], "capabilities": {"tools": {}}, "serverInfo": {"name": "north-star", "version": "0.1.0"}, "instructions": "Read the agent reporting guide. Append individual changes. Capture both agreed plans and results; never treat suggestions as commitments."}}
    if method == "ping":
        return {**response, "result": {}}
    if method == "tools/list":
        return {**response, "result": {"tools": TOOLS}}
    if method == "tools/call":
        name = params.get("name")
        arguments = params.get("arguments", {})
        try:
            if name not in {t["name"] for t in TOOLS} or not isinstance(arguments, dict):
                raise ValueError("Unknown tool or invalid arguments")
            result = store.dispatch(name, arguments)
            return {**response, "result": {"content": [{"type": "text", "text": json.dumps(result, ensure_ascii=False)}], "isError": False}}
        except (ValueError, TypeError, KeyError) as error:
            return {**response, "result": {"content": [{"type": "text", "text": str(error)}], "isError": True}}
    return {**response, "error": {"code": -32601, "message": "Method not found"}}


def main():
    store = Store()
    store.seed()
    if "--mcp" in sys.argv:
        for line in sys.stdin:
            try:
                response = rpc(store, json.loads(line))
            except json.JSONDecodeError:
                response = {"jsonrpc": "2.0", "id": None, "error": {"code": -32700, "message": "Parse error"}}
            except Exception:
                response = {"jsonrpc": "2.0", "id": None, "error": {"code": -32603, "message": "Local storage error"}}
            if response is not None:
                print(json.dumps(response, ensure_ascii=False), flush=True)
    else:
        try:
            request = json.load(sys.stdin)
            if request["method"] in {"agent_connection_status", "connect_agent"}:
                from connections import Connections
                result = Connections(store.directory).dispatch(request["method"], request.get("params", {}))
            else:
                result = store.dispatch(request["method"], request.get("params", {}))
            print(json.dumps({"result": result}, ensure_ascii=False))
        except Exception as error:
            print(json.dumps({"error": str(error)}))
            sys.exit(1)


if __name__ == "__main__":
    main()
