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

    // MARK: - Project Context

    // internal (not private) so tests can reference these values directly
    nonisolated static let projectContextBudgetChars = 32_000  // ~8,000 tokens
    nonisolated static let truncatedPreviewChars = 500
    nonisolated static let maxDiscoveryDepth = 3

    nonisolated static let excludePatterns = [
        "memory/", ".build/", "DerivedData/", "node_modules/",
        "docs/superpowers/", "benchmarks/", "results/",
    ]

    nonisolated private static let tier1Names: Set<String> = ["claude.md", "agents.md", "gemini.md"]
    nonisolated private static let tier2Names: Set<String> = ["tasks.md", "readme.md"]
    nonisolated private static let tier3Names: Set<String> = ["active-projects.md"]

    /// Assign a priority tier (1-6) to a file URL relative to the project root.
    /// Returns nil if the file should not be included (unsupported extension at depth, etc.).
    nonisolated static func priorityTier(for fileURL: URL, relativeTo root: URL) -> Int? {
        let rootComponents = root.standardizedFileURL.pathComponents
        let fileComponents = fileURL.standardizedFileURL.pathComponents
        let relativeComponents = Array(fileComponents.dropFirst(rootComponents.count))

        guard let fileName = relativeComponents.last?.lowercased() else { return nil }
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
    /// Reads project instructions and discovered files within a character budget,
    /// prioritized by tier and sorted by size within each tier.
    public func projectContext(for projectId: UUID) async -> String? {
        guard let project = projects.first(where: { $0.id == projectId }) else { return nil }

        var sections: [String] = []
        var budgetRemaining = Self.projectContextBudgetChars

        // 1. Project instructions (always first, always included)
        if let instructions = project.instructions, !instructions.isEmpty {
            let section = "## Project Instructions\n\n\(instructions)"
            sections.append(section)
            budgetRemaining -= section.count
        }

        // 2. Determine folder URL — prefer security-scoped bookmark
        let folderURL: URL?
        var startedBookmarkAccess = false
        if let bookmarkData = project.folderBookmark {
            var isStale = false
            let url = try? URL(
                resolvingBookmarkData: bookmarkData,
                options: .withSecurityScope,
                relativeTo: nil,
                bookmarkDataIsStale: &isStale
            )
            if let url, !isStale {
                // Only start access if not already accessing (avoids counter leak)
                if !accessingBookmarks.contains(projectId) {
                    startedBookmarkAccess = url.startAccessingSecurityScopedResource()
                }
                folderURL = url
            } else {
                folderURL = project.folderPath.map { URL(fileURLWithPath: $0) }
            }
        } else {
            folderURL = project.folderPath.map { URL(fileURLWithPath: $0) }
        }
        // If we started bookmark access, ensure we stop it when done
        defer {
            if startedBookmarkAccess, let folderURL {
                folderURL.stopAccessingSecurityScopedResource()
            }
        }

        guard let folderURL, budgetRemaining > 0 else {
            return sections.isEmpty ? nil : sections.joined(separator: "\n\n---\n\n")
        }

        // 3. Discover and sort files by priority tier, then size ascending
        let discoveredFiles = Self.discoverProjectFiles(in: folderURL)
        let root = folderURL.standardizedFileURL

        struct RankedFile {
            let url: URL
            let tier: Int
            let size: Int
        }

        let ranked: [RankedFile] = discoveredFiles.compactMap { url in
            guard let tier = Self.priorityTier(for: url, relativeTo: root) else { return nil }
            let size = (try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? Int) ?? 0
            return RankedFile(url: url, tier: tier, size: size)
        }.sorted { a, b in
            if a.tier != b.tier { return a.tier < b.tier }
            return a.size < b.size
        }

        // 4. Read files within budget
        // Use standardized path to match paths returned by discoverProjectFiles (which also standardizes)
        let rootPath = folderURL.standardizedFileURL.path
        for file in ranked {
            guard budgetRemaining > Self.truncatedPreviewChars else { break }

            guard let content = try? String(contentsOf: file.url, encoding: .utf8) else { continue }
            // Use standardized path to strip the root prefix safely
            let filePath = file.url.standardizedFileURL.path
            let relativePath: String
            if filePath.hasPrefix(rootPath) {
                relativePath = String(filePath.dropFirst(rootPath.count))
                    .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            } else {
                relativePath = file.url.lastPathComponent
            }

            if content.count <= budgetRemaining {
                let section = "## \(relativePath)\n\n\(content)"
                sections.append(section)
                budgetRemaining -= section.count
            } else {
                // Truncate: include first N chars + footer
                let preview = String(content.prefix(Self.truncatedPreviewChars))
                let footer = "\n[truncated -- full file at \(relativePath)]"
                let section = "## \(relativePath)\n\n\(preview)\(footer)"
                sections.append(section)
                budgetRemaining -= section.count
            }
        }

        // 5. Bookmark access cleanup handled by defer above

        return sections.isEmpty ? nil : sections.joined(separator: "\n\n---\n\n")
    }

    /// Discover project files (.md and .yaml) with exclusion patterns and depth limit.
    /// Returns file URLs that pass exclusion and depth filters.
    nonisolated static func discoverProjectFiles(in directory: URL) -> [URL] {
        let fm = FileManager.default
        let root = directory.standardizedFileURL
        let rootComponents = root.pathComponents

        guard
            let enumerator = fm.enumerator(
                at: root,
                includingPropertiesForKeys: [.isRegularFileKey],
                options: [.skipsHiddenFiles]
            )
        else { return [] }

        var results: [URL] = []
        for case let fileURL as URL in enumerator {
            let stdURL = fileURL.standardizedFileURL
            let fileComponents = stdURL.pathComponents
            let relativeComponents = Array(fileComponents.dropFirst(rootComponents.count))

            // Check exclusion patterns against relative path
            let excluded = excludePatterns.contains { pattern in
                let dir = pattern.hasSuffix("/") ? String(pattern.dropLast()) : pattern
                return relativeComponents.contains(where: { $0.caseInsensitiveCompare(dir) == .orderedSame })
            }
            if excluded {
                enumerator.skipDescendants()
                continue
            }

            // Check if file has a supported extension and valid tier
            if priorityTier(for: stdURL, relativeTo: root) != nil {
                results.append(fileURL)
            }
        }
        return results
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
