import SwiftUI
import AppKit

struct PanelView: View {
    @ObservedObject var model: AppModel
    private var isRoot: Bool { model.page == "projects" || model.page == "inbox" }
    var body: some View {
        VStack(spacing: 0) {
            header
            Hairline()
            if let error = model.error {
                HStack(alignment: .top, spacing: 9) {
                    Image(systemName: "exclamationmark.circle")
                    Text(error).font(.system(size: 13)).fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 0)
                    IconButton(symbol: "xmark", label: "Dismiss error") { model.error = nil }
                }.foregroundStyle(Palette.amber).padding(14).background(Palette.amber.opacity(0.06))
            }
            Group {
                switch model.page {
                case "project": if let project = model.selected { ProjectView(model: model, project: project).id(project.id) }
                case "capture": CaptureView(model: model)
                case "new": NewProjectView(model: model)
                case "settings": SettingsView(model: model)
                case "agentSetup": AgentSetupView(model: model)
                case "inbox": InboxView(model: model)
                default: ProjectsView(model: model)
                }
            }.frame(maxWidth: .infinity, maxHeight: .infinity)
            if let toast = model.toast {
                HStack(spacing: 8) {
                    Image(systemName: "checkmark.circle.fill")
                    Text(toast).fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 0)
                }.font(.system(size: 12)).foregroundStyle(Palette.accent).padding(.horizontal, 22).padding(.vertical, 10)
                    .background(Palette.accentWash)
            }
            if model.page != "capture" && model.page != "new" { captureBar }
        }.background(Palette.background).foregroundStyle(Palette.text)
            .buttonStyle(QuietButtonStyle()).tint(Palette.accent).preferredColorScheme(.light)
    }

    private var header: some View {
        VStack(spacing: 13) {
            HStack(spacing: 9) {
                if isRoot {
                    Image(systemName: "sparkle").font(.system(size: 19, weight: .medium)).foregroundStyle(Palette.accent)
                    Text("North Star").font(.system(size: 14, weight: .semibold))
                } else {
                    Button { model.back() } label: {
                        HStack(spacing: 7) {
                            Image(systemName: "chevron.left").font(.system(size: 11, weight: .semibold))
                            Text(model.backLabel).font(.system(size: 13, weight: .medium)).lineLimit(1)
                        }.foregroundStyle(Palette.secondary).frame(minHeight: 32)
                    }.keyboardShortcut("[", modifiers: .command).accessibilityLabel("Back to \(model.backLabel)")
                }
                Spacer()
                if model.page == "project" || model.page == "agentSetup" {
                    IconButton(symbol: "tray", label: "Thought inbox") { model.navigate(to: "inbox") }
                }
                IconButton(symbol: "gearshape", label: "Settings") { model.navigate(to: "settings") }
            }
            if isRoot {
                HStack(spacing: 4) {
                    rootTab("Projects", page: "projects", symbol: "square.grid.2x2")
                    rootTab("Inbox", page: "inbox", symbol: "tray", count: model.inboxCount)
                    Spacer()
                }
            }
        }.padding(.horizontal, 22).padding(.top, 12).padding(.bottom, isRoot ? 14 : 9)
    }

    private func rootTab(_ title: String, page: String, symbol: String, count: Int = 0) -> some View {
        Button { model.showRoot(page) } label: {
            HStack(spacing: 7) {
                Image(systemName: symbol).font(.system(size: 12))
                Text(title).font(.system(size: 13, weight: model.page == page ? .semibold : .medium))
                if count > 0 { Text("\(count)").font(.system(size: 11, weight: .semibold)).monospacedDigit() }
            }.foregroundStyle(model.page == page ? Palette.accent : Palette.secondary)
                .padding(.horizontal, 12).padding(.vertical, 8)
                .background(model.page == page ? Palette.accentWash : .clear, in: RoundedRectangle(cornerRadius: 7))
        }.accessibilityAddTraits(model.page == page ? .isSelected : [])
    }

    private var captureBar: some View {
        VStack(spacing: 0) {
            Hairline()
            Button { model.capture() } label: {
                HStack(spacing: 11) {
                    Image(systemName: "mic").font(.system(size: 16)).foregroundStyle(Palette.accent)
                        .frame(width: 32, height: 32).background(Palette.accentWash, in: RoundedRectangle(cornerRadius: 8))
                    Text("Capture a thought").font(.system(size: 14, weight: .medium))
                    Spacer()
                    Text("⌘ K").font(.system(size: 11, weight: .medium)).foregroundStyle(Palette.secondary)
                        .padding(.horizontal, 6).padding(.vertical, 4)
                        .overlay(RoundedRectangle(cornerRadius: 4).strokeBorder(Palette.line))
                }.padding(.horizontal, 22).padding(.vertical, 14).contentShape(Rectangle())
            }.keyboardShortcut("k").help("Write or speak a thought")
        }.background(Palette.surface)
    }
}

