import SwiftUI
import AppKit

struct CaptureView: View {
    @ObservedObject var model: AppModel
    @StateObject private var voice = VoiceInput()
    @State private var beforeVoice = ""
    @FocusState private var writing: Bool
    private var canSave: Bool {
        !model.draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !model.busy && !voice.authorizing && !voice.recording
    }
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                PageIntro(title: "Capture a thought", subtitle: "An idea, a decision, or something you learned.")
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Text("Project").font(.system(size: 12, weight: .medium)).foregroundStyle(Palette.secondary)
                        Spacer()
                        Picker("Project", selection: $model.captureProject) {
                            Text("Decide later").tag("")
                            ForEach(model.snapshot.projects) { Text($0.name).tag($0.id) }
                        }.labelsHidden().frame(maxWidth: 270)
                    }
                    ZStack(alignment: .topLeading) {
                        TextEditor(text: $model.draft).font(.system(size: 15)).lineSpacing(4)
                            .scrollContentBackground(.hidden).padding(10).frame(height: 205)
                            .disabled(voice.recording || voice.authorizing).focused($writing).accessibilityLabel("Your thought")
                        if model.draft.isEmpty {
                            Text("What's on your mind?").font(.system(size: 15)).foregroundStyle(Palette.secondary)
                                .padding(.horizontal, 15).padding(.vertical, 18).allowsHitTesting(false)
                        }
                    }.background(Palette.surface, in: RoundedRectangle(cornerRadius: 10))
                        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(writing || voice.recording ? Palette.accent.opacity(0.65) : Palette.line))
                    HStack(spacing: 10) {
                        Button {
                            if voice.recording { voice.stop() }
                            else { beforeVoice = model.draft; voice.start() }
                        } label: {
                            Label(voice.authorizing ? "Allow access…" : voice.recording ? "Stop recording" : "Speak instead",
                                  systemImage: voice.recording ? "stop.circle.fill" : "mic")
                                .font(.system(size: 13, weight: .medium)).foregroundStyle(Palette.accent)
                        }.disabled(voice.authorizing)
                        Spacer()
                        Picker("Dictation language", selection: $voice.language) {
                            Text("English").tag("en-US")
                            Text("Українська").tag("uk-UA")
                        }.labelsHidden().frame(width: 120).disabled(voice.recording || voice.authorizing)
                    }.padding(.top, 3)
                    if let error = voice.error {
                        Text(error).font(.system(size: 12)).foregroundStyle(Palette.amber).fixedSize(horizontal: false, vertical: true)
                    }
                    Text(voice.recording ? "Listening on this Mac…" : "Voice transcription stays on this Mac when supported.")
                        .font(.system(size: 11)).foregroundStyle(Palette.secondary)
                }
                VStack(spacing: 12) {
                    Button { voice.stop(); model.saveThought() } label: {
                        HStack {
                            Spacer()
                            Text(model.busy ? "Saving…" : "Save thought")
                            Spacer()
                            Text("⌘ ↵").font(.system(size: 11)).opacity(0.75)
                        }
                    }.buttonStyle(ActionButtonStyle())
                        .disabled(!canSave)
                        .keyboardShortcut(.return, modifiers: .command)
                    Text(model.snapshot.settings.automatic ? "Codex will find its place. Your original words are kept." : "Saved to your inbox. You can sort it whenever you're ready.")
                        .font(.system(size: 12)).foregroundStyle(Palette.secondary).multilineTextAlignment(.center).lineSpacing(3)
                }
            }.padding(22)
        }.onAppear { writing = true }
            .onChange(of: voice.transcript) { _, value in
                model.draft = beforeVoice + (beforeVoice.isEmpty || value.isEmpty ? "" : "\n") + value
            }.onDisappear { voice.stop() }
            .onReceive(NotificationCenter.default.publisher(for: Notification.Name("NorthStarPanelClosed"))) { _ in voice.stop() }
            .onReceive(NotificationCenter.default.publisher(for: Notification.Name("NorthStarSubmit"))) { _ in
                if canSave { voice.stop(); model.saveThought() }
            }
    }
}

