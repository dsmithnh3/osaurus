//
//  ProjectEditorSheet.swift
//  osaurus
//
//  Sheet for creating or editing a project.
//

import AppKit
import SwiftUI

/// Sheet for creating or editing a project.
struct ProjectEditorSheet: View {
    var existingProject: Project? = nil
    let onSave: (Project) -> Void

    @State private var name = ""
    @State private var description = ""
    @State private var icon = "folder.fill"
    @State private var color = ""
    @State private var folderPath: String? = nil
    @State private var folderBookmark: Data? = nil

    @Environment(\.dismiss) private var dismiss
    @Environment(\.theme) private var theme

    var body: some View {
        VStack(spacing: 20) {
            Text(existingProject != nil ? "Edit Project" : "New Project")
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

            HStack {
                Button("Cancel") { dismiss() }
                    .buttonStyle(.bordered)
                Spacer()
                Button(existingProject != nil ? "Save" : "Create") { save() }
                    .buttonStyle(.borderedProminent)
                    .tint(theme.accentColor)
                    .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding(24)
        .frame(minWidth: 400, minHeight: 300)
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
            existing.name = name
            existing.description = description.isEmpty ? nil : description
            existing.icon = icon
            existing.color = color.isEmpty ? nil : color
            existing.folderPath = folderPath
            existing.folderBookmark = folderBookmark
            ProjectManager.shared.updateProject(existing)
            onSave(existing)
        } else {
            let project = ProjectManager.shared.createProject(
                name: name,
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
}