struct ProjectsView: View {
    @ObservedObject var model: AppModel
    private var updatedCount: Int { model.snapshot.projects.filter { $0.newCount > 0 }.count }
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 7) {
                        Text("Your projects").font(.system(size: 25, weight: .semibold)).tracking(-0.5)
                        Text(updatedCount == 0 ? "Pick up where you left off." : "\(updatedCount) \(updatedCount == 1 ? "project has" : "projects have") new updates.")
                            .font(.system(size: 14)).foregroundStyle(Palette.secondary)
                    }
                    Spacer()
                    Button { model.navigate(to: "new") } label: {
                        Label("New", systemImage: "plus").font(.system(size: 12, weight: .medium))
                            .padding(.horizontal, 10).padding(.vertical, 7)
                            .background(Palette.surface, in: RoundedRectangle(cornerRadius: 7))
                            .overlay(RoundedRectangle(cornerRadius: 7).strokeBorder(Palette.line))
                    }.help("Add project · ⌘N").accessibilityLabel("Add project")
                }
                if model.snapshot.projects.isEmpty {
                    EmptyState(symbol: "square.stack", title: "Start with one project", detail: "Give it a goal. Keep its progress and your thoughts together.")
                    Button("Create a project") { model.navigate(to: "new") }.buttonStyle(ActionButtonStyle())
                } else {
                    VStack(spacing: 0) {
                        ForEach(Array(model.snapshot.projects.enumerated()), id: \.element.id) { index, project in
                            if index > 0 { Hairline().padding(.leading, 66) }
                            Button { model.open(project) } label: {
                                HoverRow {
                                    HStack(alignment: .top, spacing: 13) {
                                        ProjectMark(name: project.name)
                                        VStack(alignment: .leading, spacing: 7) {
                                            HStack(spacing: 8) {
                                                Text(project.name).font(.system(size: 15, weight: .semibold)).lineLimit(2)
                                                Spacer(minLength: 0)
                                                if project.newCount > 0 { Tag(text: "\(project.newCount) new") }
                                            }
                                            Text(project.state).font(.system(size: 13)).foregroundStyle(Palette.secondary)
                                                .lineSpacing(3).lineLimit(3).fixedSize(horizontal: false, vertical: true)
                                        }
                                        Image(systemName: "chevron.right").font(.system(size: 10, weight: .semibold))
                                            .foregroundStyle(Palette.secondary).padding(.top, 4)
                                    }.multilineTextAlignment(.leading)
                                }
                            }.accessibilityLabel("Open \(project.name), \(project.newCount) new updates")
                        }
                    }.clipShape(RoundedRectangle(cornerRadius: 12))
                        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Palette.line))
                    Button { model.navigate(to: "agentSetup") } label: {
                        HStack(spacing: 12) {
                            Image(systemName: "link").font(.system(size: 15)).foregroundStyle(Palette.accent)
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Connect an agent").font(.system(size: 13, weight: .medium)).foregroundStyle(Palette.text)
                                Text("Let plans and progress arrive here.").font(.system(size: 12)).foregroundStyle(Palette.secondary)
                            }
                            Spacer()
                            Image(systemName: "arrow.up.right").font(.system(size: 11)).foregroundStyle(Palette.secondary)
                        }.padding(.vertical, 6).contentShape(Rectangle())
                    }
                }
            }.padding(22)
        }
    }
}

