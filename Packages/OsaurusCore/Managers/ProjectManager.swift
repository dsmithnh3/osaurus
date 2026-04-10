//
//  ProjectManager.swift
//  osaurus
//
//  Manages project lifecycle, context building, and security-scoped bookmark access.
//

import Foundation
import Observation

/// Manages project lifecycle, context building, and security-scoped bookmark access.
@Observable
@MainActor
public final class ProjectManager {
    public static let shared = ProjectManager()

    public private(set) var projects: [Project] = []
    public var activeProjectId: UUID?

    /// Set of project IDs whose folder bookmarks are currently being accessed.
    private var accessingBookmarks: Set<UUID> = []

    public var activeProject: Project? {
        projects.first { $0.id == activeProjectId }
    }

    public var activeProjects: [Project] {
        projects.filter { $0.isActive && !$0.isArchived }
    }

    private init() {
        reload()
    }

    // MARK: - CRUD

    @discardableResult
    public func createProject(
        name: String,
        description: String? = nil,
        icon: String = "folder.fill",
        color: String? = nil,
        folderPath: String? = nil,
        folderBookmark: Data? = nil,
        instructions: String? = nil
    ) -> Project {
        let project = Project(
            name: name,
            description: description,
            icon: icon,
            color: color,
            folderPath: folderPath,
            folderBookmark: folderBookmark,
            instructions: instructions
        )
        ProjectStore.save(project)
        reload()
        return project
    }

    public func updateProject(_ project: Project) {
        var updated = project
        updated.updatedAt = Date()
        ProjectStore.save(updated)
        reload()
    }

    public func deleteProject(id: UUID) {
        stopAccessingBookmark(for: id)
        ProjectStore.delete(id: id)
        if activeProjectId == id { activeProjectId = nil }
        reload()
    }

    public func archiveProject(id: UUID) {
        guard var project = projects.first(where: { $0.id == id }) else { return }
        project.isArchived = true
        project.isActive = false
        updateProject(project)
    }

    public func reload() {
        projects = ProjectStore.loadAll()
    }

    // MARK: - Context

    // MARK: - Project Context Constants

    // internal (not private) so tests can reference these values directly
    nonisolated(unsafe) static let projectContextBudgetChars = 32_000  // ~8,000 tokens
    nonisolated(unsafe) static let truncatedPreviewChars = 500
    nonisolated(unsafe) static let maxDiscoveryDepth = 3

    nonisolated(unsafe) static let excludePatterns = [
        "memory/", ".build/", "DerivedData/", "node_modules/",
        "docs/superpowers/", "benchmarks/", "results/",
    ]

    nonisolated(unsafe) private static let tier1Names: Set<String> = ["claude.md", "agents.md", "gemini.md"]
    nonisolated(unsafe) private static let tier2Names: Set<String> = ["tasks.md", "readme.md"]
    nonisolated(unsafe) private static let tier3Names: Set<String> = ["active-projects.md"]

    /// Assign a priority tier (1-6) to a file URL relative to the project root.
    /// Returns nil if the file should not be included (unsupported extension at depth, etc.).
    nonisolated static func priorityTier(for fileURL: URL, relativeTo root: URL) -> Int? {
        let rootComponents = root.standardizedFileURL.pathComponents
        let fileComponents = fileURL.standardizedFileURL.pathComponents
        let relativeComponents = Array(fileComponents.dropFirst(rootComponents.count))

        guard !relativeComponents.isEmpty else { return nil }

        let fileName = relativeComponents.last!.lowercased()
        let depth = relativeComponents.count - 1  // 0 = root level

        let ext = fileURL.pathExtension.lowercased()
        let isMd = ext == "md"
        let isYaml = ext == "yaml" || ext == "yml"

        // Tier 1-3: known filenames (case-insensitive), must be at root (depth 0)
        if depth == 0 {
            if isMd && tier1Names.contains(fileName) { return 1 }
            if isMd && tier2Names.contains(fileName) { return 2 }
            if isMd && tier3Names.contains(fileName) { return 3 }
        }

        // Tier 4: yaml in root (depth 0) or direct config/ child (depth 1, parent is "config")
        if isYaml {
            if depth == 0 { return 4 }
            if depth == 1 && relativeComponents.first?.lowercased() == "config" { return 4 }
            return nil  // deeper yaml files excluded
        }

        // Tier 5: other root-level .md
        if isMd && depth == 0 { return 5 }

        // Tier 6: deeper .md (depth 1-3)
        if isMd && depth >= 1 && depth <= maxDiscoveryDepth { return 6 }

        return nil
    }

