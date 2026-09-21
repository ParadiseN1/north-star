import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest
from unittest.mock import patch

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "backend"))
from connections import Connections
from store import Store
from bridge import rpc


class ConnectionTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory(prefix="north-star-connect-")
        self.addCleanup(self.temporary.cleanup)
        self.home = Path(self.temporary.name)
        self.directory = self.home / "project's data"
        self.store = Store(self.directory)
        self.store.seed()
        self.registration = None
        self.installs = 0
        self.failure = False
        self.bad_saved = False
        self.parameters = {"client": "Codex", "project_id": "north-star", "python": sys.executable,
                           "server_path": str(Path(__file__).resolve().parents[1] / "backend/bridge.py")}
        self.connections = Connections(self.directory, self.home, self.runner, lambda client: "/test/" + client)

    def runner(self, args, **kwargs):
        if not args[0].startswith("/test/"):
            return subprocess.run(args, **kwargs)
        if args[2] == "get":
            if self.registration is None:
                return subprocess.CompletedProcess(args, 1, "", "Error: No MCP server named 'north-star' found.")
            return subprocess.CompletedProcess(args, 0, json.dumps({"enabled": True, "transport": self.registration}), "")
        self.installs += 1
        if self.failure:
            return subprocess.CompletedProcess(args, 1, "", "fixture write failure")
        if args[0] == "/test/Codex":
            boundary = args.index("--")
            self.registration = {"type": "stdio", "command": args[boundary + 1], "args": args[boundary + 2:],
                                 "env": {"NORTH_STAR_HOME": args[args.index("--env") + 1].split("=", 1)[1]}}
            if self.bad_saved:
                self.registration["command"] = "/different/python"
        else:
            path = self.home / ".claude.json"
            saved = json.loads(path.read_text()) if path.exists() else {}
            saved.setdefault("mcpServers", {})["north-star"] = json.loads(args[4])
            path.write_text(json.dumps(saved))
        return subprocess.CompletedProcess(args, 0, "Added north-star", "")

    def test_codex_installs_once_and_verifies_real_server(self):
        self.assertEqual(self.connections.dispatch("agent_connection_status", self.parameters)["status"], "not_connected")
        self.assertEqual(self.connections.dispatch("connect_agent", self.parameters)["status"], "verified")
        self.assertEqual(self.installs, 1)
        self.assertEqual(self.connections.dispatch("connect_agent", self.parameters)["status"], "verified")
        self.assertEqual(self.installs, 1)

    def test_conflict_or_disabled_entry_is_never_overwritten(self):
        self.registration = {"type": "http", "url": "https://example.invalid/mcp"}
        self.assertEqual(self.connections.dispatch("connect_agent", self.parameters)["status"], "conflict")
        self.assertEqual(self.installs, 0)
        expected = self.connections.expected(self.parameters)
        self.assertFalse(self.connections.matches({**expected, "enabled": False}, expected))

    def test_missing_cli_does_not_try_to_install(self):
        self.connections.finder = lambda client: None
        self.assertEqual(self.connections.dispatch("connect_agent", self.parameters)["status"], "unavailable")
        self.assertEqual(self.installs, 0)

    def test_invalid_project_prevents_registration(self):
        result = self.connections.dispatch("connect_agent", {**self.parameters, "project_id": "missing"})
        self.assertEqual(result["status"], "error")
        self.assertEqual(self.installs, 0)

    def test_failed_write_is_not_reported_as_connected(self):
        self.failure = True
        self.assertEqual(self.connections.dispatch("connect_agent", self.parameters)["status"], "error")

    def test_readback_mismatch_is_not_reported_as_connected(self):
        self.bad_saved = True
        self.assertEqual(self.connections.dispatch("connect_agent", self.parameters)["status"], "error")

    def test_claude_installs_once_and_preserves_other_fixture_settings(self):
        path = self.home / ".claude.json"
        path.write_text(json.dumps({"theme": "dark", "mcpServers": {"other": {"command": "untouched"}}}))
        params = {**self.parameters, "client": "Claude Code"}
        with patch.dict(os.environ, {"CLAUDE_CONFIG_DIR": ""}):
            self.assertEqual(self.connections.dispatch("connect_agent", params)["status"], "verified")
            self.assertEqual(self.connections.dispatch("connect_agent", params)["status"], "verified")
        self.assertEqual(self.installs, 1)
        saved = json.loads(path.read_text())
        self.assertEqual(saved["theme"], "dark")
        self.assertEqual(saved["mcpServers"]["other"], {"command": "untouched"})

    def test_invalid_claude_json_is_never_modified(self):
        path = self.home / ".claude.json"
        path.write_text("{invalid")
        with patch.dict(os.environ, {"CLAUDE_CONFIG_DIR": ""}):
            self.assertEqual(self.connections.dispatch("connect_agent", {**self.parameters, "client": "Claude Code"})["status"], "error")
        self.assertEqual(path.read_text(), "{invalid")
        self.assertEqual(self.installs, 0)

    def test_timeout_returns_recoverable_error(self):
        def timeout(args, **kwargs):
            raise subprocess.TimeoutExpired(args, 25)
        self.connections.run = timeout
        self.assertEqual(self.connections.dispatch("connect_agent", self.parameters)["status"], "error")

    def test_mcp_clients_cannot_invoke_native_installer(self):
        response = rpc(self.store, {"jsonrpc": "2.0", "id": 1, "method": "tools/call", "params": {"name": "connect_agent", "arguments": self.parameters}})
        self.assertTrue(response["result"]["isError"])


if __name__ == "__main__":
    unittest.main()
