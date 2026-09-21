import AppKit
import SwiftUI

struct AgentSetupView: View {
    @ObservedObject var model: AppModel
    @State private var projectID = ""
    @State private var client = AgentClient.codex
    @State private var showInstructions = false
    @State private var showManual = false
    private var project: Project? { model.snapshot.projects.first { $0.id == projectID } }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                PageIntro(title: "Connect your agent", subtitle: "Bring its plans and progress into North Star.")
                VStack(alignment: .leading, spacing: 14) {
                    Picker("Project", selection: $projectID) {
                        ForEach(model.snapshot.projects) { Text($0.name).tag($0.id) }
                    }.font(.system(size: 13))
                    Picker("Agent", selection: $client) {
                        ForEach(AgentClient.allCases) { Text($0.rawValue).tag($0) }
                    }.pickerStyle(.segmented).labelsHidden()
                }
                if let project {
                    let setup = model.agentSetup(for: project)
                    VStack(alignment: .leading, spacing: 13) {
                        SectionHeading(title: "1. Connect \(client.rawValue)", trailing: "Once per app")
                        if client == .codex || client == .claude {
                            AgentConnectionView(model: model, client: client, project: project).id(client.id + project.id)
                        } else if client == .cursor {
                            Button {
                                if !NSWorkspace.shared.open(setup.cursorURL) { model.error = "Cursor could not be opened. Install Cursor, or use the manual setup below." }
                            } label: { Label("Add to Cursor…", systemImage: "arrow.up.right.square") }.buttonStyle(ActionButtonStyle())
                            Text("Opens Cursor's install confirmation. Finish the connection there.").font(.system(size: 12)).foregroundStyle(Palette.secondary)
                        } else {
                            Button { model.copy(setup.configuration, confirmation: "MCP configuration copied.") } label: { Label("Copy MCP configuration", systemImage: "curlybraces") }
                                .buttonStyle(ActionButtonStyle())
                            Text("Add this to your local agent app's MCP settings.").font(.system(size: 12)).foregroundStyle(Palette.secondary)
                        }
                    }
                    Hairline()
                    VStack(alignment: .leading, spacing: 12) {
                        SectionHeading(title: "2. Give it project context")
                        Text("Copy the instructions for \(project.name) into your agent's rules file. Keep any existing instructions.")
                            .font(.system(size: 13)).foregroundStyle(Palette.secondary).lineSpacing(3)
                        Button {
                            model.copy(setup.instructions, confirmation: "Instructions for \(project.name) copied.")
                        } label: { Label("Copy agent instructions", systemImage: "doc.on.doc") }.buttonStyle(ActionButtonStyle(primary: false))
                        Text("Use AGENTS.md for Codex or CLAUDE.md for Claude Code.")
                            .font(.system(size: 11)).foregroundStyle(Palette.secondary)
                        DisclosureGroup("Preview instructions", isExpanded: $showInstructions) {
                            Text(setup.instructions).font(.system(size: 12)).textSelection(.enabled).foregroundStyle(Palette.secondary)
                                .frame(maxWidth: .infinity, alignment: .leading).padding(.top, 10)
                        }.font(.system(size: 12)).foregroundStyle(Palette.secondary)
                    }
                    Hairline()
                    DisclosureGroup("More setup options", isExpanded: $showManual) {
                        VStack(alignment: .leading, spacing: 15) {
                            Button {
                                model.copy(setup.setupMessage(for: client), confirmation: "Setup message for \(client.rawValue) copied.")
                            } label: { Label("Copy setup message for your agent", systemImage: "doc.on.clipboard") }
                            Text("Paste into a chat with your agent for help adding the connection and project instructions.")
                                .font(.system(size: 12)).foregroundStyle(Palette.secondary).lineSpacing(3)
                            if let command = setup.installCommand(for: client) {
                                Button { model.copy(command, confirmation: "\(client.rawValue) install command copied.") } label: { Label("Copy install command", systemImage: "terminal") }
                            }
                            Button { model.copy(setup.configuration, confirmation: "MCP configuration copied.") } label: { Label("Copy MCP configuration", systemImage: "curlybraces") }
                            DisclosureGroup("Connection details") {
                                Text(setup.installCommand(for: client) ?? setup.configuration)
                                    .font(.system(size: 11, design: .monospaced)).textSelection(.enabled)
                                    .foregroundStyle(Palette.secondary).frame(maxWidth: .infinity, alignment: .leading).padding(.top, 8)
                            }
                        }.font(.system(size: 12, weight: .medium)).foregroundStyle(Palette.accent).padding(.top, 14)
                    }.font(.system(size: 12, weight: .medium)).foregroundStyle(Palette.secondary)
                    Text("The connection can access all projects on this Mac. Instructions tell the agent where to report. Hosted agents need a remote connection, which isn't available yet.")
                        .font(.system(size: 11)).foregroundStyle(Palette.secondary).lineSpacing(3)
                } else {
                    EmptyState(symbol: "folder.badge.plus", title: "Start with a project", detail: "Create a project so your agent knows where to send its updates.")
                    Button("Create a project") { model.navigate(to: "new") }.buttonStyle(ActionButtonStyle())
                }
            }.padding(22)
        }.onAppear { projectID = model.selectedID ?? model.snapshot.projects.first?.id ?? "" }
    }
}

struct AgentConnectionView: View {
    @ObservedObject var model: AppModel
    let client: AgentClient
    let project: Project
    private var connection: AgentConnection? { model.agentConnections[client.id] }
    private var working: Bool { model.connectingAgents.contains(client.id) }
    private var blocked: Bool { ["conflict", "unavailable"].contains(connection?.status ?? "") }
    private var checked: Bool { connection?.status == "verified" }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let connection {
                if checked {
                    DisclosureGroup {
                        Text(connection.message).font(.system(size: 12)).foregroundStyle(Palette.secondary).lineSpacing(3).padding(.top, 8)
                    } label: {
                        Label("Configured and checked", systemImage: "checkmark.circle.fill")
                            .font(.system(size: 13, weight: .medium)).foregroundStyle(Palette.accent)
                    }
                } else {
                    Text(connection.message).font(.system(size: 12)).lineSpacing(3).foregroundStyle(blocked ? Palette.amber : Palette.secondary)
                }
            }
            Button { model.connectAgent(client, project: project, install: true) } label: {
                HStack(spacing: 9) {
                    if working { ProgressView().controlSize(.small) }
                    else { Image(systemName: checked ? "arrow.clockwise" : "link") }
                    Text(working ? "Checking connection…" : checked || connection?.status == "configured" ? "Verify connection" : "Connect \(client.rawValue)")
                }
            }.buttonStyle(ActionButtonStyle(primary: !checked)).disabled(working || blocked)
            if blocked || connection?.status == "error" {
                Button("Check setup again") { model.connectAgent(client, project: project, install: false) }
                    .font(.system(size: 12, weight: .medium)).foregroundStyle(Palette.accent).disabled(working)
            }
            Text(checked ? "Reload your agent's connections or start a new session to use the tools." : "Adds North Star to your local \(client.rawValue) settings.")
                .font(.system(size: 12)).foregroundStyle(Palette.secondary).lineSpacing(3)
        }.onAppear { model.connectAgent(client, project: project, install: false) }
    }
}
