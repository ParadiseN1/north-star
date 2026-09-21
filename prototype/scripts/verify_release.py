#!/usr/bin/env python3
"""Check a relocated release bundle with temporary data and its bundled runtime."""
import argparse
import json
import os
from pathlib import Path
import plistlib
import subprocess
import tempfile


def verify(app):
    app = app.resolve()
    resources = app / "Contents/Resources"
    python = resources / "python/bin/north-star-python"
    server = resources / "backend/bridge.py"
    info = plistlib.loads((app / "Contents/Info.plist").read_bytes())
    assert "NorthStarProjectDirectory" not in info
    assert "NorthStarPython" not in info
    assert not list(app.rglob("*.sqlite3")), "A private database must not enter the installer"
    for entry in app.rglob("*"):
        if entry.is_symlink():
            assert app in entry.resolve().parents, "A bundle symlink escapes the installed app"
    check_signature = ["/usr/bin/codesign", "--verify", "--deep", "--strict", str(app)]
    subprocess.run(check_signature, check=True)
    with tempfile.TemporaryDirectory(prefix="north-star-dmg-data-") as data:
        # Leave Python's normal bytecode setting alone to test the MCP entry point.
        env = {k: v for k, v in os.environ.items() if not k.startswith("PYTHON")}
        env.update(NORTH_STAR_HOME=data, PATH="/usr/bin:/bin")
        messages = [
            {"jsonrpc": "2.0", "id": 1, "method": "initialize", "params": {"protocolVersion": "2025-06-18"}},
            {"jsonrpc": "2.0", "method": "notifications/initialized"},
            {"jsonrpc": "2.0", "id": 2, "method": "tools/list"},
            {"jsonrpc": "2.0", "id": 3, "method": "tools/call", "params": {
                "name": "get_context", "arguments": {"project_id": "north-star"}}},
            {"jsonrpc": "2.0", "id": 4, "method": "tools/call", "params": {
                "name": "capture_thought", "arguments": {"text": "DMG packaging verification"}}},
        ]
        result = subprocess.run([str(python), str(server), "--mcp"], cwd="/", env=env,
            input="".join(json.dumps(message) + "\n" for message in messages),
            text=True, capture_output=True, timeout=30, check=True)
        replies = [json.loads(line) for line in result.stdout.splitlines()]
        assert len(replies) == 4, result.stdout
        assert all("error" not in reply and not reply["result"].get("isError") for reply in replies)
        assert len(replies[1]["result"]["tools"]) == 7
        context = json.loads(replies[2]["result"]["content"][0]["text"])
        assert context["id"] == "north-star"
        # A second process reads the same note, as the native app does on reopening.
        result = subprocess.run([str(python), str(server)], cwd="/", env=env,
            input=json.dumps({"method": "snapshot", "params": {}}),
            text=True, capture_output=True, timeout=30, check=True)
        snapshot = json.loads(result.stdout)["result"]
        assert any(note["text"] == "DMG packaging verification" for note in snapshot["thoughts"])
        assert Path(data, "north-star.sqlite3").stat().st_mode & 0o777 == 0o600
    assert not list((resources / "backend").rglob("__pycache__"))
    subprocess.run(check_signature, check=True)
    print("PASS: relocated bundle, private temporary storage, seven MCP tools, persistent capture, unchanged signature")


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("app", type=Path)
    verify(parser.parse_args().app)