struct NewProjectView: View {
    @ObservedObject var model: AppModel
    @State private var name = ""
    @State private var purpose = ""
    @State private var goal = ""
    @FocusState private var focusedField: Int?
    private var canCreate: Bool {
        ![name, purpose, goal].contains { $0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty } && !model.busy
    }
    private func createProject() {
        guard canCreate else { return }
        model.perform("create_project", ["name": name, "purpose": purpose, "goal": goal]) { model.showRoot("projects") }
    }
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                PageIntro(title: "A new project", subtitle: "Start with what matters. The details can follow.")
                field("Project name", placeholder: "A name you'll recognize", text: $name, number: 0)
                field("Purpose", placeholder: "What are you building, and for whom?", text: $purpose, number: 1)
                field("Nearest goal", placeholder: "The next outcome you want to reach", text: $goal, number: 2)
                Button(action: createProject) { Text(model.busy ? "Creating…" : "Create project") }
                    .buttonStyle(ActionButtonStyle()).keyboardShortcut(.return, modifiers: .command)
                    .disabled(!canCreate)
            }.padding(22)
        }.onAppear { focusedField = 0 }
            .onReceive(NotificationCenter.default.publisher(for: Notification.Name("NorthStarSubmit"))) { _ in createProject() }
    }
    private func field(_ title: String, placeholder: String, text: Binding<String>, number: Int) -> some View {
        VStack(alignment: .leading, spacing: 9) {
            Text(title).font(.system(size: 13, weight: .medium))
            TextField(placeholder, text: text, axis: .vertical).textFieldStyle(.plain).font(.system(size: 14))
                .lineLimit(number == 0 ? 1...2 : 2...4).focused($focusedField, equals: number).accessibilityLabel(title)
                .padding(13).background(Palette.surface, in: RoundedRectangle(cornerRadius: 9))
                .overlay(RoundedRectangle(cornerRadius: 9).strokeBorder(focusedField == number ? Palette.accent.opacity(0.65) : Palette.line))
        }
    }
}

struct SettingsView: View {
    @ObservedObject var model: AppModel
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 26) {
                PageIntro(title: "Settings", subtitle: "Thoughts, agents and local data.")
                VStack(alignment: .leading, spacing: 12) {
                    SectionHeading(title: "Open North Star", trailing: model.globalShortcutAvailable ? "⌃⌥N" : "Spotlight")
                    Text(model.globalShortcutAvailable
                         ? "Press Control–Option–N from any app to open North Star below the menu bar. You can also open it from Spotlight."
                         : "Open North Star from Spotlight if its menu bar icon is hidden. The Control–Option–N shortcut is unavailable, possibly because another app uses it.")
                        .font(.system(size: 13)).foregroundStyle(Palette.secondary).lineSpacing(3)
                }
                Hairline()
                VStack(alignment: .leading, spacing: 13) {
                    SectionHeading(title: "Thoughts")
                    HStack {
                        Text("Sort thoughts automatically").font(.system(size: 14))
                        Spacer()
                        Toggle("Sort thoughts automatically", isOn: Binding(get: { model.snapshot.settings.automatic }, set: { model.perform("set_settings", ["automatic": $0]) }))
                            .labelsHidden().toggleStyle(.switch).controlSize(.small).disabled(model.busy)
                    }
                    Text("Uses your signed-in Codex account to sort thoughts into projects. Sends the thought and project descriptions to OpenAI, using your Codex allowance. Audio stays on this Mac.")
                        .font(.system(size: 13)).foregroundStyle(Palette.secondary).lineSpacing(3)
                    Text("Unclear thoughts stay in the inbox. Ideas stay separate from agreed plans.")
                        .font(.system(size: 12)).foregroundStyle(Palette.secondary).lineSpacing(3)
                }
                Hairline()
                VStack(alignment: .leading, spacing: 12) {
                    SectionHeading(title: "Agents")
                    Text("Connect once, then give each agent the instructions for its project.")
                        .font(.system(size: 13)).foregroundStyle(Palette.secondary).lineSpacing(3)
                    Button { model.navigate(to: "agentSetup") } label: {
                        HStack { Label("Set up an agent", systemImage: "link"); Spacer(); Image(systemName: "chevron.right").font(.system(size: 10)) }
                    }.buttonStyle(ActionButtonStyle(primary: false))
                }
                Hairline()
                VStack(alignment: .leading, spacing: 12) {
                    SectionHeading(title: "On this Mac", trailing: "Prototype 0.1")
                    Text("Projects, thoughts and history are saved locally. The overview reflects agent reports; North Star does not verify their claims itself.")
                        .font(.system(size: 13)).foregroundStyle(Palette.secondary).lineSpacing(3)
                    Button { NSWorkspace.shared.open(URL(fileURLWithPath: model.dataDirectory)) } label: { Label("Show local data", systemImage: "folder") }
                        .font(.system(size: 12, weight: .medium)).foregroundStyle(Palette.accent)
                }
                Hairline()
                HStack {
                    Text("North Star").font(.system(size: 12)).foregroundStyle(Palette.secondary)
                    Spacer()
                    Button("Quit North Star") { NSApp.terminate(nil) }.font(.system(size: 12)).foregroundStyle(Palette.secondary)
                }
            }.padding(22)
        }
    }
}