    /// Build the project context string for system prompt injection.
    /// Includes project instructions and all .md files from the project folder.
    public func projectContext(for projectId: UUID) async -> String? {
        guard let project = projects.first(where: { $0.id == projectId }) else { return nil }

        var sections: [String] = []

        if let instructions = project.instructions, !instructions.isEmpty {
            sections.append("## Project Instructions\n\n\(instructions)")
        }

        // Scan .md files from project folder
        if let folderPath = project.folderPath {
            let folderURL = URL(fileURLWithPath: folderPath)
            let mdFiles = discoverMarkdownFiles(in: folderURL)
            for fileURL in mdFiles {
                if let content = try? String(contentsOf: fileURL, encoding: .utf8) {
                    let relativePath = fileURL.path.replacingOccurrences(of: folderPath, with: "")
                    sections.append("## \(relativePath)\n\n\(content)")
                }
            }
        }

        return sections.isEmpty ? nil : sections.joined(separator: "\n\n---\n\n")
    }

    /// Discover all .md files recursively in a directory.
    public func discoverMarkdownFiles(in directory: URL) -> [URL] {
        let fm = FileManager.default
        guard let enumerator = fm.enumerator(
            at: directory,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else { return [] }

        var results: [URL] = []
        for case let fileURL as URL in enumerator {
            if fileURL.pathExtension.lowercased() == "md" {
                results.append(fileURL)
            }
        }
        return results.sorted { $0.path < $1.path }
    }

    // MARK: - Security-Scoped Bookmark Lifecycle

    /// Start accessing the project's folder bookmark. Call when entering a project.
    public func startAccessingBookmark(for projectId: UUID) {
        guard !accessingBookmarks.contains(projectId),
            let project = projects.first(where: { $0.id == projectId }),
            let bookmarkData = project.folderBookmark
        else { return }

        var isStale = false
        guard
            let url = try? URL(
                resolvingBookmarkData: bookmarkData,
                options: .withSecurityScope,
                relativeTo: nil,
                bookmarkDataIsStale: &isStale
            )
        else { return }

        if isStale {
            print("[Osaurus] Bookmark stale for project \(project.name) — re-authorization needed")
            return
        }

        if url.startAccessingSecurityScopedResource() {
            accessingBookmarks.insert(projectId)
        }
    }

    /// Stop accessing the project's folder bookmark. Call when leaving a project.
    public func stopAccessingBookmark(for projectId: UUID) {
        guard accessingBookmarks.contains(projectId),
            let project = projects.first(where: { $0.id == projectId }),
            let bookmarkData = project.folderBookmark
        else {
            accessingBookmarks.remove(projectId)
            return
        }

        var isStale = false
        if let url = try? URL(
            resolvingBookmarkData: bookmarkData,
            options: .withSecurityScope,
            relativeTo: nil,
            bookmarkDataIsStale: &isStale
        ) {
            url.stopAccessingSecurityScopedResource()
        }
        accessingBookmarks.remove(projectId)
    }

    /// Set the active project. Manages bookmark lifecycle automatically.
    public func setActiveProject(_ projectId: UUID?) {
        if let current = activeProjectId {
            stopAccessingBookmark(for: current)
        }
        activeProjectId = projectId
        if let projectId {
            startAccessingBookmark(for: projectId)
        }
    }
}
