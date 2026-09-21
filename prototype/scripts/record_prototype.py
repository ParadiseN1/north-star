"""Record this prototype's measured results through its own MCP interface."""
import json
import os
from pathlib import Path
import subprocess
import sys

root = Path(__file__).resolve().parents[1]
source = str(root / "evidence/VALIDATION.md")
updates = [
    {"event_key": "prototype-v1:verified", "kind": "completed", "task_id": "first-prototype",
     "title": "The menu bar prototype is ready for a first try",
     "detail": "You can open project context, see changes since your last visit, inspect sources, and save thoughts. Agents can append updates through MCP. Optional Codex sorting routes thoughts while preserving ideas as ideas. Spoken input is implemented but still needs a microphone test.",
     "evidence": "verified", "verification": "15 automated tests passed. Native UI project creation, typed capture, idea filing, live MCP updates, unread state, and restart persistence checked. Real Codex routing passed with synthetic data. Microphone recording was not exercised."},
    {"event_key": "prototype-v1:concurrency", "kind": "knowledge",
     "title": "Parallel agents can contribute without losing each other's updates",
     "detail": "The app combines append-only reports. Tests with 32 writers preserved every update; retrying the same report did not duplicate it. Verified and ready labels still depend on evidence supplied by the reporting agent.",
     "evidence": "verified", "verification": "Concurrent SQLite writes, duplicate retries, and evidence validation passed in the automated suite."},
    {"event_key": "prototype-v1:next-live-project", "kind": "suggestion",
     "title": "Use it alongside one real project",
     "detail": "Connect your working agent from Settings. After a few updates, check whether this overview is enough to resume work without reopening the whole conversation."},
    {"event_key": "prototype-v1:next-voice", "kind": "suggestion",
     "title": "Try capturing a spoken thought",
     "detail": "Open Capture a thought and choose Speak instead. Allow microphone and Speech access when macOS asks. Dictation depends on on-device language support; typing is always available."},
]
messages = [{"jsonrpc": "2.0", "id": 0, "method": "initialize", "params": {"protocolVersion": "2025-06-18"}},
            {"jsonrpc": "2.0", "method": "notifications/initialized"}]
for i, update in enumerate(updates, 1):
    arguments = {"project_id": "north-star", "agent": "Prototype builder", "source": source, **update}
    messages.append({"jsonrpc": "2.0", "id": i, "method": "tools/call", "params": {"name": "report_update", "arguments": arguments}})
run = subprocess.run([sys.executable, str(root / "backend/bridge.py"), "--mcp"],
    input="\n".join(json.dumps(message) for message in messages) + "\n", capture_output=True, text=True,
    env={**os.environ, "NORTH_STAR_HOME": str(root / ".data")}, check=True)
responses = [json.loads(line) for line in run.stdout.splitlines()]
assert all(not response.get("result", {}).get("isError") for response in responses)
print("Recorded the prototype's verified results and suggested next steps through MCP.")
