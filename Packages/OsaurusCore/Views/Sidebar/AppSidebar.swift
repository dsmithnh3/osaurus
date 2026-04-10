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

    private let minProjectHeight: CGFloat = 56
    private let maxProjectFraction: CGFloat = 0.5

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
                                windowState: windowState
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

    /// Sessions filtered by active project (if in project mode) and search query.
    private var visibleSessions: [ChatSessionData] {
        var sessions = windowState.filteredSessions

        // Project-scope: show only sessions belonging to this project
        if windowState.mode == .project,
           let projectId = windowState.projectSession?.activeProjectId {
            sessions = sessions.filter { $0.projectId == projectId }
        }

        // Search filter
        let query = searchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        if !query.isEmpty {
            sessions = sessions.filter {
                $0.title.localizedCaseInsensitiveContains(query)
            }
        }

        return sessions
    }

    private var recentsSection: some View {
        CollapsibleSection("Recents", isExpanded: $isRecentsExpanded) {
            ScrollView(.vertical, showsIndicators: false) {
                LazyVStack(spacing: 2) {
                    ForEach(visibleSessions) { sessionData in
                        RecentRow(sessionData: sessionData, windowState: windowState)
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

    @Environment(\.theme) private var theme
    @State private var isHovered = false

    var body: some View {
        Button(action: {
            ProjectManager.shared.setActiveProject(project.id)
            windowState.switchMode(to: .project)
            windowState.projectSession = ProjectSession(activeProjectId: project.id)
            windowState.pushNavigation(NavigationEntry(mode: .project, projectId: project.id))
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
            if isActive {
                Button("Deselect Project") {
                    ProjectManager.shared.setActiveProject(nil)
                    windowState.projectSession = nil
                }
            }
        }
    }
}

// MARK: - Recent Row

private struct RecentRow: View {
    let sessionData: ChatSessionData
    @ObservedObject var windowState: ChatWindowState

    @Environment(\.theme) private var theme
    @State private var isHovered = false

    var body: some View {
        Button(action: {
            if windowState.mode == .project, windowState.projectSession?.activeProjectId != nil {
                // Open inline within project
                windowState.projectSession?.inlineSessionId = sessionData.id
                windowState.pushNavigation(NavigationEntry(
                    mode: .project,
                    projectId: windowState.projectSession?.activeProjectId,
                    sessionId: sessionData.id
                ))
            } else {
                // Normal session selection
                windowState.session.load(from: sessionData)
                windowState.switchMode(to: .chat)
            }
        }) {
            HStack(spacing: 8) {
                Circle()
                    .fill(theme.accentColor.opacity(0.5))
                    .frame(width: 8, height: 8)

                Text(sessionData.title)
                    .font(.system(size: 12))
                    .foregroundColor(theme.primaryText)
                    .lineLimit(1)
                    .truncationMode(.tail)

                Spacer()

                Text(formatRelativeDate(sessionData.updatedAt))
                    .font(.system(size: 10))
                    .foregroundColor(theme.tertiaryText)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(
                SidebarRowBackground(
                    isSelected: sessionData.id == windowState.session.sessionId,
                    isHovered: isHovered
                )
            )
            .clipShape(RoundedRectangle(cornerRadius: SidebarStyle.rowCornerRadius, style: .continuous))
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
    }
}
