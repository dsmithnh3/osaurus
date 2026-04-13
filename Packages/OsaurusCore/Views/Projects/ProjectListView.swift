//
//  ProjectListView.swift
//  osaurus
//
//  Grid of projects with search and "New project" button.
//

import SwiftUI

enum ProjectListFilter: String, CaseIterable, Identifiable {
    case active = "Active"
    case archived = "Archived"

    var id: String { rawValue }

    func projects(from projects: [Project], searchText: String) -> [Project] {
        let baseProjects = projects.filter { project in
            switch self {
            case .active:
                return project.isActive && !project.isArchived
            case .archived:
                return project.isArchived
            }
        }

        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return baseProjects }

        return baseProjects.filter { project in
            project.name.localizedCaseInsensitiveContains(query)
                || (project.description?.localizedCaseInsensitiveContains(query) ?? false)
        }
    }
}

/// Grid of projects with search and "New project" button.
struct ProjectListView: View {
    @ObservedObject var windowState: ChatWindowState

    @State private var searchText = ""
    @State private var selectedFilter: ProjectListFilter = .active
    @State private var editorPresentation: ProjectEditorPresentation?
    @State private var pendingDeleteProjectId: UUID?
    @Environment(\.theme) private var theme

    private var filteredProjects: [Project] {
        selectedFilter.projects(from: ProjectManager.shared.projects, searchText: searchText)
    }

    private var pendingDeleteProject: Project? {
        guard let pendingDeleteProjectId else { return nil }
        return ProjectManager.shared.projects.first(where: { $0.id == pendingDeleteProjectId })
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("Projects")
                    .font(.title)
                    .foregroundColor(theme.primaryText)
                Spacer()
                Button(action: { editorPresentation = .create }) {
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

            HStack(spacing: 12) {
                TextField("Search projects...", text: $searchText)
                    .textFieldStyle(.roundedBorder)
                    .foregroundColor(theme.primaryText)

                Picker("Project Filter", selection: $selectedFilter) {
                    ForEach(ProjectListFilter.allCases) { filter in
                        Text(filter.rawValue).tag(filter)
                    }
                }
                .pickerStyle(.segmented)
                .frame(width: 180)
            }
                .padding(.horizontal, 20)

            if filteredProjects.isEmpty {
                emptyState
            } else {
                ScrollView {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 200), spacing: 16)], spacing: 16) {
                        ForEach(filteredProjects) { project in
                            ProjectCardView(
                                project: project,
                                onOpen: {
                                    if project.isArchived {
                                        editorPresentation = .edit(project.id)
                                    } else {
                                        windowState.openProject(project.id)
                                    }
                                },
                                onEdit: { editorPresentation = .edit(project.id) },
                                onArchiveToggle: { toggleArchive(for: project) },
                                onDelete: { pendingDeleteProjectId = project.id }
                            )
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.bottom, 20)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .sheet(item: $editorPresentation) { presentation in
            ProjectEditorSheet(
                existingProject: presentation.project(from: ProjectManager.shared.projects),
                onSave: { project in
                    if case .create = presentation {
                        windowState.openProject(project.id)
                    }
                },
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
            editorPresentation = normalizedEditorPresentation(editorPresentation, projectIds: ids)
            pendingDeleteProjectId = ProjectManagementSelection.normalizedProjectId(
                pendingDeleteProjectId,
                in: ProjectManager.shared.projects
            )
        }
    }

    @ViewBuilder
    private var emptyState: some View {
        if searchText.isEmpty {
            VStack(spacing: 12) {
                Image(systemName: selectedFilter == .active ? "folder.badge.plus" : "archivebox")
                    .font(.system(size: 32))
                    .foregroundColor(theme.tertiaryText)
                Text(selectedFilter == .active ? "No active projects" : "No archived projects")
                    .font(.headline)
                    .foregroundColor(theme.secondaryText)
                Text(
                    selectedFilter == .active
                        ? "Create a project to organize conversations, tasks, and context"
                        : "Archived projects will appear here after you archive them"
                )
                    .font(.subheadline)
                    .foregroundColor(theme.tertiaryText)
                    .multilineTextAlignment(.center)
                if selectedFilter == .active {
                    Button("Create Project") { editorPresentation = .create }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.regular)
                }
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

    private var deleteAlertBinding: Binding<Bool> {
        Binding(
            get: { pendingDeleteProject != nil },
            set: { if !$0 { pendingDeleteProjectId = nil } }
        )
    }

    private func toggleArchive(for project: Project) {
        if project.isArchived {
            ProjectManager.shared.unarchiveProject(id: project.id)
        } else {
            ProjectManager.shared.archiveProject(id: project.id)
            windowState.handleDeletedOrArchivedProject(project.id)
        }
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
}

/// Individual project card with hover effects.
private struct ProjectCardView: View {
    let project: Project
    let onOpen: () -> Void
    let onEdit: () -> Void
    let onArchiveToggle: () -> Void
    let onDelete: () -> Void

    @State private var isHovered = false
    @Environment(\.theme) private var theme

    var body: some View {
        Button(action: onOpen) {
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
        .contextMenu {
            if !project.isArchived {
                Button("Open") {
                    onOpen()
                }
            }

            Button("Edit Settings…") {
                onEdit()
            }

            Divider()

            Button(project.isArchived ? "Unarchive" : "Archive") {
                onArchiveToggle()
            }

            Button("Delete…", role: .destructive) {
                onDelete()
            }
        }
    }
}
