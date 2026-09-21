import Foundation
import SwiftUI

struct Update: Codable, Identifiable {
    let id: String
    let seq: Int
    let projectId: String
    let agent: String
    let kind: String
    let title: String
    let detail: String
    let evidence: String
    let verification: String
    let source: String
    let createdAt: String
    let outcome: String?

    var label: String {
        switch kind {
        case "plan": return "Planned"
        case "progress": return "In progress"
        case "blocked": return "Blocked"
        case "completed": return evidence == "ready" ? "Ready to use" : evidence == "verified" ? "Verified" : "Reported complete"
        case "decision": return "Decision"
        case "knowledge": return "Finding"
        case "idea": return "Idea"
        default: return "Suggestion"
        }
    }
    var icon: String {
        switch kind {
        case "completed": return evidence == "claimed" ? "checkmark.circle" : "checkmark.seal"
        case "blocked": return "pause.circle"
        case "progress": return "circle.lefthalf.filled"
        case "idea": return "lightbulb"
        case "decision": return "arrow.triangle.branch"
        case "knowledge": return "book.closed"
        default: return "circle.dashed"
        }
    }
    var tint: Color { kind == "blocked" ? Palette.amber : kind == "completed" ? Palette.accent : Palette.secondary }
}

struct Suggestion: Codable, Identifiable {
    let id: String
    let title: String
    let detail: String
    let source: String
}

struct Project: Codable, Identifiable {
    let id: String
    let name: String
    let purpose: String
    let goal: String
    let state: String
    let lastSeen: Int
    let snapshot: Int
    let newCount: Int
    let events: [Update]
    let changes: [Update]
    let tasks: [Update]
    let completed: [Update]
    let suggestions: [Suggestion]
    let knowledge: [Update]
}

struct Thought: Codable, Identifiable {
    let id: String
    let text: String
    let projectId: String?
    let status: String
    let category: String
    let reason: String
    let createdAt: String
}

struct AppSettings: Codable { var automatic: Bool }
struct AgentConnection: Decodable {
    let status: String
    let message: String
}
struct Snapshot: Codable {
    var projects: [Project]
    var thoughts: [Thought]
    var settings: AppSettings
    static var empty: Snapshot { Snapshot(projects: [], thoughts: [], settings: AppSettings(automatic: false)) }
}

enum Palette {
    static let background = Color(red: 0.980, green: 0.980, blue: 0.973)
    static let surface = Color.white
    static let elevated = Color(red: 0.942, green: 0.949, blue: 0.934)
    static let text = Color(red: 0.137, green: 0.165, blue: 0.149)
    static let secondary = Color(red: 0.392, green: 0.427, blue: 0.404)
    static let accent = Color(red: 0.204, green: 0.384, blue: 0.310)
    static let accentWash = Color(red: 0.926, green: 0.950, blue: 0.930)
    static let amber = Color(red: 0.569, green: 0.345, blue: 0.102)
    static let line = Color(red: 0.875, green: 0.894, blue: 0.871)
}

final class AppModel: ObservableObject {
    @Published var globalShortcutAvailable = false
    @Published var snapshot = Snapshot.empty
    @Published var page = "projects"
    @Published var projectTab = "Overview"
    @Published var selectedID: String?
    @Published var boundary = 0
    @Published var captureProject = ""
    @Published var draft = ""
    @Published var error: String?
    @Published var toast: String?
    @Published var busy = false
    @Published var agentConnections: [String: AgentConnection] = [:]
    @Published var connectingAgents: Set<String> = []
    private var navigation: [String] = []
    var visible = false
    private var lastDisplayed = 0
    private var refreshing = false
    private let queue = DispatchQueue(label: "north-star.storage", qos: .userInitiated)
    private let connectionQueue = DispatchQueue(label: "north-star.connections", qos: .userInitiated)
    private var timer: Timer?
    private var worker: Process?
    let dataDirectory: String
    let backendDirectory: String
    let agentServerPath: String
    let python: String

