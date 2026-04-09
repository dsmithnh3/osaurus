//
//  ProjectInspectorPanel.swift
//  osaurus
//
//  Right inspector panel for project details.
//

import SwiftUI

/// Right inspector panel for project details — instructions, scheduled, context, memory.
struct ProjectInspectorPanel: View {
    let project: Project

    @State private var instructionsExpanded = true
    @State private var scheduledExpanded = true
    @State private var contextExpanded = true
    @State private var memoryExpanded = true
    @State private var isEditingInstructions = false
    @State private var instructionsText: String = ""

    @Environment(\.theme) private var theme

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 4) {
                CollapsibleSection("Instructions", isExpanded: $instructionsExpanded) {
                    Button(action: { isEditingInstructions.toggle() }) {
                        Image(systemName: "pencil")
                            .font(.system(size: 11))
                            .foregroundColor(theme.tertiaryText)
                    }
                    .buttonStyle(.plain)
                } content: {
                    if isEditingInstructions {
                        TextEditor(text: $instructionsText)
                            .font(.system(size: 12))
                            .scrollContentBackground(.hidden)
                            .frame(minHeight: 80)
                            .onChange(of: instructionsText) { _, newValue in
                                var updated = project
                                updated.instructions = newValue
                                ProjectManager.shared.updateProject(updated)
                            }
                    } else {
                        Text(project.instructions ?? "No instructions set")
                            .font(.system(size: 12))
                            .foregroundColor(project.instructions != nil ? theme.primaryText : theme.tertiaryText)
                    }
                }

                Divider().padding(.horizontal, 8)

                CollapsibleSection("Scheduled", isExpanded: $scheduledExpanded) {
                    Button(action: { }) {
                        Image(systemName: "plus")
                            .font(.system(size: 11))
                            .foregroundColor(theme.tertiaryText)
                    }
                    .buttonStyle(.plain)
                } content: {
                    Text("No scheduled tasks")
                        .font(.system(size: 12))
                        .foregroundColor(theme.tertiaryText)
                }

                Divider().padding(.horizontal, 8)

                CollapsibleSection("Context", isExpanded: $contextExpanded) {
                    Button(action: { }) {
                        Image(systemName: "plus")
                            .font(.system(size: 11))
                            .foregroundColor(theme.tertiaryText)
                    }
                    .buttonStyle(.plain)
                } content: {
                    if let folderPath = project.folderPath {
                        FolderTreeView(rootPath: folderPath)
                    } else {
                        Text("No folder linked")
                            .font(.system(size: 12))
                            .foregroundColor(theme.tertiaryText)
                    }
                }

                Divider().padding(.horizontal, 8)

                CollapsibleSection("Memory", isExpanded: $memoryExpanded) {
                    MemorySummaryView(projectId: project.id)
                }
            }
            .padding(.vertical, 12)
        }
        .frame(maxHeight: .infinity)
        .background(theme.secondaryBackground.opacity(0.5))
        .overlay(
            Rectangle()
                .frame(width: 1)
                .foregroundColor(theme.primaryBorder.opacity(0.2)),
            alignment: .leading
        )
        .onAppear {
            instructionsText = project.instructions ?? ""
        }
    }
}
