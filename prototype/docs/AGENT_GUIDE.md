# Reporting to North Star

North Star helps the user return to a project in about a minute. Report what your work means for the product. Keep implementation details and evidence in the expandable detail.

Read `list_projects`, then `get_context` before working. Do not mark anything seen on the user's behalf.

## When to report

| Event | Tool and kind | Include |
| --- | --- | --- |
| The user agrees to work | `report_update`, `plan` | Outcome, stable task ID, relation to the goal, source of user agreement |
| Meaningful progress | `report_update`, `progress` | New capability and remaining work |
| Work completes | `report_update`, `completed` | Result, evidence level, exact checks, limitations, source |
| Work stops | `report_update`, `blocked` | What prevents progress and what would resolve it |
| A decision changes | `report_update`, `decision` | The explicit decision, why it changed, and its source |
| Important knowledge emerges | `report_update`, `knowledge` | Finding and implication for the goal |
| A possible direction appears | `report_update`, `idea` or `suggestion` | Possibility and reason; do not invent user agreement |

Do not report every command. Do not write a replacement summary of the whole project. Each report is one append-only event, and the app assembles the overview.

## Task IDs and retries

Choose a stable, project-wide task ID for one agreed outcome, such as `voice-capture`. Use it for its plan, progress, blockers, and completion. Report the plan before its results. Parallel agents should use distinct task IDs unless coordinating the same outcome. A later report for a task becomes its displayed state, while earlier reports remain in history.

Use a stable agent name and a unique `event_key` for each logical report. Retry with the same key and same payload. Reusing a key with different content is rejected.

## Evidence levels

- `claimed`: the agent reports completion; direct verification has not been supplied.
- `verified`: state exactly what was tested and provide an artifact or source.
- `ready`: the actual intended use was verified. Local tests alone are not enough if deployment, permissions, configuration, or a live dependency remains untested.

The app displays these labels, but cannot independently prove an agent's claim. `verified` and `ready` require both `verification` and `source` fields.

## Example report

```json
{
  "project_id": "north-star",
  "agent": "voice-worker",
  "event_key": "voice-capture:local-check:1",
  "kind": "completed",
  "task_id": "voice-capture",
  "title": "Spoken thoughts can be saved to the inbox",
  "detail": "English dictation was exercised on the test Mac. Ukrainian on-device availability still needs checking.",
  "evidence": "verified",
  "verification": "Recorded a phrase, inspected the transcript, saved it, and reopened the app.",
  "source": "/absolute/path/to/voice-test-report.md"
}
```

This is an illustrative payload, not a report of what the prototype has passed.

## Captured thoughts

Use `list_thoughts` and `resolve_thought` to interpret pending thoughts. Preserve the original wording and any explicitly selected project. Infer a project only when clear. Use `unclear` to leave an ambiguous thought in the inbox.

“Maybe we should try team access” is an idea. “I've decided to build team access first” is a decision. Never turn a tentative idea into an agreed task. The first prototype stores decisions in knowledge and history; changes to an agreed task still need a separate plan update with the user's authorization.

## Connecting

Open a project and choose **Agent setup**, or use **Settings → Set up an agent**. Choose your project and client. **Copy setup message for your agent** includes the client-specific installation instructions and a self-contained project instruction block. You can also copy the install command, JSON configuration, and project instructions separately. Cursor offers an install link.

For installed Codex and Claude Code clients, the app's **Connect** button registers North Star automatically and checks the saved connection. Existing matching entries are reused. Conflicting or disabled entries are left for review. The installer is a native-app action, not an MCP tool available to working agents.

Register the local MCP server once per agent app, then put the instructions for the correct project into that workspace's rules file. A running session may need to reload connections or restart before tools become available. Verify with `get_context`; do not claim a connection works just because configuration was saved.

The server is a local stdio process using Python 3 and the same SQLite database as the app. No HTTP port or API key is required for agent reports. Agents can report while the panel is closed or the app is not running. The configuration works on this Mac, and the server can access all local projects. The project ID guides reporting; it is not an access restriction.
