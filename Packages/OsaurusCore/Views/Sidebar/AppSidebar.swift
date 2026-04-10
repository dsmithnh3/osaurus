//
//  AppSidebar.swift
//  osaurus
//
//  Unified sidebar for all three modes (Chat, Work, Projects).
//  Renders consistently across modes — nav items + active project chip + interleaved recents.
//

import SwiftUI

/// Unified sidebar for all three modes (Chat, Work, Projects).
/// Renders consistently across modes — nav items + active project chip + interleaved recents.
struct AppSidebar: View {
    @ObservedObject var windowState: ChatWindowState
    @ObservedObject var session: ChatSession

    @AppStorage("isRecentsExpanded") private var isRecentsExpanded = true
    @Environment(\.theme) private var theme

    @State private var searchQuery: String = ""
    @FocusState private var searchFocused: Bool
    @State private var isNewChatHovered = false

    var body: some View {
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

            // Nav items
            VStack(spacing: 2) {
                SidebarNavRow(
                    icon: "folder.fill",
                    label: "Projects",
                    badge: ProjectManager.shared.activeProjects.count,
                    isActive: windowState.sidebarContentMode == .projects,
                    action: {
                        windowState.sidebarContentMode = .projects
                    }
                )
                SidebarNavRow(
                    icon: "calendar.badge.clock",
                    label: "Scheduled",
                    isActive: windowState.sidebarContentMode == .scheduled,
                    action: {
                        windowState.sidebarContentMode = .scheduled
                    }
                )
                SidebarNavRow(
                    icon: "slider.horizontal.3",
                    label: "Customize",
                    action: {
                        AppDelegate.shared?.showManagementWindow()
                    }
                )
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)

            Divider().opacity(0.3).padding(.horizontal, 12)

            // Active project chip
            if let project = ProjectManager.shared.activeProject {
                activeProjectChip(project)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)

                Divider().opacity(0.3).padding(.horizontal, 12)
            }

            // Recents (collapsible)
            CollapsibleSection("Recents", isExpanded: $isRecentsExpanded) {
                recentsList
            }

            Spacer()
        }
    }

    // MARK: - Subviews

    private var newChatButton: some View {
        Button(action: { windowState.startNewChat() }) {
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
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(
                        isNewChatHovered
                            ? theme.secondaryBackground.opacity(0.5)
                            : theme.secondaryBackground.opacity(0.3)
                    )
            )
        }
        .buttonStyle(.plain)
        .onHover { isNewChatHovered = $0 }
    }

    private func activeProjectChip(_ project: Project) -> some View {
        ActiveProjectChipView(project: project, windowState: windowState)
    }

    private var recentsList: some View {
        ScrollView {
            LazyVStack(spacing: 1) {
                ForEach(windowState.filteredSessions) { sessionData in
                    RecentSessionRow(sessionData: sessionData, windowState: windowState)
                }
            }
        }
    }
}

// MARK: - Active Project Chip

private struct ActiveProjectChipView: View {
    let project: Project
    @ObservedObject var windowState: ChatWindowState
    @Environment(\.theme) private var theme
    @State private var isHovered = false

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: project.icon)
                .font(.system(size: 11))
                .foregroundColor(theme.secondaryText)
            Text(project.name)
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(theme.primaryText)
                .lineLimit(1)
            Spacer()
            Button(action: {
                ProjectManager.shared.setActiveProject(nil)
                windowState.projectSession = nil
            }) {
                Image(systemName: "xmark")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundColor(theme.tertiaryText)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(
                    isHovered
                        ? theme.secondaryBackground.opacity(0.6)
                        : theme.secondaryBackground.opacity(0.4)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .strokeBorder(theme.primaryBorder.opacity(0.3), lineWidth: 1)
                )
        )
        .onHover { isHovered = $0 }
    }
}

// MARK: - Recent Session Row

private struct RecentSessionRow: View {
    let sessionData: ChatSessionData
    @ObservedObject var windowState: ChatWindowState
    @Environment(\.theme) private var theme
    @State private var isHovered = false

    var body: some View {
        Text(sessionData.title)
            .font(.system(size: 12))
            .foregroundColor(theme.primaryText)
            .lineLimit(1)
            .truncationMode(.tail)
            .padding(.vertical, 4)
            .padding(.horizontal, 8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .fill(isHovered ? theme.secondaryBackground.opacity(0.3) : Color.clear)
            )
            .onHover { isHovered = $0 }
    }
}
