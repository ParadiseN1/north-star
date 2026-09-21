import concurrent.futures
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "backend"))
from store import Store
from bridge import rpc
from processor import process_one


class StoreTests(unittest.TestCase):
    def setUp(self):
        self.directory = tempfile.TemporaryDirectory()
        self.addCleanup(self.directory.cleanup)
        self.store = Store(self.directory.name)
        self.store.seed()

    def report(self, **kwargs):
        return self.store.report_update({"project_id": "north-star", "agent": "test-agent", "event_key": "test", "kind": "knowledge", "title": "A useful finding", **kwargs})

    def test_concurrent_agents_preserve_all_updates_and_idempotency(self):
        def write(i):
            store = Store(self.directory.name)
            return store.report_update({"project_id": "north-star", "agent": "agent-" + str(i), "event_key": "done", "kind": "knowledge", "title": "Finding " + str(i)})
        with concurrent.futures.ThreadPoolExecutor(max_workers=8) as pool:
            results = list(pool.map(write, range(32)))
        self.assertEqual(len({r["id"] for r in results}), 32)
        self.assertEqual(len(self.store.context("north-star")["events"]), 34)
        self.assertTrue(write(0)["duplicate"])
        self.assertEqual(len(self.store.context("north-star")["events"]), 34)

    def test_retry_key_cannot_silently_change_history(self):
        self.report()
        with self.assertRaises(ValueError):
            self.report(title="Different meaning")

    def test_seen_snapshot_does_not_swallow_update_arriving_after_view(self):
        viewed = self.store.context("north-star")
        added = self.report()
        self.store.mark_seen({"project_id": "north-star", "snapshot": viewed["snapshot"]})
        current = self.store.context("north-star")
        self.assertEqual([c["id"] for c in current["changes"]], [added["id"]])
        self.store.mark_seen({"project_id": "north-star", "snapshot": 0})
        self.assertEqual(self.store.context("north-star")["last_seen"], viewed["snapshot"])

    def test_read_only_context_does_not_mark_seen(self):
        self.store.context("north-star")
        self.store.list_projects()
        self.assertEqual(self.store.context("north-star")["last_seen"], 0)

    def test_verified_results_require_evidence_and_existing_plan(self):
        with self.assertRaises(ValueError):
            self.report(kind="completed", task_id="unknown", evidence="verified", source="tests", verification="Passed")
        with self.assertRaises(ValueError):
            self.report(kind="completed", task_id="first-prototype", evidence="verified")
        self.report(kind="completed", task_id="first-prototype", evidence="verified", source="test report", verification="Exercised the core flow")
        context = self.store.context("north-star")
        self.assertFalse(context["tasks"])
        self.assertEqual(context["completed"][0]["evidence"], "verified")

    def test_claimed_completion_is_not_promoted_to_verified(self):
        self.report(kind="completed", task_id="first-prototype")
        self.assertEqual(self.store.context("north-star")["completed"][0]["evidence"], "claimed")

    def test_suggestions_do_not_become_agreed_tasks(self):
        self.report(kind="suggestion", title="Try team access")
        self.assertEqual(len(self.store.context("north-star")["tasks"]), 1)
        with self.assertRaises(ValueError):
            self.report(kind="plan", task_id="team-access", event_key="plan")

    def test_idea_preserves_original_and_does_not_create_commitment(self):
        text = "Maybe we should add team access to North Star."
        thought = self.store.capture_thought({"text": text})
        self.store.resolve_thought({"thought_id": thought["id"], "project_id": "north-star", "category": "idea", "title": "Consider team access", "reason": "Tentative idea"})
        self.assertEqual(self.store.list_thoughts()[0]["text"], text)
        self.assertEqual(len(self.store.context("north-star")["tasks"]), 1)
        self.assertEqual(self.store.context("north-star")["knowledge"][0]["kind"], "idea")

    def test_ambiguous_project_stays_in_inbox(self):
        thought = self.store.capture_thought({"text": "Maybe we should rethink that."})
        self.store.resolve_thought({"thought_id": thought["id"], "category": "unclear", "reason": "No project is identifiable"})
        self.assertEqual(self.store.list_thoughts()[0]["status"], "needs_context")
        self.assertEqual(len(self.store.context("north-star")["events"]), 2)

    def test_explicit_project_cannot_be_rerouted_by_interpreter(self):
        another = self.store.create_project({"name": "Other", "purpose": "Other purpose", "goal": "Other goal"})
        thought = self.store.capture_thought({"text": "Maybe team access", "project_id": "north-star"})
        with self.assertRaises(ValueError):
            self.store.resolve_thought({"thought_id": thought["id"], "project_id": another["id"], "category": "idea", "title": "Team access", "reason": "Guess"})

    def test_project_order_stays_stable_after_updates(self):
        second = self.store.create_project({"name": "Second", "purpose": "Purpose", "goal": "Goal"})
        self.report(project_id=second["id"])
        self.assertEqual([p["name"] for p in self.store.list_projects()], ["North Star", "Second"])

    def test_restart_preserves_thoughts_and_seen_state(self):
        thought = self.store.capture_thought({"text": "An idea"})
        self.store.mark_seen({"project_id": "north-star", "snapshot": 2})
        reopened = Store(self.directory.name)
        reopened.seed()
        self.assertEqual(reopened.list_thoughts()[0]["id"], thought["id"])
        self.assertEqual(reopened.context("north-star")["new_count"], 0)

    def test_processing_is_opt_in_and_failure_keeps_original(self):
        thought = self.store.capture_thought({"text": "A note"})
        def fail(store, note):
            raise ValueError("Provider unavailable")
        self.assertFalse(process_one(self.store, fail))
        self.store.set_settings({"automatic": True})
        self.assertTrue(process_one(self.store, fail))
        saved = self.store.list_thoughts()[0]
        self.assertEqual(saved["text"], "A note")
        self.assertEqual(saved["status"], "needs_context")
        self.assertEqual(saved["reason"], "Provider unavailable")
        self.assertEqual(saved["id"], thought["id"])

    def test_stdio_mcp_initialization_call_and_error_recovery(self):
        messages = [
            {"jsonrpc": "2.0", "id": 1, "method": "initialize", "params": {"protocolVersion": "2025-06-18"}},
            {"jsonrpc": "2.0", "method": "notifications/initialized"},
            {"jsonrpc": "2.0", "id": 2, "method": "tools/list"},
            {"jsonrpc": "2.0", "id": 3, "method": "tools/call", "params": {"name": "report_update", "arguments": {"project_id": "north-star", "agent": "wire-test", "event_key": "wire", "kind": "knowledge", "title": "Arrived over MCP"}}},
            {"jsonrpc": "2.0", "id": 4, "method": "tools/call", "params": {"name": "report_update", "arguments": {}}}]
        payload = "\n".join(json.dumps(m) for m in messages) + "\n{broken\n"
        process = subprocess.run([sys.executable, str(Path(__file__).resolve().parents[1] / "backend/bridge.py"), "--mcp"],
            input=payload, text=True, capture_output=True, env={**os.environ, "NORTH_STAR_HOME": self.directory.name}, timeout=15)
        self.assertEqual(process.returncode, 0, process.stderr)
        replies = [json.loads(line) for line in process.stdout.splitlines()]
        self.assertEqual(len(replies), 5)
        self.assertEqual(replies[0]["result"]["protocolVersion"], "2025-06-18")
        self.assertEqual(len(replies[1]["result"]["tools"]), 7)
        self.assertFalse(replies[2]["result"]["isError"])
        self.assertTrue(replies[3]["result"]["isError"])
        self.assertEqual(replies[4]["error"]["code"], -32700)
        self.assertEqual(self.store.context("north-star")["events"][0]["title"], "Arrived over MCP")

    def test_invalid_rpc_does_not_crash(self):
        for request in [None, [], {}, {"jsonrpc": "2.0", "id": 1, "method": "tools/call", "params": []}]:
            self.assertIn("error", rpc(self.store, request))


if __name__ == "__main__":
    unittest.main()
