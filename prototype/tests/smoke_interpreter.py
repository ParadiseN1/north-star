"""Explicit live provider smoke check. Synthetic data only; not part of unit tests."""
import json
from pathlib import Path
import sys
import tempfile
sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "backend"))
from store import Store
from processor import process_one

with tempfile.TemporaryDirectory(prefix="north-star-smoke-") as directory:
    store = Store(directory)
    store.create_project({"name": "Paper Moon", "purpose": "A fictional reading list app for this test", "goal": "Test a reading list"})
    store.create_project({"name": "Garden Log", "purpose": "A fictional plant watering app for this test", "goal": "Track watering"})
    store.set_settings({"automatic": True})
    store.capture_thought({"text": "Maybe Paper Moon could let people tag their books by mood. Just an idea, not a decision."})
    process_one(store)
    thought = store.list_thoughts()[0]
    print(json.dumps({"status": thought["status"], "category": thought["category"], "reason": thought["reason"]}, indent=2))
    assert thought["status"] == "filed", "Live interpreter did not file the synthetic thought"
    assert thought["category"] == "idea", "Tentative note must remain an idea"
    project = store.context(thought["project_id"])
    assert project["name"] == "Paper Moon", "Thought routed to the wrong project"
    assert not project["tasks"], "Thought unexpectedly created a commitment"
    print("PASS: real Codex interpretation routed a synthetic thought and preserved it as an idea.")
