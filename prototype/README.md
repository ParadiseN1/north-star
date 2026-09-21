# North Star · first prototype

A native macOS menu bar app for returning to your projects. It opens a compact panel with stable project order, changes since the last visit, unfinished agreed work, completed results, suggested next steps, and expandable sources.

## Run

Open `build/North Star.app`. Click the sparkle in the macOS menu bar to reopen the panel. The app runs without a Dock icon. Press Control–Option–N from any app, or reopen North Star through Spotlight, to open a separate panel below the menu bar. This works even when the menu bar icon is hidden by the camera notch. Settings contains Quit. Only one copy runs per user; opening another copy brings the existing one forward.

To rebuild on this Apple Silicon Mac with Xcode command-line tools:

```sh
/usr/bin/python3 scripts/build.py
open 'build/North Star.app'
```

The development build uses SwiftUI, AppKit, Speech, AVFoundation, and the system Python standard library. It records this checkout and Python path, so rebuild if you move the project.

## Installable DMG

```sh
/usr/bin/python3 scripts/package.py
```

This creates `dist/North-Star-0.0.1-arm64.dmg` and a SHA-256 checksum. Drag the app into Applications and launch it there. It requires an Apple Silicon Mac with macOS 14 or later. This prototype is ad-hoc signed, not Apple-notarized; installation instructions are included in the image.

The release bundles a checksum-pinned [standalone CPython runtime](https://github.com/astral-sh/python-build-standalone/releases/tag/20260901), its license notices, and the backend. It needs no separate Python or Xcode installation. The initial packaging build downloads the runtime; subsequent builds reuse the verified local cache. `build.py --release` builds only the portable app in `build/release/`.

Installed-app data lives in `~/Library/Application Support/North Star`, outside the app bundle. No development database is packaged or automatically imported. Existing development MCP connections remain unchanged; the installed app reports a conflict if a client still points to the checkout. Install in a permanent location before using agent setup. See `packaging/Install.txt` for switching from a development connection.

Run `scripts/verify_release.py '/path/to/North Star.app'` to check the installed bundle's signature, MCP tools, data persistence, and relocation using isolated temporary data.

## Try it

1. Open North Star. The seeded project reflects the real project brief, not fabricated agent activity.
2. Open a project and expand an update to see its explanation and source.
3. Return to the project list. That viewed snapshot is remembered automatically.
4. Capture a typed thought. Leave the project unset if you'd like it routed later.
5. In Settings, optionally enable automatic sorting through your installed, signed-in Codex CLI. Thoughts and project descriptions are sent to OpenAI; this uses the account's Codex allowance. Original notes remain locally available if processing fails.
6. Open a project and choose **Agent setup**, or use **Settings → Set up an agent**. Choose the project and your agent app.
7. For Codex or Claude Code, click **Connect**. North Star uses the installed client's own command-line tool to register the local server, reads back the saved entry, and requests this project's context through MCP. A matching existing entry is reused; a conflicting entry is left unchanged. Cursor opens its own install confirmation.
8. Choose **Copy agent instructions** for the project's rules file. **Copy setup message for your agent** remains available if you'd like the agent to help merge those instructions or configure another client.

## Agent setup

Each project's **Copy agent instructions** button produces a self-contained Markdown section with the project's name, ID, purpose, goal, reporting events, task IDs, retries, evidence rules, and thought-handling rules. Paste it into the instruction file the agent reads. The conventional file is `AGENTS.md` for Codex and `CLAUDE.md` for Claude Code; other clients may use their own rules format. Preserve the existing instructions.

Register North Star once per agent app on this Mac. A project-specific registration is not required. Codex and Claude Code have automatic **Connect** buttons plus copyable install commands. The automatic installer detects missing client tools, validates the local MCP server before registering it, and reports failed or mismatched configurations. Existing conflicting or disabled entries require review in the agent's settings. It uses the client CLI to write settings; it does not rewrite those files itself. Claude installations with a custom `CLAUDE_CONFIG_DIR` use the manual setup path in this prototype.

Cursor has an install link that opens its own confirmation. Other local MCP clients get a JSON configuration that may need their client's wrapper. The setup message checks for an existing server before adding one and preserves unrelated instructions.

Registration changes the client's configuration. A running agent may need to reload MCP connections or start a new session before the tools appear. Verify by calling `get_context` with the copied project ID. The connection has access to all projects in the local store; the project instructions select the intended destination, not an access boundary. Hosted agents need a remote MCP connection, which this prototype does not implement.

Automatic setup registers MCP. It does not install missing agent applications, change their permissions, or edit repository instruction files. Use the project's copy action for those instructions. [Validation reports](evidence/README.md) are kept locally and excluded from Git.

Client setup references: [Codex MCP](https://learn.chatgpt.com/docs/extend/mcp?surface=cli), [Claude Code MCP](https://code.claude.com/docs/en/mcp), [Cursor install links](https://cursor.com/docs/mcp/install-links).

## Implemented boundaries

- SQLite transactions preserve individual updates from simultaneous agent processes. Retry keys prevent duplicate reports.
- Agents record plans before their results. Suggestions and ideas do not create tasks.
- Reported complete, verified, and ready to use remain distinct evidence states. These are agent-reported levels, not independent certification.
- The overview is a deterministic projection of reports. Model-written summaries and conflicting-decision resolution are not part of this first build.
- Optional Codex processing classifies a thought and routes it to a project. A decision is recorded in knowledge; changing project goals or turning a decision into tasks is a future step.
- Unclear thoughts stay in the inbox. You can choose a project and retry, or keep a thought as an idea.
- Dictation requests microphone and Speech permissions only when you click Speak. It requires on-device recognition for the selected language. Unsupported languages show a typing fallback. It does not upload audio or store recordings.
- There is no background auto-discovery of other apps, authentication service, cloud sync, or launch-at-login setup.

## Files and data

- `assets/`: app icon, PNG preview, and macOS icon sizes. `scripts/draw_icon.swift` is the editable vector master; the build regenerates the icon when that source changes.
- `native/`: menu bar app and dictation.
- `backend/store.py`: shared SQLite store and context projection.
- `backend/bridge.py`: UI bridge and seven stdio MCP tools.
- `backend/processor.py`: optional serial thought interpreter.
- `backend/connections.py`: local client registration and MCP connection checks, available only through the native UI bridge.
- `.data/`: private local runtime data, excluded from source control.
- `tests/`: storage, concurrency, unread-state, and MCP transport checks.

Set `NORTH_STAR_HOME` to use a separate data directory for tests or a different local installation. The native app polls for updates every two seconds. Automatic thought processing runs while the app is open. The MCP server works independently.

```sh
/usr/bin/python3 -m unittest discover -s tests -v
```

Implementation references: [MCP stdio transport](https://modelcontextprotocol.io/specification/2025-06-18/basic/transports), [Codex non-interactive mode](https://learn.chatgpt.com/docs/non-interactive-mode), [Apple on-device speech recognition](https://developer.apple.com/documentation/speech/sfspeechrecognitionrequest/requiresondevicerecognition).
