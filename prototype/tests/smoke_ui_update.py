"""Send an actual MCP report to the isolated native UI test database."""
import json
import os
from pathlib import Path
import subprocess
import sys
root = Path(__file__).resolve().parents[1]
messages = [
    {"jsonrpc": "2.0", "id": 1, "method": "initialize", "params": {"protocolVersion": "2025-06-18"}},
    {"jsonrpc": "2.0", "method": "notifications/initialized"},
    {"jsonrpc": "2.0", "id": 2, "method": "tools/call", "params": {"name": "report_update", "arguments": {
        "project_id": "north-star", "agent": "Prototype QA", "event_key": "native-ui-transport-check",
        "kind": "knowledge", "title": "A new agent update has arrived through MCP",
        "detail": "This test report was sent by a separate stdio MCP client while the native app was running.",
        "source": "tests/smoke_ui_update.py"}}}]
run = subprocess.run([sys.executable, str(root / "backend/bridge.py"), "--mcp"],
    input="\n".join(json.dumps(m) for m in messages) + "\n", text=True, capture_output=True,
    env={**os.environ, "NORTH_STAR_HOME": str(root / "evidence/ui-data")}, check=True)
responses = [json.loads(line) for line in run.stdout.splitlines()]
assert responses[-1]["result"]["isError"] is False
print("Sent the test update through MCP to the isolated native UI database.")
