"""Local event store shared by the menu bar app and independent MCP processes."""
import contextlib
import datetime as dt
import json
import os
from pathlib import Path
import sqlite3
import uuid


KINDS = {"plan", "progress", "completed", "blocked", "decision", "knowledge", "idea", "suggestion"}
LEVELS = {"claimed", "verified", "ready"}
TASK_KINDS = {"plan", "progress", "completed", "blocked"}


def now():
    return dt.datetime.now(dt.timezone.utc).isoformat()


def required(data, key, limit=4000):
    value = data.get(key)
    if not isinstance(value, str) or not value.strip():
        raise ValueError(key + " must be a nonempty string")
    if len(value) > limit:
        raise ValueError(key + " is too long")
    return value.strip()


class Store:
    def __init__(self, directory=None):
        self.directory = Path(directory or os.environ.get("NORTH_STAR_HOME", Path(__file__).resolve().parents[1] / ".data"))
        self.directory.mkdir(parents=True, exist_ok=True, mode=0o700)
        self.path = self.directory / "north-star.sqlite3"
        with self.connect() as db:
            db.executescript("""
                PRAGMA journal_mode=WAL;
                CREATE TABLE IF NOT EXISTS projects (
                    id TEXT PRIMARY KEY, name TEXT NOT NULL, purpose TEXT NOT NULL,
                    goal TEXT NOT NULL, position INTEGER NOT NULL, created_at TEXT NOT NULL,
                    last_seen INTEGER NOT NULL DEFAULT 0
                );
                CREATE TABLE IF NOT EXISTS events (
                    seq INTEGER PRIMARY KEY AUTOINCREMENT, id TEXT UNIQUE NOT NULL,
                    project_id TEXT NOT NULL REFERENCES projects(id), agent TEXT NOT NULL,
                    event_key TEXT NOT NULL, kind TEXT NOT NULL, title TEXT NOT NULL,
                    detail TEXT NOT NULL, task_id TEXT NOT NULL, evidence TEXT NOT NULL,
                    verification TEXT NOT NULL, source TEXT NOT NULL, agreement TEXT NOT NULL,
                    created_at TEXT NOT NULL,
                    UNIQUE(project_id, agent, event_key)
                );
                CREATE TABLE IF NOT EXISTS thoughts (
                    id TEXT PRIMARY KEY, text TEXT NOT NULL, project_id TEXT REFERENCES projects(id),
                    status TEXT NOT NULL, category TEXT NOT NULL DEFAULT '',
                    reason TEXT NOT NULL DEFAULT '', created_at TEXT NOT NULL,
                    event_id TEXT, processing_at TEXT
                );
                CREATE TABLE IF NOT EXISTS settings (key TEXT PRIMARY KEY, value TEXT NOT NULL);
            """)
        os.chmod(self.path, 0o600)

    @contextlib.contextmanager
    def connect(self):
        db = sqlite3.connect(self.path, timeout=15)
        db.row_factory = sqlite3.Row
        db.execute("PRAGMA foreign_keys=ON")
        db.execute("PRAGMA busy_timeout=15000")
        try:
            with db:
                yield db
        finally:
            db.close()

    def settings(self):
        with self.connect() as db:
            values = dict(db.execute("SELECT key,value FROM settings").fetchall())
        return {"automatic": values.get("automatic", "false") == "true"}

    def set_settings(self, data):
        if not isinstance(data.get("automatic"), bool):
            raise ValueError("automatic must be a boolean")
        with self.connect() as db:
            db.execute("INSERT OR REPLACE INTO settings VALUES (?,?)", ("automatic", str(data["automatic"]).lower()))
        return self.settings()

    def seed(self):
        with self.connect() as db:
            db.execute("BEGIN IMMEDIATE")
            if db.execute("SELECT 1 FROM projects LIMIT 1").fetchone():
                return
            db.execute("INSERT INTO projects VALUES (?,?,?,?,?,?,?)", (
                "north-star", "North Star", "Regain project context in about a minute, while agents work in parallel.",
                "Try the first menu bar prototype with one real project.", 0, now(), 0))
            self._insert_event(db, {
                "project_id": "north-star", "agent": "Project brief", "event_key": "initial-intent",
                "kind": "decision", "title": "A quiet place to return to your projects",
                "detail": "A compact menu bar panel shows current state, changes, unfinished plans, and a few possible next steps. Project order stays stable. No daily reporting ritual.",
                "source": "PROJECT.md · September 20, 2026", "agreement": "Agreed project direction"})
            self._insert_event(db, {
                "project_id": "north-star", "agent": "Project brief", "event_key": "first-prototype",
                "kind": "plan", "task_id": "first-prototype", "title": "Try the complete return-to-project flow",
                "detail": "Open the panel, understand what changed, inspect a source, and capture a thought.",
                "source": "User request: lets build first prototype of project", "agreement": "User requested the first prototype."})

    def create_project(self, data):
        name = required(data, "name", 100)
        purpose = required(data, "purpose", 2000)
        goal = required(data, "goal", 1000)
        project_id = str(uuid.uuid4())
        with self.connect() as db:
            db.execute("BEGIN IMMEDIATE")
            position = db.execute("SELECT COALESCE(MAX(position), -1)+1 FROM projects").fetchone()[0]
            db.execute("INSERT INTO projects VALUES (?,?,?,?,?,?,0)", (project_id, name, purpose, goal, position, now()))
        return {"id": project_id}

    def _project(self, db, project_id):
        row = db.execute("SELECT * FROM projects WHERE id=?", (project_id,)).fetchone()
        if not row:
            raise ValueError("Unknown project")
        return dict(row)

    def _insert_event(self, db, data):
        project_id = required(data, "project_id", 100)
        self._project(db, project_id)
        fields = {
            "project_id": project_id, "agent": required(data, "agent", 100),
            "event_key": required(data, "event_key", 200), "kind": required(data, "kind", 30),
            "title": required(data, "title", 200), "detail": data.get("detail", ""),
            "task_id": data.get("task_id", ""), "evidence": data.get("evidence", "claimed"),
            "verification": data.get("verification", ""), "source": data.get("source", ""),
            "agreement": data.get("agreement", "")}
        for key, value in fields.items():
            if not isinstance(value, str) or len(value) > 12000:
                raise ValueError("Invalid " + key)
        if fields["kind"] not in KINDS or fields["evidence"] not in LEVELS:
            raise ValueError("Invalid kind or evidence level")
        if fields["kind"] in TASK_KINDS and not fields["task_id"].strip():
            raise ValueError("Task updates require a stable task_id")
        if fields["kind"] == "plan" and not fields["agreement"].strip():
            raise ValueError("Agreed plans require the user's agreement; use suggestion otherwise")
        if fields["evidence"] != "claimed" and (not fields["verification"].strip() or not fields["source"].strip()):
            raise ValueError("Verified or ready results require verification and a source")
        existing = db.execute("SELECT * FROM events WHERE project_id=? AND agent=? AND event_key=?", (
            project_id, fields["agent"], fields["event_key"])).fetchone()
        if existing:
            if any(existing[k] != v for k, v in fields.items()):
                raise ValueError("event_key already used for a different update")
            return {"id": existing["id"], "seq": existing["seq"], "duplicate": True}
        if fields["kind"] in {"progress", "completed", "blocked"}:
            plan = db.execute("SELECT 1 FROM events WHERE project_id=? AND task_id=? AND kind='plan'", (project_id, fields["task_id"])).fetchone()
            if not plan:
                raise ValueError("Record the agreed plan with this task_id before reporting its progress")
        event_id = str(uuid.uuid4())
        keys = ["id"] + list(fields) + ["created_at"]
        cursor = db.execute("INSERT INTO events (" + ",".join(keys) + ") VALUES (" + ",".join("?" for _ in keys) + ")", [event_id] + list(fields.values()) + [now()])
        return {"id": event_id, "seq": cursor.lastrowid, "duplicate": False}

    def report_update(self, data):
        with self.connect() as db:
            db.execute("BEGIN IMMEDIATE")
            return self._insert_event(db, data)

    def context(self, project_id, since=None):
        with self.connect() as db:
            db.execute("BEGIN")
            project = self._project(db, project_id)
            events = [dict(row) for row in db.execute("SELECT * FROM events WHERE project_id=? ORDER BY seq", (project_id,))]
        tasks = {}
        for event in events:
            if event["kind"] in TASK_KINDS:
                previous = tasks.get(event["task_id"])
                task = dict(event)
                task["outcome"] = previous["outcome"] if previous else event["title"]
                tasks[event["task_id"]] = task
        outstanding = [t for t in tasks.values() if t["kind"] != "completed"]
        completed = [t for t in tasks.values() if t["kind"] == "completed"]
        blocked = [t for t in outstanding if t["kind"] == "blocked"]
        threshold = project["last_seen"] if since is None else int(since)
        changes = [e for e in events if e["seq"] > threshold]
        suggestions = [dict(e) for e in events if e["kind"] == "suggestion"][-3:]
        if not suggestions:
            if blocked:
                t = blocked[0]
                suggestions.append({"id": "unblock", "title": "Unblock: " + t["outcome"], "detail": t["detail"] or "This is holding up the agreed plan.", "source": t["id"]})
            elif outstanding:
                t = outstanding[0]
                suggestions.append({"id": "continue", "title": t["outcome"], "detail": "Continue the agreed plan toward your nearest goal.", "source": t["id"]})
            elif completed:
                suggestions.append({"id": "review", "title": "Try the latest result yourself", "detail": "Check whether the completed work moves you closer to your goal.", "source": completed[-1]["id"]})
            else:
                suggestions.append({"id": "define", "title": "Choose the first outcome", "detail": "Agree one piece of work that brings your nearest goal closer.", "source": "Project goal"})
        latest = next((e for e in reversed(events) if e["kind"] in {"progress", "completed", "blocked"}), None)
        state = latest["title"] if latest else (outstanding[0]["outcome"] if outstanding else "Ready for the first plan")
        return {**project, "state": state, "events": list(reversed(events)), "changes": list(reversed(changes)),
                "tasks": outstanding, "completed": completed, "suggestions": suggestions,
                "knowledge": [e for e in reversed(events) if e["kind"] in {"decision", "knowledge", "idea"}],
                "snapshot": max((e["seq"] for e in events), default=0), "new_count": len(changes)}

    def list_projects(self):
        with self.connect() as db:
            ids = [r[0] for r in db.execute("SELECT id FROM projects ORDER BY position,created_at,id")]
        return [self.context(i) for i in ids]

    def mark_seen(self, data):
        project_id = required(data, "project_id", 100)
        snapshot = data.get("snapshot")
        if not isinstance(snapshot, int) or isinstance(snapshot, bool) or snapshot < 0:
            raise ValueError("snapshot must be a nonnegative integer")
        with self.connect() as db:
            self._project(db, project_id)
            maximum = db.execute("SELECT COALESCE(MAX(seq),0) FROM events WHERE project_id=?", (project_id,)).fetchone()[0]
            db.execute("UPDATE projects SET last_seen=MAX(last_seen,?) WHERE id=?", (min(snapshot, maximum), project_id))
        return {"ok": True}

    def capture_thought(self, data):
        text = required(data, "text", 12000)
        project_id = data.get("project_id") or None
        thought_id = str(uuid.uuid4())
        with self.connect() as db:
            if project_id:
                self._project(db, project_id)
            db.execute("INSERT INTO thoughts (id,text,project_id,status,created_at) VALUES (?,?,?,?,?)", (thought_id, text, project_id, "pending", now()))
        return {"id": thought_id, "status": "pending"}

    def list_thoughts(self):
        with self.connect() as db:
            return [dict(row) for row in db.execute("SELECT * FROM thoughts ORDER BY created_at DESC")]

    def resolve_thought(self, data):
        thought_id = required(data, "thought_id", 100)
        category = required(data, "category", 30)
        if category not in {"idea", "decision", "knowledge", "unclear"}:
            raise ValueError("Invalid thought category")
        reason = required(data, "reason", 2000)
        with self.connect() as db:
            db.execute("BEGIN IMMEDIATE")
            row = db.execute("SELECT * FROM thoughts WHERE id=?", (thought_id,)).fetchone()
            if not row:
                raise ValueError("Unknown thought")
            if row["status"] == "filed":
                return {"status": "filed", "id": thought_id, "duplicate": True}
            project_id = data.get("project_id") or row["project_id"]
            if row["project_id"] and project_id != row["project_id"]:
                raise ValueError("Keep the project explicitly selected by the user")
            if category == "unclear" or not project_id:
                db.execute("UPDATE thoughts SET status='needs_context',reason=?,processing_at=NULL WHERE id=?", (reason, thought_id))
                return {"status": "needs_context", "id": thought_id}
            self._project(db, project_id)
            title = required(data, "title", 200)
            # A note records intent. It never creates a task or marks work complete.
            event = self._insert_event(db, {
                "project_id": project_id, "agent": "You", "event_key": "thought:" + thought_id,
                "kind": category, "title": title, "detail": row["text"],
                "source": "Captured thought · " + row["created_at"],
                "agreement": reason if category == "decision" else ""})
            db.execute("UPDATE thoughts SET project_id=?,status='filed',category=?,reason=?,event_id=?,processing_at=NULL WHERE id=?", (project_id, category, reason, event["id"], thought_id))
        return {"status": "filed", "id": thought_id}

    def retry_thought(self, data):
        thought_id = required(data, "thought_id", 100)
        with self.connect() as db:
            row = db.execute("SELECT status FROM thoughts WHERE id=?", (thought_id,)).fetchone()
            if not row:
                raise ValueError("Unknown thought")
            if row["status"] == "filed":
                raise ValueError("Thought already filed")
            project_id = data.get("project_id")
            if project_id:
                self._project(db, project_id)
                db.execute("UPDATE thoughts SET project_id=? WHERE id=?", (project_id, thought_id))
            db.execute("UPDATE thoughts SET status='pending',reason='',processing_at=NULL WHERE id=?", (thought_id,))
        return {"ok": True}

    def snapshot(self):
        return {"projects": self.list_projects(), "thoughts": self.list_thoughts(), "settings": self.settings()}

    def dispatch(self, method, data):
        actions = {
            "snapshot": lambda d: self.snapshot(), "list_projects": lambda d: self.list_projects(),
            "get_context": lambda d: self.context(required(d, "project_id", 100)),
            "create_project": self.create_project, "report_update": self.report_update,
            "mark_seen": self.mark_seen, "capture_thought": self.capture_thought,
            "list_thoughts": lambda d: self.list_thoughts(), "resolve_thought": self.resolve_thought,
            "set_settings": self.set_settings, "retry_thought": self.retry_thought}
        if method not in actions:
            raise ValueError("Unknown action")
        return actions[method](data)
