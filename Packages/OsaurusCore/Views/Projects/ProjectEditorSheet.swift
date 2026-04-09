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
                .font(.headline)

            VStack(alignment: .leading, spacing: 12) {
                TextField("Project name", text: $name)
                    .textFieldStyle(.roundedBorder)

                TextField("Description (optional)", text: $description)
                    .textFieldStyle(.roundedBorder)

                HStack {
                    Text("Folder:")
                        .font(.system(size: 12))
                    Text(folderPath ?? "None selected")
                        .font(.system(size: 12))
                        .foregroundColor(theme.secondaryText)
                        .lineLimit(1)
                    Spacer()
                    Button("Choose...") { pickFolder() }
                        .buttonStyle(.bordered)
                }
            }

            HStack {
                Button("Cancel") { dismiss() }
                    .buttonStyle(.bordered)
                Spacer()
                Button(existingProject != nil ? "Save" : "Create") { save() }
                    .buttonStyle(.borderedProminent)
                    .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding(24)
        .frame(width: 400)
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