struct ProjectView: View {
    @ObservedObject var model: AppModel
    let project: Project
    private var tab: String {
        get { model.projectTab }
        nonmutating set { model.projectTab = newValue }
    }
    var changes: [Update] { project.events.filter { $0.seq > model.boundary } }
    var body: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 20) {
                HStack(alignment: .center, spacing: 12) {
                    ProjectMark(name: project.name)
                    Text(project.name).font(.system(size: 23, weight: .semibold)).tracking(-0.4).lineLimit(2)
                    Spacer(minLength: 0)
                    Menu {
                        Button("Agent setup", systemImage: "link") { model.navigate(to: "agentSetup") }
                        Button("Copy agent instructions", systemImage: "doc.on.doc") {
                            model.copy(model.agentSetup(for: project).instructions, confirmation: "Instructions for \(project.name) copied.")
                        }
                    } label: {
                        Image(systemName: "ellipsis").font(.system(size: 17)).foregroundStyle(Palette.secondary)
                            .frame(width: 30, height: 30)
                    }.menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize().help("Project actions")
                        .accessibilityLabel("Project actions")
                }
                TabStrip(items: ["Overview", "Knowledge", "History"], selected: $model.projectTab)
            }.padding(.horizontal, 22).padding(.top, 20)
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 25) {
                        Color.clear.frame(height: 0).id("top")
                        if tab == "Overview" { overview }
                        else if tab == "Knowledge" {
                            SectionHeading(title: "Ideas, decisions & findings", trailing: "\(project.knowledge.count)")
                            if project.knowledge.isEmpty {
                                EmptyState(symbol: "lightbulb", title: "Room for your thinking", detail: "Ideas, decisions and findings appear here with their original context.")
                            } else { updateList(project.knowledge) }
                        } else {
                            SectionHeading(title: "Update history", trailing: "\(project.events.count) updates")
                            if project.events.isEmpty {
                                EmptyState(symbol: "clock", title: "The story starts here", detail: "Agent plans and results will build a history of this project.")
                            } else { updateList(project.events) }
                        }
                    }.padding(.horizontal, 22).padding(.bottom, 24)
                }.onChange(of: tab) { _, _ in proxy.scrollTo("top", anchor: .top) }
            }
        }
    }

    @ViewBuilder private var overview: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 8) {
                Text("CURRENT STATE").font(.system(size: 10, weight: .semibold)).tracking(1.2).foregroundStyle(Palette.secondary)
                Text(project.state).font(.system(size: 18, weight: .medium)).lineSpacing(4)
                    .fixedSize(horizontal: false, vertical: true).textSelection(.enabled)
            }
            VStack(alignment: .leading, spacing: 8) {
                Label("Nearest goal", systemImage: "scope").font(.system(size: 11, weight: .semibold)).foregroundStyle(Palette.accent)
                Text(project.goal).font(.system(size: 14)).lineSpacing(3).fixedSize(horizontal: false, vertical: true)
            }.padding(14).frame(maxWidth: .infinity, alignment: .leading)
                .background(Palette.accentWash, in: RoundedRectangle(cornerRadius: 9))
        }
        VStack(alignment: .leading, spacing: 10) {
            SectionHeading(title: model.boundary == 0 ? "Recent updates" : "Since your last visit", trailing: changes.isEmpty ? "All caught up" : "\(changes.count) new")
            if changes.isEmpty {
                Text("No new updates. Your current plan is below.").font(.system(size: 13)).foregroundStyle(Palette.secondary).padding(.vertical, 5)
            } else { updateList(Array(changes.prefix(3))) }
            if changes.count > 3 {
                Button { tab = "History" } label: { Label("View all \(changes.count) updates", systemImage: "arrow.right") }
                    .font(.system(size: 12, weight: .medium)).foregroundStyle(Palette.accent).padding(.top, 2)
            }
        }
        VStack(alignment: .leading, spacing: 10) {
            SectionHeading(title: "In the plan", trailing: "\(project.tasks.count) open")
            if project.tasks.isEmpty {
                Text(project.completed.isEmpty ? "No agreed work yet." : "The agreed work is complete.")
                    .font(.system(size: 13)).foregroundStyle(Palette.secondary).padding(.vertical, 5)
            } else { updateList(project.tasks, showOutcome: true) }
        }
        if !project.completed.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                SectionHeading(title: "Completed", trailing: "\(project.completed.count)")
                updateList(Array(project.completed.suffix(3).reversed()), showOutcome: true)
            }
        }
        if !project.suggestions.isEmpty {
            VStack(alignment: .leading, spacing: 14) {
                SectionHeading(title: "Possible next steps", trailing: "Suggestions")
                ForEach(Array(project.suggestions.enumerated()), id: \.element.id) { index, item in
                    HStack(alignment: .top, spacing: 12) {
                        Text("\(index + 1)").font(.system(size: 11, weight: .medium)).foregroundStyle(Palette.secondary)
                            .frame(width: 22, height: 22).background(Palette.elevated, in: Circle())
                        VStack(alignment: .leading, spacing: 5) {
                            Text(item.title).font(.system(size: 14, weight: .medium))
                            Text(item.detail).font(.system(size: 13)).foregroundStyle(Palette.secondary).lineSpacing(3)
                        }
                    }
                }
            }
        }
        VStack(alignment: .leading, spacing: 14) {
            Hairline()
            DisclosureGroup("About this project") {
                Text(project.purpose).font(.system(size: 13)).foregroundStyle(Palette.secondary)
                    .lineSpacing(3).textSelection(.enabled).padding(.top, 8)
            }.font(.system(size: 12, weight: .medium)).foregroundStyle(Palette.secondary)
            Button { model.navigate(to: "agentSetup") } label: { Label("Agent setup", systemImage: "link") }
                .font(.system(size: 12, weight: .medium)).foregroundStyle(Palette.accent)
        }
    }

    private func updateList(_ updates: [Update], showOutcome: Bool = false) -> some View {
        VStack(spacing: 0) {
            ForEach(Array(updates.enumerated()), id: \.element.id) { index, update in
                if index > 0 { Hairline().padding(.leading, 29) }
                UpdateRow(update: update, showOutcome: showOutcome)
            }
        }
    }
}

