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
    var onFileSelected: ((String) -> Void)?

    @State private var instructionsExpanded = true
    @State private var scheduledExpanded = true
    @State private var contextExpanded = true
    @State private var memoryExpanded = true
    @State private var isEditingInstructions = false
    @State private var instructionsText: String = ""

    @Environment(\.theme) private var theme

    var body: some View {
        SidebarContainer(attachedEdge: .trailing, width: SidebarStyle.inspectorWidth) {
            ScrollView(.vertical, showsIndicators: false) {
                VStack(alignment: .leading, spacing: 0) {
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
                                .padding(.horizontal, 12)
                                .onChange(of: instructionsText) { _, newValue in
                                    var updated = project
                                    updated.instructions = newValue
                                    ProjectManager.shared.updateProject(updated)
                                }
                        } else if let instructions = project.instructions {
                            Text(instructions)
                                .font(.system(size: 12))
                                .foregroundColor(theme.primaryText)
                                .padding(.horizontal, 12)
                        } else {
                            VStack(spacing: 6) {
                                Image(systemName: "pencil.slash")
                                    .font(.system(size: 16))
                                    .foregroundColor(theme.tertiaryText)
                                Text("No instructions set")
                                    .font(.caption)
                                    .foregroundColor(theme.tertiaryText)
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                            .padding(.horizontal, 12)
                        }
                    }

                    Divider()
                        .opacity(0.3)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 8)

                    CollapsibleSection("Scheduled", isExpanded: $scheduledExpanded) {
                        Button(action: { }) {
                            Image(systemName: "plus")
                                .font(.system(size: 11))
                                .foregroundColor(theme.tertiaryText)
                        }
                        .buttonStyle(.plain)
                    } content: {
                        VStack(spacing: 6) {
                            Image(systemName: "calendar.badge.clock")
                                .font(.system(size: 16))
                                .foregroundColor(theme.tertiaryText)
                            Text("No scheduled tasks")
                                .font(.caption)
                                .foregroundColor(theme.tertiaryText)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .padding(.horizontal, 12)
                    }

                    Divider()
                        .opacity(0.3)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 8)

                    CollapsibleSection("Context", isExpanded: $contextExpanded) {
                        Button(action: { }) {
                            Image(systemName: "plus")
                                .font(.system(size: 11))
                                .foregroundColor(theme.tertiaryText)
                        }
                        .buttonStyle(.plain)
                    } content: {
                        if let folderPath = project.folderPath {
                            FolderTreeView(rootPath: folderPath, onFileSelected: onFileSelected)
                                .padding(.horizontal, 12)
                        } else {
                            VStack(spacing: 6) {
                                Image(systemName: "folder.badge.questionmark")
                                    .font(.system(size: 16))
                                    .foregroundColor(theme.tertiaryText)
                                Text("No folder linked")
                                    .font(.caption)
                                    .foregroundColor(theme.tertiaryText)
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                            .padding(.horizontal, 12)
                        }
                    }

                    Divider()
                        .opacity(0.3)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 8)

                    CollapsibleSection("Memory", isExpanded: $memoryExpanded) {
                        MemorySummaryView(projectId: project.id)
                            .padding(.horizontal, 12)
                    }
                }
                .padding(.vertical, 12)
            }
        }
        .onAppear {
            instructionsText = project.instructions ?? ""
        }
    }
}
