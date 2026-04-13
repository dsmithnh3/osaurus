//
//  AppSidebar.swift
//  osaurus
//
//  Unified sidebar for all three modes (Chat, Work, Projects).
//  Stacked layout: project list + draggable divider + unified recents.
//

import SwiftUI

/// Unified sidebar for all three modes (Chat, Work, Projects).
struct AppSidebar: View {
    @ObservedObject var windowState: ChatWindowState
    @ObservedObject var session: ChatSession

    @AppStorage("isRecentsExpanded") private var isRecentsExpanded = true
    @AppStorage("isProjectsExpanded") private var isProjectsExpanded = true
    @AppStorage("sidebarProjectSectionHeight") private var projectSectionHeight: Double = 140

    @Environment(\.theme) private var theme
    @State private var searchQuery: String = ""
    @FocusState private var searchFocused: Bool
    @State private var isNewChatHovered = false
    @State private var isDraggingDivider = false
    @State private var renamingSessionId: UUID?
    @State private var renamingTitle: String = ""
    @State private var projectEditorPresentation: ProjectEditorPresentation?
    @State private var pendingDeleteProjectId: UUID?

    private let minProjectHeight: CGFloat = 56
    private let maxProjectFraction: CGFloat = 0.5

    // MARK: - ProjectRecentItem

    enum ProjectRecentItem: Identifiable {
        case session(ChatSessionData)
        case task(WorkTask)

        var id: String {
            switch self {
            case .session(let s): return "session-\(s.id.uuidString)"
            case .task(let t): return "task-\(t.id)"
            }
        }

        var date: Date {
            switch self {
            case .session(let s): return s.updatedAt
            case .task(let t): return t.updatedAt
            }
        }
    }

    var body: some View {
        SidebarContainer(attachedEdge: .leading, topPadding: 40) {
            GeometryReader { geometry in
                let maxProjectHeight = geometry.size.height * maxProjectFraction

                VStack(spacing: 0) {
                    // New Chat button
                    newChatButton
                        .padding(.horizontal, 12)
                        .padding(.top, 8)
                        .padding(.bottom, 4)

                    // Search field
                    SidebarSearchField(
                        text: $searchQuery,
                        placeholder: "Search conversations...",
                        isFocused: $searchFocused
                    )
                    .padding(.horizontal, 12)
                    .padding(.bottom, 8)

                    Divider().opacity(0.3).padding(.horizontal, 12)

                    // Projects section
                    projectsSection(maxHeight: maxProjectHeight)

                    // Draggable divider
                    draggableDivider(maxHeight: maxProjectHeight)

                    // Recents section
                    recentsSection

                    Spacer(minLength: 0)
                }
            }
        }
        .sheet(item: $projectEditorPresentation) { presentation in
            ProjectEditorSheet(
                existingProject: presentation.project(from: ProjectManager.shared.projects),
                onSave: { _ in },
                onArchiveToggle: { project in
                    toggleArchive(for: project)
                },
                onDelete: { project in
                    deleteProject(project)
                }
            )
        }
        .alert("Delete Project?", isPresented: deleteAlertBinding, presenting: pendingDeleteProject) { project in
            Button("Delete", role: .destructive) {
                deleteProject(project)
            }
            Button("Cancel", role: .cancel) {
                pendingDeleteProjectId = nil
            }
        } message: { project in
            Text(
                "Delete \"\(project.name)\" from Osaurus. Its linked folder and project memory will be left untouched."
            )
        }
        .onChange(of: ProjectManager.shared.projects.map(\.id)) { _, ids in
            projectEditorPresentation = normalizedEditorPresentation(projectEditorPresentation, projectIds: ids)
            pendingDeleteProjectId = ProjectManagementSelection.normalizedProjectId(
                pendingDeleteProjectId,
                in: ProjectManager.shared.projects
            )
        }
    }

    // MARK: - New Chat Button

    private var newChatButton: some View {
        Button(action: {
            windowState.startNewChat()
        }) {
            HStack {
                Image(systemName: "plus.bubble")
                    .font(.system(size: 13, weight: .medium))
                Text("New Chat")
                    .font(.system(size: 13, weight: .medium))
                Spacer()
            }
            .foregroundColor(theme.primaryText)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(
                SidebarRowBackground(isSelected: false, isHovered: isNewChatHovered)
            )
            .clipShape(RoundedRectangle(cornerRadius: SidebarStyle.rowCornerRadius, style: .continuous))
        }
        .buttonStyle(.plain)
        .onHover { isNewChatHovered = $0 }
    }

    // MARK: - Projects Section

