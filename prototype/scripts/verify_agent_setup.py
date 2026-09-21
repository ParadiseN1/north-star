"""Check exported connection details without changing any agent configuration."""
import base64
import json
import os
from pathlib import Path
import shlex
import subprocess
import tempfile
import urllib.parse

root = Path(__file__).resolve().parents[1]
with tempfile.TemporaryDirectory(prefix="north-star-onboarding-") as temporary:
    temporary = Path(temporary)
    alias = temporary / "agent's server folder"
    alias.symlink_to(root / "backend", target_is_directory=True)
    runner = temporary / "main.swift"
    runner.write_text('''import Foundation
let s = AgentSetup(python: "/usr/bin/python3", serverPath: CommandLine.arguments[1], dataDirectory: CommandLine.arguments[2], projectID: "north-star", projectName: "North Star", purpose: "Restore project context", goal: "Try the prototype")
let out: [String: String] = ["codex": s.installCommand(for: .codex)!, "claude": s.installCommand(for: .claude)!, "configuration": s.configuration, "cursor": s.cursorURL.absoluteString, "instructions": s.instructions, "message": s.setupMessage(for: .codex)]
let data = try! JSONSerialization.data(withJSONObject: out, options: [.sortedKeys])
print(String(data: data, encoding: .utf8)!)
''')
    binary = temporary / "export"
    subprocess.run(["swiftc", "-module-cache-path", str(root / "build/module-cache"),
                    str(root / "native/AgentSetup.swift"), str(runner), "-o", str(binary)], check=True)
    server = str(alias / "bridge.py")
    directory = str(temporary / "project's data $(literal)")
    emitted = json.loads(subprocess.check_output([str(binary), server, directory], text=True))
    for key in ["codex", "claude"]:
        arguments = shlex.split(emitted[key])
        assert arguments[-3:] == ["/usr/bin/python3", server, "--mcp"]
        assert arguments[arguments.index("--env") + 1] == "NORTH_STAR_HOME=" + directory
    config = json.loads(emitted["configuration"])["mcpServers"]["north-star"]
    query = urllib.parse.parse_qs(urllib.parse.urlparse(emitted["cursor"]).query)
    assert json.loads(base64.b64decode(query["config"][0])) == config
    identity = json.loads(emitted["instructions"].split("```json\n", 1)[1].split("```", 1)[0])
    assert identity["project_id"] == "north-star"
    assert "claimed" in emitted["instructions"] and "event_key" in emitted["instructions"]
    messages = [
        {"jsonrpc": "2.0", "id": 1, "method": "initialize", "params": {"protocolVersion": "2025-06-18"}},
        {"jsonrpc": "2.0", "id": 2, "method": "tools/call", "params": {"name": "get_context", "arguments": {"project_id": "north-star"}}}]
    process = subprocess.run([config["command"], *config["args"]], env={**os.environ, **config["env"]},
                             input="\n".join(json.dumps(m) for m in messages) + "\n", text=True, capture_output=True, check=True)
    replies = [json.loads(line) for line in process.stdout.splitlines()]
    assert not replies[-1]["result"]["isError"]
    assert json.loads(replies[-1]["result"]["content"][0]["text"])["id"] == "north-star"
    report = """PASS: generated Codex and Claude commands preserve spaces, apostrophes, and literal shell characters.
PASS: Cursor install URL decodes to the exact MCP server configuration.
PASS: copied configuration starts the real MCP server and reads the intended project in an isolated test database.
PASS: project instructions include the exact ID, reporting rules, evidence levels, and retry keys.
No user-level agent settings were changed. Client registration/reload was not exercised.
"""
    (root / "evidence/onboarding-check.txt").write_text(report)
    print(report)
