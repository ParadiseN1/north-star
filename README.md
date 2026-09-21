# North Star

A native macOS menu bar app that helps you return to a project with its current goal, recent changes, unfinished plans, and suggested next steps in view. Working agents report updates through a local MCP server. You can also capture thoughts by typing or dictation.

The current implementation is a prototype for Apple Silicon Macs running macOS 14 or later. It uses SwiftUI and AppKit with a Python standard-library backend and a local SQLite database.

## Build and run

Install Xcode command-line tools, then run from this repository:

```sh
cd prototype
/usr/bin/python3 scripts/build.py
open 'build/North Star.app'
```

Click the menu bar icon or press Control-Option-N to open the panel. The development build records the checkout location, so rebuild after moving the project.

## Test

From `prototype/`:

```sh
/usr/bin/python3 -m unittest discover -s tests -v
```

## Package

From `prototype/`, run `/usr/bin/python3 scripts/package.py` to build an installable DMG with a bundled Python runtime. The prototype is ad-hoc signed and is not Apple-notarized. See the [prototype guide](prototype/README.md) for installation and agent setup.

## Project files

- [Project brief](PROJECT.md): product direction and original scope.
- [Prototype guide](prototype/README.md): setup, capabilities, and implementation limits.
- [Agent reporting guide](prototype/docs/AGENT_GUIDE.md): MCP reporting rules and evidence levels.
- [Design notes](prototype/docs/DESIGN.md): layout, navigation, and keyboard shortcuts.

Personal databases, local validation artifacts, and built applications are excluded from Git. Development data lives in `prototype/.data/`; installed-app data lives in `~/Library/Application Support/North Star`.