    @ViewBuilder
    private func projectsSection(maxHeight: CGFloat) -> some View {
        CollapsibleSection("Projects", isExpanded: $isProjectsExpanded) {
            Text("\(ProjectManager.shared.activeProjects.count)")
                .font(.system(size: 10, weight: .medium))
                .foregroundColor(theme.tertiaryText)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(
                    Capsule().fill(theme.secondaryBackground.opacity(0.5))
                )
        } content: {
            let projects = ProjectManager.shared.activeProjects
            if projects.isEmpty {
                emptyProjectsRow
            } else {
                ScrollView(.vertical, showsIndicators: false) {
                    VStack(spacing: 2) {
                        ForEach(projects) { project in
                            ProjectSidebarRow(
                                project: project,
                                isActive: project.id == ProjectManager.shared.activeProjectId,
                                windowState: windowState,
                                onEdit: { projectEditorPresentation = .edit(project.id) },
                                onArchive: { toggleArchive(for: project) },
                                onDelete: { pendingDeleteProjectId = project.id }
                            )
                        }
                    }
                    .padding(.horizontal, 8)
                }
                .frame(maxHeight: min(CGFloat(projectSectionHeight), maxHeight))
            }

            // All Projects row
            if !projects.isEmpty {
                allProjectsRow
                    .padding(.horizontal, 8)
                    .padding(.top, 4)
            }
        }
    }

