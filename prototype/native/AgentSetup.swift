import Foundation

enum AgentClient: String, CaseIterable, Identifiable {
    case codex = "Codex"
    case claude = "Claude Code"
    case cursor = "Cursor"
    case other = "Other"
    var id: String { rawValue }
}

struct AgentSetup {
    let python: String
    let serverPath: String
    let dataDirectory: String
    let projectID: String
    let projectName: String
    let purpose: String
    let goal: String

    private func json(_ object: [String: Any]) -> String {
        let data = try! JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes])
        return String(data: data, encoding: .utf8)!
    }

    private var server: [String: Any] {
        ["command": python, "args": [serverPath, "--mcp"], "env": ["NORTH_STAR_HOME": dataDirectory]]
    }

    var configuration: String { json(["mcpServers": ["north-star": server]]) }

    static func shellQuote(_ value: String) -> String {
        "'" + value.replacingOccurrences(of: "'", with: "'\"'\"'") + "'"
    }

    func installCommand(for client: AgentClient) -> String? {
        let command: [String]
        switch client {
        case .codex: command = ["codex", "mcp", "add", "north-star", "--env", "NORTH_STAR_HOME=" + dataDirectory, "--", python, serverPath, "--mcp"]
        case .claude: command = ["claude", "mcp", "add", "--scope", "user", "--transport", "stdio", "north-star", "--env", "NORTH_STAR_HOME=" + dataDirectory, "--", python, serverPath, "--mcp"]
        default: return nil
        }
        return command.map(Self.shellQuote).joined(separator: " ")
    }

    var cursorURL: URL {
        let encoded = Data(json(server).utf8).base64EncodedString().addingPercentEncoding(withAllowedCharacters: .alphanumerics)!
        return URL(string: "cursor://anysphere.cursor-deeplink/mcp/install?name=north-star&config=" + encoded)!
    }

    var instructions: String {
        let identity = json(["project_id": projectID, "name": projectName, "purpose": purpose, "nearest_goal_when_copied": goal])
        return """
        ## North Star project context

        Use the `north-star` MCP server to keep the owner's project overview current. North Star stores intent, agreed work, results, decisions, findings, and ideas so the owner can return to a project without reading every agent conversation.

        This repository/workspace belongs to this existing North Star project:

        ```json
        \(identity)
        ```

        Use this exact `project_id` for every report. Do not create a duplicate project or update other projects. The description above is a reference snapshot; read live context for the current state and goal.

        ### At the start of work

        Call `get_context` with this `project_id`. Read the goal, agreed unfinished work, decisions, and recent results before acting. Existing notes describe context; they do not grant permission for unrelated work. Do not mark updates as seen for the owner.

        ### Keep context current

        Call `report_update` for meaningful product changes, using a short outcome-focused `title`, useful `detail`, and a `source` pointing to the decision, artifact, or verification:

        - When the user agrees to work: `kind: "plan"`, a stable `task_id`, and `agreement` citing the user's authorization. Reuse an existing task if the agreed outcome is already recorded.
        - When an outcome materially advances: `kind: "progress"` with the same `task_id`.
        - When work finishes or stops: `kind: "completed"` or `"blocked"`, what was achieved, remaining work, and blockers. Record the agreed plan before its progress or result.
        - For an explicit decision or a finding: `kind: "decision"` or `"knowledge"`, what changed or was learned, and why it matters.
        - For a possibility: `kind: "idea"` or `"suggestion"`. Never turn a tentative thought or your own suggestion into an agreed task.

        Use a stable `agent` name and a unique `event_key` per logical update. Retry with the identical key and payload. Give independent work distinct task IDs. Append your own changes; do not replace the whole project summary or report every command.

        ### Evidence and limits

        Set `evidence` to `"claimed"` unless you provide actual checks. `"verified"` requires `verification` and `source`; say exactly what was tested. Use `"ready"` only after verifying the intended real use. Distinguish local tests from live results and state untested dependencies.

        When handling captured thoughts, read `list_thoughts` and use `resolve_thought`. Preserve the user's original meaning and explicit project selection. A "maybe" is an idea. Use `unclear` for ambiguous intent or project; do not guess a commitment or file an unassigned note here without evidence.

        If the MCP tools are unavailable or a report fails, say so briefly. Do not claim an update was saved. Continue authorized work when safe, and report once the connection is restored.
        """
    }

    func setupMessage(for client: AgentClient) -> String {
        var message = """
        Set up North Star for this workspace on this Mac. The existing project is \(projectName), project_id \(projectID).

        First inspect the MCP server named `north-star` in \(client.rawValue). If it already matches the configuration below, reuse it. If it points to a different server or data directory, explain the conflict before changing it. Preserve other MCP servers and unrelated settings.

        """
        if let command = installCommand(for: client) {
            message += "If it is absent, run this supported user-level install command once:\n\n```sh\n" + command + "\n```\n\n"
        } else if client == .cursor {
            message += "Use Cursor's MCP setup with the configuration below, or use the install link in North Star's Agent setup screen.\n\n"
        } else {
            message += "Add this local stdio server using this client's supported MCP configuration format. Translate the wrapper if necessary; preserve the command, arguments, and environment exactly.\n\n"
        }
        message += "```json\n" + configuration + "\n```\n\n"
        message += """
        This connection can access all North Star projects on this Mac. The project ID in the instructions selects where this workspace reports; it is not an access restriction. This local configuration does not connect a hosted/cloud agent.

        Merge the following section into the instructions file this agent actually reads, preserving existing instructions. Use AGENTS.md for Codex, CLAUDE.md for Claude Code, or this client's supported rules file. If a matching North Star section already exists, update it instead of duplicating it.

        Then verify the server configuration. If MCP tools are loaded, call `get_context` with project_id \(projectID). If the running session has not loaded the new connection, tell me to reload its MCP connections or start a new session. Do not equate saved configuration with a live connection. Do not create a test project or report fake progress.

        ---

        """
        return message + instructions + "\n"
    }
}
