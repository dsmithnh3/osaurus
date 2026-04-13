//
//  ProjectInspectorPanel.swift
//  osaurus
//
//  Right inspector panel for project details.
//

import SwiftUI

/// Right inspector panel for project details — instructions, scheduled, outputs, context, memory.
struct ProjectInspectorPanel: View {
    let project: Project
    var onFileSelected: ((String) -> Void)?
    var onArtifactSelected: ((SharedArtifact) -> Void)?

    @State private var instructionsExpanded = true
    @State private var scheduledExpanded = true
    @State private var outputsExpanded = true
    @State private var contextExpanded = true
    @State private var memoryExpanded = true
    @State private var isEditingInstructions = false
    @State private var instructionsText: String = ""

    @State private var projectArtifacts: [SharedArtifact] = []
    @State private var folderOutputFiles: [SharedArtifact] = []
    @State private var saveTask: Task<Void, Never>?
    @State private var showingScheduleEditor = false
    @State private var dragStartWidth: Double?

    @AppStorage("inspectorWidth") private var inspectorWidth: Double = Double(
        SidebarStyle.inspectorWidth
    )

    @Environment(\.theme) private var theme

    var body: some View {
        HStack(spacing: 0) {
            // Drag handle for resizing
            Rectangle()
                .fill(Color.clear)
                .frame(width: 6)
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 1)
                        .onChanged { value in
                            if dragStartWidth == nil { dragStartWidth = inspectorWidth }
                            let newWidth =
                                (dragStartWidth ?? inspectorWidth)
                                - Double(value.translation.width)
                            inspectorWidth = max(220, min(newWidth, 400))
                        }
                        .onEnded { _ in dragStartWidth = nil }
                )
                .onHover { hovering in
                    if hovering { NSCursor.resizeLeftRight.push() } else { NSCursor.pop() }
                }

