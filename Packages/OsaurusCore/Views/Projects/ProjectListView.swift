//
//  ProjectListView.swift
//  osaurus
//
//  Grid of projects with search and "New project" button.
//

import SwiftUI

/// Grid of projects with search and "New project" button.
struct ProjectListView: View {
    @ObservedObject var windowState: ChatWindowState

    @State private var searchText = ""
    @State private var showEditor = false
    @Environment(\.theme) private var theme

    private var filteredProjects: [Project] {
        let active = ProjectManager.shared.activeProjects
        if searchText.isEmpty { return active }
        return active.filter { $0.name.localizedCaseInsensitiveContains(searchText) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("Projects")
                    .font(.title)
                    .foregroundColor(theme.primaryText)
                Spacer()
                Button(action: { showEditor = true }) {
                    HStack(spacing: 6) {
                        Image(systemName: "plus")
                        Text("New project")
                    }
                    .font(.system(size: 12, weight: .medium))
                }
                .buttonStyle(.borderedProminent)
            }
            .padding(.horizontal, 20)
            .padding(.top, 20)

            TextField("Search projects...", text: $searchText)
                .textFieldStyle(.roundedBorder)
                .foregroundColor(theme.primaryText)
                .padding(.horizontal, 20)

            if filteredProjects.isEmpty {
                emptyState
            } else {
                ScrollView {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 200), spacing: 16)], spacing: 16) {
                        ForEach(filteredProjects) { project in
                            ProjectCardView(project: project, windowState: windowState)
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.bottom, 20)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .sheet(isPresented: $showEditor) {
            ProjectEditorSheet(onSave: { project in
                ProjectManager.shared.setActiveProject(project.id)
                windowState.switchMode(to: .project)
                windowState.projectSession = ProjectSession(activeProjectId: project.id)
                windowState.pushNavigation(NavigationEntry(mode: .project, projectId: project.id))
            })
        }
    }

    @ViewBuilder
    private var emptyState: some View {
        if searchText.isEmpty {
            VStack(spacing: 12) {
                Image(systemName: "folder.badge.plus")
                    .font(.system(size: 32))
                    .foregroundColor(theme.tertiaryText)
                Text("No projects yet")
                    .font(.headline)
                    .foregroundColor(theme.secondaryText)
                Text("Create a project to organize conversations, tasks, and context")
                    .font(.subheadline)
                    .foregroundColor(theme.tertiaryText)
                    .multilineTextAlignment(.center)
                Button("Create Project") { showEditor = true }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.regular)
            }
            .padding(40)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            VStack(spacing: 12) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 32))
                    .foregroundColor(theme.tertiaryText)
                Text("No projects match \"\(searchText)\"")
                    .font(.headline)
                    .foregroundColor(theme.secondaryText)
            }
            .padding(40)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}

/// Individual project card with hover effects.
private struct ProjectCardView: View {
    let project: Project
    @ObservedObject var windowState: ChatWindowState

    @State private var isHovered = false
    @Environment(\.theme) private var theme

    var body: some View {
        Button(action: {
            ProjectManager.shared.setActiveProject(project.id)
            windowState.switchMode(to: .project)
            windowState.projectSession = ProjectSession(activeProjectId: project.id)
            windowState.pushNavigation(NavigationEntry(mode: .project, projectId: project.id))
        }) {
            VStack(alignment: .leading, spacing: 8) {
                Image(systemName: project.icon)
                    .font(.system(size: 24))
                    .foregroundColor(theme.accentColor)

                Text(project.name)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(theme.primaryText)
                    .lineLimit(1)

                if let desc = project.description {
                    Text(desc)
                        .font(.system(size: 11))
                        .foregroundColor(theme.secondaryText)
                        .lineLimit(2)
                }
            }
            .padding(16)
            .frame(maxWidth: .infinity, minHeight: 100, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(theme.cardBackground.opacity(isHovered ? 0.5 : 0.3))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .strokeBorder(theme.cardBorder.opacity(isHovered ? 0.3 : 0), lineWidth: 1)
                    )
            )
        }
        .buttonStyle(.plain)
        .scaleEffect(isHovered ? 1.01 : 1.0)
        .animation(.easeInOut(duration: 0.15), value: isHovered)
        .onHover { hovering in
            isHovered = hovering
        }
    }
}
