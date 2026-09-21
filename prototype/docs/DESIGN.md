# North Star design

The panel should help you understand a project in about a minute. Its visual hierarchy follows that job: choose a project, read its current state and nearest goal, scan recent changes, then look at the remaining plan. Evidence and setup controls are available when needed.

## Visual language

Warm off-white canvas, white surfaces, dark green-black text, and a muted forest-green accent. Color identifies actions, selection, new updates and evidence states. Amber identifies blockers or errors. Labels carry the same meaning without relying on color.

Use the macOS system font, regular and medium weights for reading, and semibold for headings. Page titles are 23–25 points, body text 13–15, and supporting labels 11–12. Layout uses 22-point outer margins and a consistent spacing scale. Corners are modest. Borders separate groups; individual updates use dividers instead of separate cards.

North Star uses light appearance even when macOS is dark. Controls show focus, hover, pressed and disabled states. Disclosure animation respects Reduce Motion.

## Navigation

Projects and Inbox are the two root destinations. Project order remains stable as reports arrive. Each row shows a name, current state and count of unseen changes. The nearest goal lives in the project overview.

Inside a project, Overview, Knowledge and History stay visible while content scrolls. Current state leads; the goal follows. Plans, completed outcomes and suggestions remain distinct. Verification text is explicitly agent-reported. Project purpose and source detail expand on demand.

Back names and returns to the previous destination. Settings and agent setup preserve their entry path. Capture remains at the bottom of browsing screens, and returns to its origin after saving. Capture drafts survive closing the panel.

Keyboard shortcuts: Command-1 for Projects, Command-2 for Inbox, Command-K for capture, Command-N for a project, Command-comma for Settings, Command-[ for Back, and Command-Return to save a thought or create a project.

## Secondary screens

Capture offers an optional project, a focused writing area, and a voice alternative. Empty submissions are visibly disabled. The inbox separates thoughts waiting to be sorted from all original thoughts.

Agent setup is two steps: connect the app, then copy project instructions. Manual commands, configuration and previews sit behind disclosures. A saved connection and a connection checked through MCP remain distinguishable.

## Scope

This redesign changes the native interface and navigation. The project store, MCP reporting semantics, thought processing and speech recognition remain the existing implementation. Test content belongs in the isolated design QA store, never in the user's project data.