    init() {
        let info = Bundle.main.infoDictionary ?? [:]
        let developmentDirectory = info["NorthStarProjectDirectory"] as? String
        let resources = Bundle.main.resourcePath!
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("North Star", isDirectory: true).path
        dataDirectory = ProcessInfo.processInfo.environment["NORTH_STAR_HOME"]
            ?? developmentDirectory.map { $0 + "/.data" } ?? support
        backendDirectory = resources + "/backend"
        agentServerPath = developmentDirectory.map { $0 + "/backend/bridge.py" }
            ?? backendDirectory + "/bridge.py"
        python = info["NorthStarPython"] as? String ?? resources + "/python/bin/north-star-python"
        refresh()
        startWorker()
        timer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in self?.refresh() }
    }

    var selected: Project? { snapshot.projects.first { $0.id == selectedID } }
    var inboxCount: Int { snapshot.thoughts.filter { $0.status != "filed" }.count }

    private func call(_ method: String, _ params: [String: Any]) throws -> Data {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: python)
        process.arguments = [backendDirectory + "/bridge.py"]
        var env = ProcessInfo.processInfo.environment
        env["NORTH_STAR_HOME"] = dataDirectory
        env["PYTHONDONTWRITEBYTECODE"] = "1"
        process.environment = env
        let input = Pipe(), output = Pipe()
        process.standardInput = input
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice
        try process.run()
        let request = try JSONSerialization.data(withJSONObject: ["method": method, "params": params])
        input.fileHandleForWriting.write(request)
        try input.fileHandleForWriting.close()
        let data = output.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] ?? [:]
        if let error = object["error"] as? String { throw NSError(domain: "NorthStar", code: 1, userInfo: [NSLocalizedDescriptionKey: error]) }
        guard let result = object["result"] else { throw NSError(domain: "NorthStar", code: 2, userInfo: [NSLocalizedDescriptionKey: "Could not read local project data."]) }
        return try JSONSerialization.data(withJSONObject: result)
    }

    func refresh() {
        guard !refreshing else { return }
        refreshing = true
        queue.async { [weak self] in
            guard let self else { return }
            do {
                let data = try self.call("snapshot", [:])
                let decoder = JSONDecoder()
                decoder.keyDecodingStrategy = .convertFromSnakeCase
                let snapshot = try decoder.decode(Snapshot.self, from: data)
                DispatchQueue.main.async {
                    self.snapshot = snapshot
                    if self.visible && self.page == "project", let project = self.selected { self.lastDisplayed = project.snapshot }
                    self.refreshing = false
                }
            } catch {
                DispatchQueue.main.async { self.error = error.localizedDescription; self.refreshing = false }
            }
        }
    }

    func perform(_ method: String, _ params: [String: Any], completion: (() -> Void)? = nil) {
        busy = true
        queue.async { [weak self] in
            guard let self else { return }
            do {
                _ = try self.call(method, params)
                DispatchQueue.main.async { self.busy = false; self.error = nil; completion?(); self.refresh() }
            } catch {
                DispatchQueue.main.async { self.busy = false; self.error = error.localizedDescription }
            }
        }
    }

    func open(_ project: Project) {
        selectedID = project.id
        projectTab = "Overview"
        boundary = project.lastSeen
        lastDisplayed = project.snapshot
        navigation = ["projects"]
        page = "project"
    }

    func navigate(to destination: String) {
        guard page != destination else { return }
        if page == "project" { remember() }
        navigation.append(page)
        page = destination
    }

    func showRoot(_ destination: String) {
        remember()
        navigation = []
        selectedID = nil
        page = destination
    }

    var backLabel: String {
        switch navigation.last ?? "projects" {
        case "project": return selected?.name ?? "Project"
        case "inbox": return "Inbox"
        case "settings": return "Settings"
        case "agentSetup": return "Agent setup"
        default: return "Projects"
        }
    }

    func remember() {
        guard let id = selectedID, lastDisplayed > 0 else { return }
        perform("mark_seen", ["project_id": id, "snapshot": lastDisplayed])
    }

    func back() {
        if page == "project" { remember(); selectedID = nil }
        page = navigation.popLast() ?? "projects"
    }

    func capture() {
        guard page != "capture" else { return }
        if draft.isEmpty { captureProject = selectedID ?? "" }
        navigate(to: "capture")
    }

    func saveThought() {
        let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        var params: [String: Any] = ["text": text]
        if !captureProject.isEmpty { params["project_id"] = captureProject }
        perform("capture_thought", params) {
            self.draft = ""
            self.back()
            self.showToast(self.snapshot.settings.automatic ? "Thought saved. Finding its place…" : "Thought saved to your inbox.")
        }
    }

    func showToast(_ text: String) {
        toast = text
        DispatchQueue.main.asyncAfter(deadline: .now() + 4) { if self.toast == text { self.toast = nil } }
    }

    func closed() {
        remember()
        visible = false
        if page != "capture" && page != "new" { selectedID = nil; navigation = []; page = "projects" }
    }

    func startWorker() {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: python)
        process.arguments = [backendDirectory + "/processor.py"]
        var env = ProcessInfo.processInfo.environment
        env["NORTH_STAR_HOME"] = dataDirectory
        env["PYTHONDONTWRITEBYTECODE"] = "1"
        env["PATH"] = "/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:"
            + (env["PATH"] ?? "")
        process.environment = env
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        do { try process.run(); worker = process }
        catch { self.error = "Automatic sorting could not start. Thoughts can still be saved." }
    }

    func shutdown() { timer?.invalidate(); worker?.terminate() }

    func agentSetup(for project: Project) -> AgentSetup {
        AgentSetup(python: python, serverPath: agentServerPath,
                   dataDirectory: dataDirectory, projectID: project.id, projectName: project.name,
                   purpose: project.purpose, goal: project.goal)
    }

    func connectAgent(_ client: AgentClient, project: Project, install: Bool) {
        guard [.codex, .claude].contains(client), !connectingAgents.contains(client.id) else { return }
        connectingAgents.insert(client.id)
        let params: [String: Any] = ["client": client.rawValue, "project_id": project.id,
                                    "python": python, "server_path": agentServerPath]
        connectionQueue.async { [weak self] in
            guard let self else { return }
            let result: AgentConnection
            do {
                let data = try self.call(install ? "connect_agent" : "agent_connection_status", params)
                result = try JSONDecoder().decode(AgentConnection.self, from: data)
            } catch { result = AgentConnection(status: "error", message: error.localizedDescription) }
            DispatchQueue.main.async {
                self.agentConnections[client.id] = result
                self.connectingAgents.remove(client.id)
            }
        }
    }

    func copy(_ text: String, confirmation: String) {
        NSPasteboard.general.clearContents()
        if NSPasteboard.general.setString(text, forType: .string) { showToast(confirmation) }
        else { error = "The text could not be copied. Please try again." }
    }
}
