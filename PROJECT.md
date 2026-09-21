# North Star

Working project description based on the discussion on September 20, 2026. The direction is established; the data model and implementation details remain open.

## Purpose

The app helps a person regain project context while juggling work and several personal projects, with agents carrying out many tasks in parallel.

The core experience: open a project and, in roughly a minute, understand where it is heading, where it stands, what has been done, and what could come next. One minute is a design target.

The product selects the information that matters when returning to a project. It maintains a concise, current overview, with details available when needed.

Maintaining context must require no manual reports, mandatory summary approvals, or end-of-session rituals. Users can optionally record thoughts as they arise.

## Main interface

The initial interface is a macOS menu bar app. Clicking its icon opens a compact panel.

The first screen lists projects. Each entry shows a name, a short line describing its current state, and an indicator for new updates when applicable. Projects stay in a stable order; agent activity does not automatically rearrange them.

Clicking a project opens a brief product overview:

- The current state and nearest goal.
- What has been completed and what has changed since the last visit.
- What remains unfinished in the agreed plan.
- A few suggested next steps, with brief explanations.

The overview leads with product outcomes, such as the ability to capture thoughts by voice. Individual technical tasks and details can be expanded within it.

The app automatically remembers the last state the user viewed so it can highlight new changes. The summary provides access to the explanations, decisions, and sources behind it.

## Project context

The proposed components are:

- Intent: the product description, intended users, purpose, overall goal, and nearest goal.
- Current state: what is available, planned, in progress, and blocked.
- Knowledge and decisions: important findings, reasons behind the chosen direction, and the user's ideas.
- Update history: what changed and why, with references to relevant sources or work results.

Tasks may be internal entities that agents use to track the plan. The exact model is still undecided.

The summary should explain what the work means for the product and how it relates to the goal. A list of technical actions alone does not restore human context.

## Information sources

### Updates from working agents through MCP

Agents write updates through MCP themselves. They need a clear guide defining when to report, what to send, and which format to use.

Each agent submits individual changes from its own work. The app combines them into the current state and overall summary, allowing multiple agents to contribute without overwriting each other's context.

The proposed reporting guide starts with:

| Event | What to report |
| --- | --- |
| Work is agreed | The planned outcome and how it relates to the project goal |
| Work is completed or stopped | The result, what was verified, remaining work, and blockers |
| A plan or decision changes | What changed and why |
| Important knowledge is gained | What was learned and how it affects the project |

Both plans and results must be recorded. Completion reports alone cannot reveal what remains unfinished in the plan.

The app must distinguish an agent's completion claim, a verified result, and readiness for actual use. Suggested next steps must also remain distinct from the agreed plan.

### Voice capture from the user

The recording button is immediately available in the panel. Selecting a project before recording is optional.

The user records a thought. The audio is transcribed, then an agent identifies the relevant project and decides how to use the message: save an idea, add knowledge, record a decision, or update the context or plan.

Tentative ideas and decisions must remain distinct. "Maybe we should try team access" is stored as an idea. "I've decided to build team access first" changes the plan. A passing thought must not automatically become a commitment.

## Scope boundaries

The user chooses which project to work on. Prioritizing across projects is outside the app's scope.

The app takes limited product initiative by suggesting next steps based on the goal and current state. Independently directing the project or actively challenging its strategy is outside the current scope.

## Open questions

- The final entities, fields, and information categories.
- The exact layout and length of the project overview.
- The MCP tool definitions and complete agent reporting guide.
- How to handle ambiguous voice notes and conflicting or missing updates.
- The technical implementation and scope of the first version.
