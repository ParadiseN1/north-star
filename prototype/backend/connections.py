"""Native-app-only MCP registration through the installed clients' own CLIs."""
import fcntl
import json
import os
from pathlib import Path
import shutil
import subprocess


class ConnectionProblem(Exception):
    pass


class Connections:
    def __init__(self, directory, home=None, runner=subprocess.run, finder=None):
        self.directory = Path(directory).resolve()
        self.home = Path(home) if home else Path.home()
        self.run = runner
        self.finder = finder or self.find_binary

    def find_binary(self, client):
        name = "codex" if client == "Codex" else "claude"
        candidates = [shutil.which(name), str(self.home / ".local/bin" / name),
                      "/opt/homebrew/bin/" + name, "/usr/local/bin/" + name]
        if client == "Codex":
            candidates.append("/Applications/Codex.app/Contents/Resources/codex")
        for candidate in candidates:
            if candidate and Path(candidate).is_file() and os.access(candidate, os.X_OK):
                return str(Path(candidate).resolve())
        return None

    def command(self, args, timeout=25, **kwargs):
        try:
            return self.run(args, cwd=self.home, capture_output=True, text=True,
                            timeout=timeout, **kwargs)
        except subprocess.TimeoutExpired:
            raise ConnectionProblem("The agent did not respond in time. Check its setup and try again.")
        except OSError:
            raise ConnectionProblem("The agent could not be started. Check that its command-line tool is installed.")

    def expected(self, data):
        python = data.get("python")
        server = data.get("server_path")
        for path in (python, server):
            if not isinstance(path, str) or not Path(path).is_absolute() or not Path(path).is_file():
                raise ConnectionProblem("North Star's local server files could not be found. Rebuild or reopen the app.")
        return {"command": python, "args": [server, "--mcp"], "env": {"NORTH_STAR_HOME": str(self.directory)}}

    def read_registration(self, client, binary):
        if client == "Codex":
            result = self.command([binary, "mcp", "get", "north-star", "--json"])
            if result.returncode:
                if "No MCP server named 'north-star' found" in result.stderr + result.stdout:
                    return None
                raise ConnectionProblem("Codex could not read its MCP settings. Open its settings to check the configuration.")
            try:
                value = json.loads(result.stdout)
                transport = value.get("transport", value)
                if not isinstance(transport, dict):
                    raise ValueError()
                return {**transport, "enabled": value.get("enabled", True)}
            except (ValueError, AttributeError):
                raise ConnectionProblem("This Codex version returned an unfamiliar configuration. Use the manual setup options.")
        # Claude's get command has human-readable output, so inspect only the named
        # entry in its documented user file. Its CLI remains the only writer.
        if os.environ.get("CLAUDE_CONFIG_DIR"):
            raise ConnectionProblem("Claude uses a custom settings directory. Use the manual setup command for this configuration.")
        path = self.home / ".claude.json"
        try:
            settings = json.loads(path.read_text()) if path.exists() else {}
            override = settings.get("projects", {}).get(str(self.home), {}).get("mcpServers", {}).get("north-star")
            if override is not None:
                raise ConnectionProblem("Claude has a project-scoped North Star override in your home folder. Resolve that entry before using automatic setup.")
            value = settings.get("mcpServers", {}).get("north-star")
            if value is not None and not isinstance(value, dict):
                raise ValueError()
            return value
        except (OSError, ValueError, AttributeError):
            raise ConnectionProblem("Claude's settings could not be read safely. Check its configuration before connecting.")

    @staticmethod
    def matches(existing, expected):
        if existing.get("enabled", True) is not True or existing.get("type", "stdio") != "stdio":
            return False
        if existing.get("env_vars") or existing.get("cwd"):
            return False
        return (existing.get("command") == expected["command"]
                and existing.get("args", []) == expected["args"]
                and (existing.get("env") or {}) == expected["env"])

    def inspect(self, client, expected):
        binary = self.finder(client)
        if not binary:
            return None, None, {"status": "unavailable", "message": "Install " + client + " with its command-line tool, then try again."}
        existing = self.read_registration(client, binary)
        if existing is not None and not self.matches(existing, expected):
            return binary, existing, {"status": "conflict", "message": "An existing north-star entry in " + client + " differs from this app or is disabled. It has not been changed. Review it in your agent's settings."}
        if existing is not None:
            return binary, existing, {"status": "configured", "message": "North Star is already registered in " + client + ". Verify it to check that the local server responds."}
        return binary, None, {"status": "not_connected", "message": "Connect once to make North Star available to " + client + " on this Mac."}

    def verify_server(self, configuration, project_id):
        requests = [
            {"jsonrpc": "2.0", "id": 1, "method": "initialize", "params": {"protocolVersion": "2025-06-18", "capabilities": {}, "clientInfo": {"name": "north-star-setup", "version": "0.1"}}},
            {"jsonrpc": "2.0", "method": "notifications/initialized"},
            {"jsonrpc": "2.0", "id": 2, "method": "tools/list"},
            {"jsonrpc": "2.0", "id": 3, "method": "tools/call", "params": {"name": "get_context", "arguments": {"project_id": project_id}}}]
        result = self.command([configuration["command"], *configuration["args"]], timeout=15,
                              env={**os.environ, **configuration["env"]},
                              input="\n".join(json.dumps(r) for r in requests) + "\n")
        try:
            responses = {r["id"]: r for r in map(json.loads, result.stdout.splitlines())}
            valid = (result.returncode == 0
                     and responses[1]["result"]["serverInfo"]["name"] == "north-star"
                     and "report_update" in {t["name"] for t in responses[2]["result"]["tools"]}
                     and not responses[3]["result"].get("isError", False))
            context = json.loads(responses[3]["result"]["content"][0]["text"])
            if not valid or context["id"] != project_id:
                raise ValueError()
        except (ValueError, KeyError, IndexError, TypeError):
            raise ConnectionProblem("The MCP server did not return this project's context. Check the local server and try again.")

    def dispatch(self, method, data):
        client = data.get("client")
        if client not in {"Codex", "Claude Code"}:
            raise ValueError("Automatic setup supports Codex and Claude Code")
        try:
            expected = self.expected(data)
            if method == "agent_connection_status":
                return self.inspect(client, expected)[2]
            if method != "connect_agent":
                raise ValueError("Unknown connection action")
            project_id = data.get("project_id")
            if not isinstance(project_id, str) or not project_id:
                raise ConnectionProblem("Choose a project before connecting.")
            self.directory.mkdir(parents=True, exist_ok=True, mode=0o700)
            with (self.directory / "agent-connections.lock").open("a") as lock:
                # Avoid overlapping installs from multiple North Star app instances.
                try:
                    fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
                except BlockingIOError:
                    raise ConnectionProblem("Another connection setup is in progress. Try again in a moment.")
                binary, existing, status = self.inspect(client, expected)
                if status["status"] in {"conflict", "unavailable"}:
                    return status
                # Validate the server before writing any client configuration.
                self.verify_server(expected, project_id)
                if existing is None:
                    if client == "Codex":
                        arguments = [binary, "mcp", "add", "north-star", "--env", "NORTH_STAR_HOME=" + str(self.directory), "--", expected["command"], *expected["args"]]
                    else:
                        arguments = [binary, "mcp", "add-json", "north-star", json.dumps({"type": "stdio", **expected}), "--scope", "user"]
                    result = self.command(arguments)
                    if result.returncode:
                        raise ConnectionProblem(client + " could not save the connection. Its configuration may need attention; use the manual setup options.")
                saved = self.read_registration(client, binary)
                if saved is None or not self.matches(saved, expected):
                    raise ConnectionProblem("The saved connection does not match North Star. Review your agent's settings before retrying.")
                self.verify_server(saved, project_id)
                return {"status": "verified", "message": "Registered in " + client + "; the MCP server returned this project's context. Start a new agent session or reload MCP connections to use its tools."}
        except ConnectionProblem as error:
            return {"status": "error", "message": str(error)}