struct UpdateRow: View {
    let update: Update
    var showOutcome = false
    @State private var expanded = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Button { withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.15)) { expanded.toggle() } } label: {
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: update.icon).font(.system(size: 15)).foregroundStyle(update.tint).frame(width: 19).padding(.top, 1)
                    VStack(alignment: .leading, spacing: 5) {
                        Text(showOutcome ? update.outcome ?? update.title : update.title).font(.system(size: 14, weight: .medium))
                            .lineSpacing(2).multilineTextAlignment(.leading).fixedSize(horizontal: false, vertical: true)
                        Text(update.label).font(.system(size: 11)).foregroundStyle(update.tint)
                    }
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.right").rotationEffect(.degrees(expanded ? 90 : 0))
                        .font(.system(size: 9, weight: .semibold)).foregroundStyle(Palette.secondary).padding(.top, 4)
                }.contentShape(Rectangle())
            }.accessibilityLabel("\(update.title), \(update.label), \(expanded ? "collapse" : "show details")")
            if expanded {
                VStack(alignment: .leading, spacing: 10) {
                    if !update.detail.isEmpty { Text(update.detail).font(.system(size: 13)).lineSpacing(3).textSelection(.enabled) }
                    if !update.verification.isEmpty {
                        VStack(alignment: .leading, spacing: 5) {
                            Text("Reported verification").font(.system(size: 11, weight: .semibold)).foregroundStyle(Palette.accent)
                            Text(update.verification).font(.system(size: 12)).foregroundStyle(Palette.secondary).lineSpacing(3).textSelection(.enabled)
                        }
                    }
                    Text("\(update.agent) · \(String(update.createdAt.prefix(10)))").font(.system(size: 11)).foregroundStyle(Palette.secondary)
                    if !update.source.isEmpty {
                        if let url = URL(string: update.source), ["https", "http"].contains(url.scheme) {
                            Link(destination: url) { Label("Open source", systemImage: "arrow.up.right.square").font(.system(size: 12)) }.foregroundStyle(Palette.accent)
                        } else {
                            Text(update.source).font(.system(size: 11)).foregroundStyle(Palette.secondary).textSelection(.enabled)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }.padding(12).frame(maxWidth: .infinity, alignment: .leading)
                    .background(Palette.surface, in: RoundedRectangle(cornerRadius: 8)).padding(.leading, 29)
            }
        }.padding(.vertical, 12)
    }
}