    private var emptyProjectsRow: some View {
        Button(action: {
            windowState.sidebarContentMode = .projects
        }) {
            HStack(spacing: 6) {
                Image(systemName: "plus")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(theme.tertiaryText)
                Text("Create a project to get started")
                    .font(.system(size: 11))
                    .foregroundColor(theme.secondaryText)
                Spacer()
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 8)
    }

    private var allProjectsRow: some View {
        Button(action: {
            windowState.sidebarContentMode = .projects
        }) {
            HStack(spacing: 6) {
                Image(systemName: "square.grid.2x2")
                    .font(.system(size: 11))
                    .foregroundColor(theme.secondaryText)
                Text("All Projects")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(theme.secondaryText)
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundColor(theme.tertiaryText)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(
                SidebarRowBackground(isSelected: false, isHovered: false)
            )
            .clipShape(RoundedRectangle(cornerRadius: SidebarStyle.rowCornerRadius, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    private var pendingDeleteProject: Project? {
        guard let pendingDeleteProjectId else { return nil }
        return ProjectManager.shared.projects.first(where: { $0.id == pendingDeleteProjectId })
    }

    private var deleteAlertBinding: Binding<Bool> {
        Binding(
            get: { pendingDeleteProject != nil },
            set: { if !$0 { pendingDeleteProjectId = nil } }
        )
    }

    private func toggleArchive(for project: Project) {
        ProjectManager.shared.archiveProject(id: project.id)
        windowState.handleDeletedOrArchivedProject(project.id)
    }

    private func deleteProject(_ project: Project) {
        ProjectManager.shared.deleteProject(id: project.id)
        windowState.handleDeletedOrArchivedProject(project.id)
        pendingDeleteProjectId = nil
    }

    private func normalizedEditorPresentation(
        _ presentation: ProjectEditorPresentation?,
        projectIds: [UUID]
    ) -> ProjectEditorPresentation? {
        guard let presentation else { return nil }
        switch presentation {
        case .create:
            return .create
        case .edit(let projectId):
            return projectIds.contains(projectId) ? presentation : nil
        }
    }

    // MARK: - Draggable Divider

    @ViewBuilder
    private func draggableDivider(maxHeight: CGFloat) -> some View {
        VStack(spacing: 0) {
            Divider().opacity(0.3).padding(.horizontal, 12)
        }
        .frame(height: 8)
        .contentShape(Rectangle())
        .gesture(
            DragGesture(minimumDistance: 1)
                .onChanged { value in
                    isDraggingDivider = true
                    let newHeight = projectSectionHeight + Double(value.translation.height)
                    projectSectionHeight = max(Double(minProjectHeight), min(newHeight, Double(maxHeight)))
                }
                .onEnded { _ in
                    isDraggingDivider = false
                }
        )
        .onHover { hovering in
            if hovering {
                NSCursor.resizeUpDown.push()
            } else {
                NSCursor.pop()
            }
        }
    }

    // MARK: - Recents Section

    /// Recent items (sessions + tasks) filtered by active project and search query, sorted by date descending.
    private var projectRecentItems: [ProjectRecentItem] {
        var items: [ProjectRecentItem] = []

        // Chat sessions
        let sessions: [ChatSessionData] = {
            var s = windowState.filteredSessions
            if windowState.mode == .project,
                let projectId = windowState.projectSession?.activeProjectId
            {
                s = s.filter { $0.projectId == projectId }
            }
            return s
        }()
        items.append(contentsOf: sessions.map { .session($0) })

        // Work tasks (only in project mode with active project)
        if windowState.mode == .project,
            let projectId = windowState.projectSession?.activeProjectId,
            WorkDatabase.shared.isOpen
        {
            let tasks = (try? IssueStore.listTasks(projectId: projectId)) ?? []
            items.append(contentsOf: tasks.map { .task($0) })
        }

        // Sort by date descending
        items.sort { $0.date > $1.date }

        // Apply search filter
        let query = searchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        if !query.isEmpty {
            items = items.filter {
                switch $0 {
                case .session(let s): return s.title.localizedCaseInsensitiveContains(query)
                case .task(let t): return t.title.localizedCaseInsensitiveContains(query)
                }
            }
        }

        return items
    }

    private var recentsSection: some View {
        CollapsibleSection("Recents", isExpanded: $isRecentsExpanded) {
            ScrollView(.vertical, showsIndicators: false) {
                LazyVStack(spacing: 2) {
                    ForEach(projectRecentItems) { item in
                        switch item {
                        case .session(let sessionData):
                            SessionRow(
                                session: sessionData,
                                agent: windowState.agents.first { $0.id == sessionData.agentId },
                                isSelected: sessionData.id == windowState.session.sessionId,
                                isEditing: renamingSessionId == sessionData.id,
                                editingTitle: $renamingTitle,
                                onSelect: {
                                    if windowState.mode == .project,
                                        windowState.projectSession?.activeProjectId != nil
                                    {
                                        windowState.loadSession(sessionData)
                                        windowState.switchProjectSubMode(to: .chat)
                                    } else {
                                        windowState.loadSession(sessionData)
                                        windowState.switchMode(to: .chat)
                                    }
                                },
                                onStartRename: {
                                    renamingSessionId = sessionData.id
                                    renamingTitle = sessionData.title
                                },
                                onConfirmRename: {
                                    if let id = renamingSessionId, !renamingTitle.isEmpty {
                                        ChatSessionsManager.shared.rename(id: id, title: renamingTitle)
                                        windowState.refreshSessions()
                                    }
                                    renamingSessionId = nil
                                    renamingTitle = ""
                                },
                                onCancelRename: {
                                    renamingSessionId = nil
                                    renamingTitle = ""
                                },
                                onDelete: {
                                    ChatSessionsManager.shared.delete(id: sessionData.id)
                                    if windowState.session.sessionId == sessionData.id {
                                        windowState.startNewChat()
                                    }
                                    windowState.refreshSessions()
                                },
                                onOpenInNewWindow: {
                                    ChatWindowManager.shared.createWindow(
                                        agentId: sessionData.agentId,
                                        sessionData: sessionData
                                    )
                                }
                            )
                        case .task(let task):
                            TaskRow(
                                task: task,
                                isSelected: windowState.workSession?.currentTask?.id == task.id,
                                onSelect: {
                                    windowState.switchProjectSubMode(to: .work)
                                    Task { await windowState.workSession?.loadTask(task) }
                                },
                                onDelete: {
                                    Task {
                                        try? await IssueManager.shared.deleteTask(task.id)
                                        windowState.refreshWorkTasks()
                                    }
                                }
                            )
                        }
                    }
                }
                .padding(.horizontal, 8)
            }
        }
    }
}

// MARK: - Project Sidebar Row

private struct ProjectSidebarRow: View {
    let project: Project
    let isActive: Bool
    @ObservedObject var windowState: ChatWindowState
    let onEdit: () -> Void
    let onArchive: () -> Void
    let onDelete: () -> Void

    @Environment(\.theme) private var theme
    @State private var isHovered = false

    var body: some View {
        Button(action: {
            windowState.openProject(project.id)
        }) {
            HStack(spacing: 8) {
                Image(systemName: project.icon)
                    .font(.system(size: 11))
                    .foregroundColor(isActive ? theme.accentColor : theme.secondaryText)

                Text(project.name)
                    .font(.system(size: 12))
                    .foregroundColor(theme.primaryText)
                    .lineLimit(1)
                    .truncationMode(.tail)

                Spacer()

                if isActive {
                    Circle()
                        .fill(theme.accentColor)
                        .frame(width: 6, height: 6)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(
                SidebarRowBackground(isSelected: isActive, isHovered: isHovered)
            )
            .clipShape(RoundedRectangle(cornerRadius: SidebarStyle.rowCornerRadius, style: .continuous))
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .contextMenu {
            Button("Open") {
                windowState.openProject(project.id)
            }

            Button("Edit Settings…") {
                onEdit()
            }

            Divider()

            Button("Archive") {
                onArchive()
            }

            Button("Delete…", role: .destructive) {
                onDelete()
            }
        }
    }
}
