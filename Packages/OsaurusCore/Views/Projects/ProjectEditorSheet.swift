//
//  ProjectEditorSheet.swift
//  osaurus
//
//  Sheet for creating or editing a project.
//

import AppKit
import SwiftUI

enum ProjectEditorPresentation: Identifiable, Equatable {
    case create
    case edit(UUID)

    var id: String {
        switch self {
        case .create:
            return "create"
        case .edit(let projectId):
            return "edit-\(projectId.uuidString)"
        }
    }

    func project(from projects: [Project]) -> Project? {
        guard case .edit(let projectId) = self else { return nil }
        return projects.first(where: { $0.id == projectId })
    }
}

enum ProjectManagementAction: String, CaseIterable, Equatable {
    case open
    case editSettings
    case archive
    case unarchive
    case delete

    static func available(for project: Project) -> [ProjectManagementAction] {
        if project.isArchived {
            return [.editSettings, .unarchive, .delete]
        }
        return [.open, .editSettings, .archive, .delete]
    }
}

enum ProjectManagementSelection {
    static func normalizedProjectId(_ projectId: UUID?, in projects: [Project]) -> UUID? {
        guard let projectId else { return nil }
        return projects.contains(where: { $0.id == projectId }) ? projectId : nil
    }
}

/// Sheet for creating or editing a project.
struct ProjectEditorSheet: View {
    var existingProject: Project? = nil
    let onSave: (Project) -> Void
    var onArchiveToggle: ((Project) -> Void)? = nil
    var onDelete: ((Project) -> Void)? = nil

    @State private var name = ""
    @State private var description = ""
    @State private var icon = "folder.fill"
    @State private var color = ""
    @State private var folderPath: String? = nil
    @State private var folderBookmark: Data? = nil
    @State private var isDeleteConfirmationPresented = false

    @Environment(\.dismiss) private var dismiss
    @Environment(\.theme) private var theme

    private var isEditingExistingProject: Bool {
        existingProject != nil
    }

    private var trimmedName: String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text(isEditingExistingProject ? "Project Settings" : "New Project")
                .font(.system(size: 18, weight: .semibold))
                .foregroundColor(theme.primaryText)

            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Project name")
                        .font(.caption)
                        .foregroundColor(theme.secondaryText)
                    TextField("e.g., Website Redesign", text: $name)
                        .textFieldStyle(.roundedBorder)
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text("Description")
                        .font(.caption)
                        .foregroundColor(theme.secondaryText)
                    TextField("Optional description", text: $description)
                        .textFieldStyle(.roundedBorder)
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text("Folder")
                        .font(.caption)
                        .foregroundColor(theme.secondaryText)
                    Button(action: { pickFolder() }) {
                        HStack(spacing: 6) {
                            Image(systemName: "folder")
                                .font(.system(size: 12))
                                .foregroundColor(theme.secondaryText)
                            Text(folderPath ?? "No folder selected")
                                .font(.system(size: 12))
                                .foregroundColor(folderPath != nil ? theme.primaryText : theme.tertiaryText)
                                .lineLimit(1)
                                .truncationMode(.middle)
                            Spacer()
                            Text("Choose...")
                                .font(.system(size: 11, weight: .medium))
                                .foregroundColor(theme.accentColor)
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 8)
                        .background(
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .fill(theme.inputBackground)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                                        .strokeBorder(theme.inputBorder, lineWidth: 1)
                                )
                        )
                    }
                    .buttonStyle(.plain)
                }
            }

            if let existingProject {
                managementSection(for: existingProject)
            }

            HStack {
                Button("Cancel") { dismiss() }
                    .buttonStyle(.bordered)
                Spacer()
                Button(isEditingExistingProject ? "Save" : "Create") { save() }
                    .buttonStyle(.borderedProminent)
                    .tint(theme.accentColor)
                    .disabled(trimmedName.isEmpty)
            }
        }
        .padding(24)
        .frame(minWidth: 420, minHeight: 340)
        .onAppear {
            if let existing = existingProject {
                name = existing.name
                description = existing.description ?? ""
                icon = existing.icon
                color = existing.color ?? ""
                folderPath = existing.folderPath
                folderBookmark = existing.folderBookmark
            }
        }
        .alert(
            "Delete Project?",
            isPresented: $isDeleteConfirmationPresented,
            presenting: existingProject
        ) { project in
            Button("Delete", role: .destructive) {
                onDelete?(project)
                dismiss()
            }
            Button("Cancel", role: .cancel) {}
        } message: { project in
            Text(
                "Delete \"\(project.name)\" from Osaurus. Its linked folder and project memory will be left untouched."
            )
        }
    }

    private func pickFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.message = "Choose a project folder"

        if panel.runModal() == .OK, let url = panel.url {
            folderPath = url.path
            folderBookmark = try? url.bookmarkData(
                options: .withSecurityScope,
                includingResourceValuesForKeys: nil,
                relativeTo: nil
            )
        }
    }

    private func save() {
        if var existing = existingProject {
            existing.name = trimmedName
            existing.description = description.isEmpty ? nil : description
            existing.icon = icon
            existing.color = color.isEmpty ? nil : color
            existing.folderPath = folderPath
            existing.folderBookmark = folderBookmark
            ProjectManager.shared.updateProject(existing)
            onSave(existing)
        } else {
            let project = ProjectManager.shared.createProject(
                name: trimmedName,
                description: description.isEmpty ? nil : description,
                icon: icon,
                color: color.isEmpty ? nil : color,
                folderPath: folderPath,
                folderBookmark: folderBookmark
            )
            onSave(project)
        }
        dismiss()
    }

    @ViewBuilder
    private func managementSection(for project: Project) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Management")
                .font(.caption)
                .foregroundColor(theme.secondaryText)

            HStack(spacing: 10) {
                Button(project.isArchived ? "Unarchive Project" : "Archive Project") {
                    onArchiveToggle?(project)
                    dismiss()
                }
                .buttonStyle(.bordered)

                Button("Delete Project…", role: .destructive) {
                    isDeleteConfirmationPresented = true
                }
                .buttonStyle(.bordered)
            }

            Text(
                project.isArchived
                    ? "Unarchiving returns the project to active lists. Watchers and schedules remain disabled until re-enabled manually."
                    : "Archiving removes the project from active lists and disables its watchers and schedules without touching its folder or memory."
            )
            .font(.system(size: 11))
            .foregroundColor(theme.tertiaryText)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(theme.cardBackground.opacity(0.3))
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .strokeBorder(theme.cardBorder.opacity(0.2), lineWidth: 1)
                )
        )
    }
}
