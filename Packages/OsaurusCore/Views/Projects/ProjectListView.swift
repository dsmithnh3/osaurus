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
                    Label("New project", systemImage: "plus")
                        .font(.system(size: 12, weight: .medium))
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 20)
            .padding(.top, 20)

            TextField("Search projects...", text: $searchText)
                .textFieldStyle(.roundedBorder)
                .padding(.horizontal, 20)

            ScrollView {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 200), spacing: 16)], spacing: 16) {
                    ForEach(filteredProjects) { project in
                        projectCard(project)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 20)
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

    private func projectCard(_ project: Project) -> some View {
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
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(theme.secondaryBackground.opacity(0.3))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .strokeBorder(theme.primaryBorder.opacity(0.2), lineWidth: 1)
                    )
            )
        }
        .buttonStyle(.plain)
    }
}