            SidebarContainer(attachedEdge: .trailing, width: CGFloat(inspectorWidth)) {
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
                                    .onChange(of: instructionsText) { _, newValue in
                                        saveTask?.cancel()
                                        saveTask = Task {
                                            try? await Task.sleep(for: .milliseconds(500))
                                            guard !Task.isCancelled else { return }
                                            var updated = project
                                            updated.instructions = newValue
                                            ProjectManager.shared.updateProject(updated)
                                        }
                                    }
                            } else if let instructions = project.instructions {
                                Text(instructions)
                                    .font(.system(size: 12))
                                    .foregroundColor(theme.primaryText)
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
                            }
                        }

                        Divider()
                            .opacity(0.3)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 8)

                        CollapsibleSection("Scheduled", isExpanded: $scheduledExpanded) {
                            Button(action: { showingScheduleEditor = true }) {
                                Image(systemName: "plus")
                                    .font(.system(size: 11))
                                    .foregroundColor(theme.tertiaryText)
                            }
                            .buttonStyle(.plain)
                        } content: {
                            if projectSchedules.isEmpty {
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
                            } else {
                                VStack(alignment: .leading, spacing: 4) {
                                    ForEach(projectSchedules) { schedule in
                                        ScheduleRowView(schedule: schedule)
                                    }
                                }
                            }
                        }
                        .sheet(isPresented: $showingScheduleEditor) {
                            ScheduleEditorSheet(
                                mode: .create,
                                onSave: { schedule in
                                    ScheduleManager.shared.create(
                                        name: schedule.name,
                                        instructions: schedule.instructions,
                                        agentId: schedule.agentId,
                                        mode: schedule.mode,
                                        parameters: schedule.parameters,
                                        folderPath: schedule.folderPath ?? project.folderPath,
                                        folderBookmark: schedule.folderBookmark
                                            ?? project.folderBookmark,
                                        frequency: schedule.frequency,
                                        isEnabled: schedule.isEnabled,
                                        projectId: project.id
                                    )
                                    showingScheduleEditor = false
                                },
                                onCancel: { showingScheduleEditor = false },
                                initialProjectId: project.id
                            )
                        }

                        Divider()
                            .opacity(0.3)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 8)

                        CollapsibleSection("Outputs", isExpanded: $outputsExpanded) {
                            if projectArtifacts.isEmpty && folderOutputFiles.isEmpty {
                                VStack(spacing: 6) {
                                    Image(systemName: "doc.richtext")
                                        .font(.system(size: 16))
                                        .foregroundColor(theme.tertiaryText)
                                    Text("No outputs yet")
                                        .font(.caption)
                                        .foregroundColor(theme.tertiaryText)
                                }
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 12)
                            } else {
                                VStack(alignment: .leading, spacing: 8) {
                                    if !projectArtifacts.isEmpty {
                                        VStack(alignment: .leading, spacing: 4) {
                                            ForEach(projectArtifacts) { artifact in
                                                outputArtifactRow(artifact)
                                            }
                                        }
                                    }

                                    if !folderOutputFiles.isEmpty {
                                        Text("Files")
                                            .font(.system(size: 10, weight: .semibold))
                                            .foregroundColor(theme.tertiaryText)
                                            .textCase(.uppercase)

                                        VStack(alignment: .leading, spacing: 4) {
                                            ForEach(folderOutputFiles) { artifact in
                                                outputArtifactRow(artifact)
                                            }
                                        }
                                    }
                                }
                            }
                        }

                        Divider()
                            .opacity(0.3)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 8)

                        CollapsibleSection("Context", isExpanded: $contextExpanded) {
                            Menu {
                                Button(action: { pickFiles() }) {
                                    Label("Add Files...", systemImage: "doc.badge.plus")
                                }
                                Button(action: { pickFolder() }) {
                                    Label("Add Folder...", systemImage: "folder.badge.plus")
                                }
                            } label: {
                                Image(systemName: "plus")
                                    .font(.system(size: 11))
                                    .foregroundColor(theme.tertiaryText)
                            }
                            .menuStyle(.borderlessButton)
                            .menuIndicator(.hidden)
                            .frame(width: 16)
                        } content: {
                            VStack(alignment: .leading, spacing: 8) {
                                if let entries = project.contextEntries, !entries.isEmpty {
                                    PinnedContextView(
                                        entries: entries,
                                        onRemove: { removeContextEntry($0) },
                                        onFileSelected: onFileSelected
                                    )
                                }

                                if let folderPath = project.folderPath {
                                    FolderTreeView(
                                        rootPath: folderPath,
                                        onFileSelected: onFileSelected
                                    )
                                } else if (project.contextEntries ?? []).isEmpty {
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
                                }
                            }
                        }

                        Divider()
                            .opacity(0.3)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 8)

                        CollapsibleSection("Memory", isExpanded: $memoryExpanded) {
                            MemorySummaryView(projectId: project.id)
                        }
                    }
                    .padding(.vertical, 12)
                }
            }
            .onAppear {
                instructionsText = project.instructions ?? ""
                loadArtifacts()
            }
            .onChange(of: project.id) { _, _ in
                instructionsText = project.instructions ?? ""
                isEditingInstructions = false
                loadArtifacts()
            }
            .onChange(of: isEditingInstructions) { _, editing in
                if !editing {
                    saveTask?.cancel()
                    var updated = project
                    updated.instructions = instructionsText
                    ProjectManager.shared.updateProject(updated)
                }
            }
        }
    }

    // MARK: - Data Loading

    private static let outputExtensions: Set<String> = [
        "pdf", "png", "jpg", "jpeg", "gif", "svg",
        "html", "htm", "csv", "xlsx", "docx", "pptx",
    ]

    private func loadArtifacts() {
        if WorkDatabase.shared.isOpen {
            let tasks = (try? IssueStore.listTasks(projectId: project.id)) ?? []
            projectArtifacts = tasks.flatMap { task in
                (try? IssueStore.listSharedArtifacts(contextId: task.id)) ?? []
            }
        } else {
            projectArtifacts = []
        }
        scanOutputFiles()
    }

    private func scanOutputFiles() {
        guard let folderPath = project.folderPath else {
            folderOutputFiles = []
            return
        }
        let fm = FileManager.default
        let rootURL = URL(fileURLWithPath: folderPath)
        let existingPaths = Set(projectArtifacts.map(\.hostPath))
        var results: [SharedArtifact] = []

        // Scan root level
        let rootFiles =
            (try? fm.contentsOfDirectory(
                at: rootURL,
                includingPropertiesForKeys: [.isRegularFileKey, .isDirectoryKey],
                options: .skipsHiddenFiles
            )) ?? []

        for url in rootFiles {
            let isDir =
                (try? url.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory ?? false
            if isDir { continue }
            let ext = url.pathExtension.lowercased()
            guard Self.outputExtensions.contains(ext) else { continue }
            guard !existingPaths.contains(url.path) else { continue }
            if let artifact = SharedArtifact.fromFilePath(url.path) {
                results.append(artifact)
            }
        }

        // Scan one level deep
        let subdirs = rootFiles.filter {
            (try? $0.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true
        }
        for subdir in subdirs {
            guard !excludedDirectoryNames.contains(subdir.lastPathComponent) else { continue }
            let subFiles =
                (try? fm.contentsOfDirectory(
                    at: subdir,
                    includingPropertiesForKeys: [.isRegularFileKey],
                    options: .skipsHiddenFiles
                )) ?? []
            for url in subFiles {
                let ext = url.pathExtension.lowercased()
                guard Self.outputExtensions.contains(ext) else { continue }
                guard !existingPaths.contains(url.path) else { continue }
                if let artifact = SharedArtifact.fromFilePath(url.path) {
                    results.append(artifact)
                }
            }
        }

        folderOutputFiles = results
    }

    // MARK: - Schedules

    private var projectSchedules: [Schedule] {
        ScheduleManager.shared.schedules.filter { $0.projectId == project.id }
    }

    // MARK: - Context Pinning

    private func pickFiles() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = true
        panel.message = "Select files to pin to project context"

        guard panel.runModal() == .OK else { return }
        addContextEntries(from: panel.urls, isDirectory: false)
    }

    private func pickFolder() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = true
        panel.message = "Select folders to pin to project context"

        guard panel.runModal() == .OK else { return }
        addContextEntries(from: panel.urls, isDirectory: true)
    }

    private func addContextEntries(from urls: [URL], isDirectory: Bool) {
        var updated = project
        var entries = updated.contextEntries ?? []
        for url in urls {
            let bookmark = try? url.bookmarkData(
                options: .withSecurityScope,
                includingResourceValuesForKeys: nil,
                relativeTo: nil
            )
            let entry = ProjectContextEntry(
                path: url.path,
                bookmark: bookmark,
                isDirectory: isDirectory
            )
            entries.append(entry)
        }
        updated.contextEntries = entries
        ProjectManager.shared.updateProject(updated)
    }

    private func removeContextEntry(_ id: UUID) {
        var updated = project
        var entries = updated.contextEntries ?? []
        entries.removeAll { $0.id == id }
        updated.contextEntries = entries.isEmpty ? nil : entries
        ProjectManager.shared.updateProject(updated)
    }

    // MARK: - Helpers

    @ViewBuilder
    private func outputArtifactRow(_ artifact: SharedArtifact) -> some View {
        Button {
            onArtifactSelected?(artifact)
        } label: {
            HStack(spacing: 8) {
                Image(systemName: iconForMimeType(artifact.mimeType))
                    .foregroundStyle(theme.accentColor)
                Text(artifact.filename)
                    .font(.caption)
                    .lineLimit(1)
                Spacer()
                Text(
                    ByteCountFormatter.string(
                        fromByteCount: Int64(artifact.fileSize),
                        countStyle: .file
                    )
                )
                .font(.caption2)
                .foregroundStyle(theme.tertiaryText)
            }
        }
        .buttonStyle(.plain)
    }

    private func iconForMimeType(_ mimeType: String) -> String {
        switch mimeType {
        case let m where m.hasPrefix("image/"): return "photo"
        case let m where m.hasPrefix("text/html"): return "globe"
        case let m where m.contains("pdf"): return "doc.richtext"
        case let m where m.hasPrefix("text/"): return "doc.text"
        default: return "doc"
        }
    }
}

// MARK: - Schedule Row

private struct ScheduleRowView: View {
    let schedule: Schedule

    @Environment(\.theme) private var theme

    var body: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(schedule.isEnabled ? Color.green : theme.tertiaryText)
                .frame(width: 6, height: 6)

            Text(schedule.name)
                .font(.system(size: 11))
                .foregroundColor(theme.primaryText)
                .lineLimit(1)

            Spacer()

            Text(schedule.frequency.shortDescription)
                .font(.system(size: 9))
                .foregroundColor(theme.secondaryText)
                .padding(.horizontal, 4)
                .padding(.vertical, 1)
                .background(
                    Capsule().fill(theme.secondaryBackground.opacity(0.5))
                )
        }
    }
}