struct InboxView: View {
    @ObservedObject var model: AppModel
    @State private var filter = "To sort"
    private var thoughts: [Thought] {
        filter == "To sort" ? model.snapshot.thoughts.filter { $0.status != "filed" } : model.snapshot.thoughts
    }
    var body: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 20) {
                PageIntro(title: "Thought inbox", subtitle: "A place for things you don't want to lose.")
                TabStrip(items: ["To sort", "All thoughts"], selected: $filter)
            }.padding(.horizontal, 22).padding(.top, 22)
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    if thoughts.isEmpty {
                        EmptyState(symbol: "tray", title: filter == "To sort" ? "All clear" : "Your thoughts start here",
                                   detail: filter == "To sort" ? "Nothing waiting to be sorted. Capture a thought whenever it comes to you." : "Ideas, decisions and observations, kept in your own words.")
                    }
                    ForEach(thoughts) { thought in ThoughtRow(model: model, thought: thought) }
                }.padding(22)
            }.id(filter)
        }
    }
}

struct ThoughtRow: View {
    @ObservedObject var model: AppModel
    let thought: Thought
    @State private var projectID = ""
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Tag(text: status, color: thought.status == "filed" ? Palette.accent : Palette.secondary)
                Spacer()
                Text(String(thought.createdAt.prefix(10))).font(.system(size: 11)).foregroundStyle(Palette.secondary)
            }
            Text(thought.text).font(.system(size: 14)).lineSpacing(3).textSelection(.enabled)
            if let project = model.snapshot.projects.first(where: { $0.id == thought.projectId }) {
                Label(project.name, systemImage: "folder").font(.system(size: 12)).foregroundStyle(Palette.secondary)
            }
            if !thought.reason.isEmpty { Text(thought.reason).font(.system(size: 12)).foregroundStyle(Palette.secondary).lineSpacing(3) }
            if thought.status == "needs_context" || (thought.status == "pending" && !model.snapshot.settings.automatic) {
                Hairline()
                Picker("Project", selection: $projectID) {
                    Text("Choose a project").tag("")
                    ForEach(model.snapshot.projects) { Text($0.name).tag($0.id) }
                }.font(.system(size: 12))
                HStack {
                    Button("Keep as an idea") {
                        model.perform("resolve_thought", ["thought_id": thought.id, "project_id": projectID, "category": "idea", "title": String(thought.text.prefix(160)), "reason": "Saved as an idea by you."])
                    }.disabled(projectID.isEmpty || model.busy).foregroundStyle(Palette.accent)
                    Spacer()
                    if model.snapshot.settings.automatic {
                        Button("Retry sorting") { model.perform("retry_thought", ["thought_id": thought.id, "project_id": projectID]) }
                            .foregroundStyle(Palette.accent).disabled(model.busy)
                    }
                }.font(.system(size: 12, weight: .medium))
            }
        }.padding(16).background(Palette.surface, in: RoundedRectangle(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Palette.line))
            .onAppear { projectID = thought.projectId ?? "" }
    }
    private var status: String {
        switch thought.status {
        case "filed": return thought.category.capitalized
        case "processing": return "Sorting…"
        case "needs_context": return "Needs a project"
        default: return "To sort"
        }
    }
}
