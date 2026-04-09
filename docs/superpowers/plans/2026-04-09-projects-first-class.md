# Projects as a First-Class Concept — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add Projects as a third mode alongside Chat and Work — an organizational container that groups conversations, tasks, schedules, watchers, and memory under a shared context with folder, instructions, and scoped memory.

**Architecture:** Layer 1 builds data model and persistence (Project, ProjectStore, DB migrations, memory scoping). Layer 2 wires navigation (ChatMode extension, toolbar, navigation stack, sidebar). Layer 3 builds the project UI (3-panel layout with inspector). Layer 4 connects system prompt injection and memory integration. Each layer produces testable, committable increments.

**Tech Stack:** Swift 6.2, SwiftUI + AppKit hybrid, SQLite (raw via OpaquePointer), VecturaKit, security-scoped bookmarks, OsaurusPaths

**Spec:** `docs/superpowers/specs/2026-04-09-projects-first-class-design.md`

---

## File Map

### New Files

| File                                                                | Purpose                                                                     |
| ------------------------------------------------------------------- | --------------------------------------------------------------------------- |
| `Packages/OsaurusCore/Models/Project/Project.swift`                 | Project data model                                                          |
| `Packages/OsaurusCore/Models/Project/ProjectStore.swift`            | JSON file persistence (follows AgentStore pattern)                          |
| `Packages/OsaurusCore/Managers/ProjectManager.swift`                | @Observable @MainActor manager — CRUD, context building, bookmark lifecycle |
| `Packages/OsaurusCore/Views/Projects/ProjectView.swift`             | 3-panel coordinator view                                                    |
| `Packages/OsaurusCore/Views/Projects/ProjectHomeView.swift`         | Center panel — header, input, outputs, recents                              |
| `Packages/OsaurusCore/Views/Projects/ProjectInspectorPanel.swift`   | Right panel — instructions, scheduled, context, memory                      |
| `Packages/OsaurusCore/Views/Projects/ProjectListView.swift`         | Grid of projects with search + "New project" button                         |
| `Packages/OsaurusCore/Views/Projects/ProjectEditorSheet.swift`      | Create/edit project sheet (name, icon, color, folder)                       |
| `Packages/OsaurusCore/Views/Projects/FolderTreeView.swift`          | Recursive directory tree browser                                            |
| `Packages/OsaurusCore/Views/Projects/MemorySummaryView.swift`       | Compact memory entry list for inspector                                     |
| `Packages/OsaurusCore/Views/Common/CollapsibleSection.swift`        | Reusable collapsible header + content                                       |
| `Packages/OsaurusCore/Views/Sidebar/AppSidebar.swift`               | Unified sidebar replacing Chat/Work sidebars                                |
| `Packages/OsaurusCore/Views/Sidebar/SidebarNavRow.swift`            | Nav item component for sidebar                                              |
| `Packages/OsaurusCore/Tests/Project/ProjectStoreTests.swift`        | ProjectStore persistence tests                                              |
| `Packages/OsaurusCore/Tests/Project/ProjectManagerTests.swift`      | ProjectManager CRUD + context tests                                         |
| `Packages/OsaurusCore/Tests/Project/ProjectNavigationTests.swift`   | Navigation stack + mode switching tests                                     |
| `Packages/OsaurusCore/Tests/Memory/MemoryProjectScopingTests.swift` | Memory scoping with project_id tests                                        |

### Modified Files

| File                                           | Lines          | Change                                                                                     |
| ---------------------------------------------- | -------------- | ------------------------------------------------------------------------------------------ |
| `Models/Chat/ChatMode.swift`                   | 11-30          | Add `.project` case                                                                        |
| `Managers/Chat/ChatWindowState.swift`          | 23-67, 179-203 | Add ProjectSession struct, @Published properties, navigation stack, extend switchMode      |
| `Views/Common/SharedHeaderComponents.swift`    | 45-94          | Refactor ModeToggleButton: add `.project` segment, change callback to `(ChatMode) -> Void` |
| `Managers/Chat/ChatWindowManager.swift`        | 615-741        | Add back/forward toolbar items, update ModeToggleButton call site                          |
| `Views/Chat/ChatView.swift`                    | ~1292          | Add `.project` routing branch in body                                                      |
| `Models/Chat/ChatSessionData.swift`            | 11-85          | Add `var projectId: UUID?`                                                                 |
| `Models/Schedule/Schedule.swift`               | 310-481        | Add `var projectId: UUID?`                                                                 |
| `Models/Watcher/Watcher.swift`                 | 65-219         | Add `var projectId: UUID?`                                                                 |
| `Models/Work/WorkModels.swift`                 | 385+           | Add `var projectId: UUID?` to WorkTask                                                     |
| `Storage/WorkDatabase.swift`                   | 38, 128-147    | Update schemaVersion to 5, add V5 migration                                                |
| `Storage/MemoryDatabase.swift`                 | 34, 76+        | Update schemaVersion to 4, add V4 migration                                                |
| `Services/Memory/MemoryService.swift`          | 33-39          | Add `projectId: String?` param to recordConversationTurn                                   |
| `Services/Memory/MemoryContextAssembler.swift` | 27-76          | Add projectId param, update cache key to composite                                         |
| `Services/Chat/SystemPromptComposer.swift`     | 44-66, 91-136  | Add project context injection after base prompt                                            |
| `Utils/OsaurusPaths.swift`                     | 70+            | Add `projects()` directory function                                                        |

---

## Task 1: Project Data Model & Store

**Files:**

- Create: `Packages/OsaurusCore/Models/Project/Project.swift`
- Create: `Packages/OsaurusCore/Models/Project/ProjectStore.swift`
- Modify: `Packages/OsaurusCore/Utils/OsaurusPaths.swift:70+`
- Test: `Packages/OsaurusCore/Tests/Project/ProjectStoreTests.swift`

- [ ] **Step 1: Write the failing test for Project model encoding**

```swift
// Tests/Project/ProjectStoreTests.swift
import Foundation
import Testing

@testable import OsaurusCore

@Suite("ProjectStore Tests")
struct ProjectStoreTests {

    @Test("Project round-trips through JSON")
    func projectCodable() throws {
        let project = Project(
            id: UUID(),
            name: "Test Project",
            description: "A test",
            icon: "folder.fill",
            color: "#FF6600",
            folderPath: "/tmp/test",
            folderBookmark: nil,
            instructions: "Be helpful",
            isActive: true,
            isArchived: false,
            createdAt: Date(),
            updatedAt: Date()
        )
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(project)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode(Project.self, from: data)
        #expect(decoded.id == project.id)
        #expect(decoded.name == "Test Project")
        #expect(decoded.instructions == "Be helpful")
        #expect(decoded.isActive == true)
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --package-path Packages/OsaurusCore --filter ProjectStoreTests 2>&1 | head -20`
Expected: FAIL — `Project` type not found

- [ ] **Step 3: Create the Project model**

```swift
// Models/Project/Project.swift
import Foundation

/// A project groups conversations, work tasks, schedules, watchers, and memory
/// under a shared context with a linked folder and instructions.
public struct Project: Identifiable, Codable, Sendable, Equatable {
    public let id: UUID
    public var name: String
    public var description: String?
    public var icon: String
    public var color: String?

    // Folder
    public var folderPath: String?
    public var folderBookmark: Data?

    // Instructions
    public var instructions: String?

    // State
    public var isActive: Bool
    public var isArchived: Bool

    // Timestamps
    public let createdAt: Date
    public var updatedAt: Date

    public init(
        id: UUID = UUID(),
        name: String,
        description: String? = nil,
        icon: String = "folder.fill",
        color: String? = nil,
        folderPath: String? = nil,
        folderBookmark: Data? = nil,
        instructions: String? = nil,
        isActive: Bool = true,
        isArchived: Bool = false,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.name = name
        self.description = description
        self.icon = icon
        self.color = color
        self.folderPath = folderPath
        self.folderBookmark = folderBookmark
        self.instructions = instructions
        self.isActive = isActive
        self.isArchived = isArchived
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `swift test --package-path Packages/OsaurusCore --filter ProjectStoreTests 2>&1 | head -20`
Expected: PASS

- [ ] **Step 5: Add OsaurusPaths.projects() directory function**

In `Utils/OsaurusPaths.swift`, add after the `agents()` function (line ~72):

```swift
/// Projects directory
public static func projects() -> URL {
    root().appendingPathComponent("projects", isDirectory: true)
}
```

- [ ] **Step 6: Write failing test for ProjectStore save/load**

Add to `ProjectStoreTests.swift`:

```swift
@Test("ProjectStore saves and loads a project")
@MainActor
func saveAndLoad() throws {
    let project = Project(name: "CIMCO Test")
    ProjectStore.save(project)
    let loaded = ProjectStore.load(id: project.id)
    #expect(loaded != nil)
    #expect(loaded?.name == "CIMCO Test")
    // Cleanup
    ProjectStore.delete(id: project.id)
    #expect(ProjectStore.load(id: project.id) == nil)
}

@Test("ProjectStore loadAll returns saved projects")
@MainActor
func loadAll() throws {
    let p1 = Project(name: "Alpha")
    let p2 = Project(name: "Beta")
    ProjectStore.save(p1)
    ProjectStore.save(p2)
    let all = ProjectStore.loadAll()
    #expect(all.contains(where: { $0.id == p1.id }))
    #expect(all.contains(where: { $0.id == p2.id }))
    ProjectStore.delete(id: p1.id)
    ProjectStore.delete(id: p2.id)
}
```

- [ ] **Step 7: Create ProjectStore**

```swift
// Models/Project/ProjectStore.swift
import Foundation

/// JSON file persistence for Projects. One file per project at ~/.osaurus/projects/{uuid}.json.
/// Follows the AgentStore pattern (enum with static methods).
@MainActor
public enum ProjectStore {

    public static func loadAll() -> [Project] {
        let directory = projectsDirectory()
        OsaurusPaths.ensureExistsSilent(directory)

        guard let files = try? FileManager.default.contentsOfDirectory(
            at: directory, includingPropertiesForKeys: [.contentModificationDateKey]
        ) else { return [] }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        var projects: [Project] = []
        for file in files where file.pathExtension == "json" {
            do {
                let data = try Data(contentsOf: file)
                let project = try decoder.decode(Project.self, from: data)
                projects.append(project)
            } catch {
                print("[Osaurus] Failed to load project from \(file.lastPathComponent): \(error)")
            }
        }

        return projects.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    public static func load(id: UUID) -> Project? {
        let url = projectFileURL(for: id)
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        do {
            let data = try Data(contentsOf: url)
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            return try decoder.decode(Project.self, from: data)
        } catch {
            print("[Osaurus] Failed to load project \(id): \(error)")
            return nil
        }
    }

    public static func save(_ project: Project) {
        let url = projectFileURL(for: project.id)
        OsaurusPaths.ensureExistsSilent(url.deletingLastPathComponent())
        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            encoder.dateEncodingStrategy = .iso8601
            let data = try encoder.encode(project)
            try data.write(to: url, options: [.atomic])
        } catch {
            print("[Osaurus] Failed to save project \(project.id): \(error)")
        }
    }

    @discardableResult
    public static func delete(id: UUID) -> Bool {
        do {
            try FileManager.default.removeItem(at: projectFileURL(for: id))
            return true
        } catch {
            print("[Osaurus] Failed to delete project \(id): \(error)")
            return false
        }
    }

    public static func exists(id: UUID) -> Bool {
        FileManager.default.fileExists(atPath: projectFileURL(for: id).path)
    }

    // MARK: - Private

    private static func projectsDirectory() -> URL {
        OsaurusPaths.projects()
    }

    private static func projectFileURL(for id: UUID) -> URL {
        projectsDirectory().appendingPathComponent("\(id.uuidString).json")
    }
}
```

- [ ] **Step 8: Run all ProjectStore tests**

Run: `swift test --package-path Packages/OsaurusCore --filter ProjectStoreTests 2>&1 | head -30`
Expected: ALL PASS

- [ ] **Step 9: Commit**

```bash
git add Packages/OsaurusCore/Models/Project/ Packages/OsaurusCore/Tests/Project/ProjectStoreTests.swift Packages/OsaurusCore/Utils/OsaurusPaths.swift
git commit -m "feat: add Project model and ProjectStore persistence"
```

---

## Task 2: Add projectId to Existing Models

**Files:**

- Modify: `Packages/OsaurusCore/Models/Chat/ChatSessionData.swift:11-85`
- Modify: `Packages/OsaurusCore/Models/Schedule/Schedule.swift:310-481`
- Modify: `Packages/OsaurusCore/Models/Watcher/Watcher.swift:65-219`
- Modify: `Packages/OsaurusCore/Models/Work/WorkModels.swift:385+`

- [ ] **Step 1: Add `projectId` to ChatSessionData**

Open `Models/Chat/ChatSessionData.swift`. Add inside the struct properties:

```swift
/// Optional project association. nil = workspace-global.
public var projectId: UUID?
```

Ensure the `init` has a default of `nil` for this parameter. If using `CodingKeys`, add `projectId` to the enum. Since `Codable` with optional properties defaults to nil on decode, existing JSON files without this field will decode correctly.

- [ ] **Step 2: Add `projectId` to Schedule**

Open `Models/Schedule/Schedule.swift`. Add inside the struct:

```swift
/// Optional project association. nil = workspace-global.
public var projectId: UUID?
```

Add to init with `projectId: UUID? = nil` default. Add to CodingKeys if they exist.

- [ ] **Step 3: Add `projectId` to Watcher**

Open `Models/Watcher/Watcher.swift`. Add inside the struct:

```swift
/// Optional project association. nil = workspace-global.
public var projectId: UUID?
```

Add to init with `projectId: UUID? = nil` default. Add to CodingKeys if they exist.

- [ ] **Step 4: Add `projectId` to WorkTask**

Open `Models/Work/WorkModels.swift`. Find the `WorkTask` struct (~line 385). Add:

```swift
/// Optional project association. nil = workspace-global.
public var projectId: UUID?
```

Add to init with `projectId: UUID? = nil` default. Add to CodingKeys if they exist.

- [ ] **Step 5: Verify compile**

Run: `cd Packages/OsaurusCore && swift build 2>&1 | grep -E "error:" | grep -v "IkigaJSON"`
Expected: empty output (no errors)

- [ ] **Step 6: Run existing tests to confirm no regressions**

Run: `swift test --package-path Packages/OsaurusCore 2>&1 | tail -5`
Expected: all existing tests still pass

- [ ] **Step 7: Commit**

```bash
git add Packages/OsaurusCore/Models/Chat/ChatSessionData.swift Packages/OsaurusCore/Models/Schedule/Schedule.swift Packages/OsaurusCore/Models/Watcher/Watcher.swift Packages/OsaurusCore/Models/Work/WorkModels.swift
git commit -m "feat: add projectId field to ChatSessionData, Schedule, Watcher, WorkTask"
```

---

## Task 3: Database Migrations (WorkDatabase V5 + MemoryDatabase V4)

**Files:**

- Modify: `Packages/OsaurusCore/Storage/WorkDatabase.swift:38, 128-147`
- Modify: `Packages/OsaurusCore/Storage/MemoryDatabase.swift:34, 76+`
- Test: `Packages/OsaurusCore/Tests/Project/ProjectManagerTests.swift` (partial — migration verification)

- [ ] **Step 1: Add WorkDatabase V5 migration**

In `Storage/WorkDatabase.swift`:

1. Change `schemaVersion` constant at line 38 from `2` to `5`. Note: this constant is stale at `2` but the migration ladder already runs to V4 via `currentVersion < 4` branches. The runtime schema version comes from `PRAGMA user_version` in the SQLite file, not this constant.
2. In `runMigrations()`, insert a new block **after line 147** (after the closing `}` of the `if currentVersion < 4` block, before the method's closing `}`):

```swift
if currentVersion < 5 {
    try migrateToV5()
}
```

3. Add the migration method:

```swift
/// V5: Add project_agents table for project-agent associations
private func migrateToV5() throws {
    try executeRaw("""
        CREATE TABLE IF NOT EXISTS project_agents (
            project_id TEXT NOT NULL,
            agent_id TEXT NOT NULL,
            added_at TEXT NOT NULL DEFAULT (datetime('now')),
            PRIMARY KEY (project_id, agent_id)
        )
    """)
    try executeRaw("CREATE INDEX IF NOT EXISTS idx_project_agents_agent ON project_agents(agent_id)")
    try setSchemaVersion(5)
    debugLog("[WorkDB] Migrated to v5: project_agents table")
}
```

- [ ] **Step 2: Add MemoryDatabase V4 migration**

In `Storage/MemoryDatabase.swift`:

1. Change `schemaVersion` at line 34 from `3` to `4`
2. Find `runMigrations()` and add a `currentVersion < 4` block:

```swift
if currentVersion < 4 {
    try migrateToV4()
}
```

3. Add the migration method:

```swift
/// V4: Add project_id column to memory tables for project-scoped memory
private func migrateToV4() throws {
    let tables = ["memory_entries", "conversation_summaries", "conversations", "entities", "relationships"]
    for table in tables {
        try executeRaw("ALTER TABLE \(table) ADD COLUMN project_id TEXT")
    }
    try executeRaw("CREATE INDEX IF NOT EXISTS idx_memory_entries_agent_project ON memory_entries(agent_id, project_id)")
    try executeRaw("CREATE INDEX IF NOT EXISTS idx_summaries_agent_project ON conversation_summaries(agent_id, project_id)")
    try executeRaw("CREATE INDEX IF NOT EXISTS idx_conversations_agent_project ON conversations(agent_id, project_id)")
    try setSchemaVersion(4)
    debugLog("[MemoryDB] Migrated to v4: project_id columns")
}
```

Note: `ALTER TABLE ADD COLUMN` in SQLite is safe for existing rows — they get NULL (which is our `nil` default).

- [ ] **Step 3: Verify compile**

Run: `cd Packages/OsaurusCore && swift build 2>&1 | grep -E "error:" | grep -v "IkigaJSON"`
Expected: empty

- [ ] **Step 4: Run existing tests**

Run: `swift test --package-path Packages/OsaurusCore --filter MemoryTests 2>&1 | tail -5`
Run: `swift test --package-path Packages/OsaurusCore --filter WorkExecutionEngineTests 2>&1 | tail -5`
Expected: all pass (migrations are additive, no schema breaks)

- [ ] **Step 5: Commit**

```bash
git add Packages/OsaurusCore/Storage/WorkDatabase.swift Packages/OsaurusCore/Storage/MemoryDatabase.swift
git commit -m "feat: add WorkDatabase V5 and MemoryDatabase V4 migrations for project scoping"
```

---

## Task 4: ProjectManager

**Files:**

- Create: `Packages/OsaurusCore/Managers/ProjectManager.swift`
- Test: `Packages/OsaurusCore/Tests/Project/ProjectManagerTests.swift`

- [ ] **Step 1: Write failing test for ProjectManager CRUD**

```swift
// Tests/Project/ProjectManagerTests.swift
import Foundation
import Testing

@testable import OsaurusCore

@Suite("ProjectManager Tests")
struct ProjectManagerTests {

    @Test("Create and retrieve a project")
    @MainActor
    func createProject() async throws {
        let manager = ProjectManager.shared
        let project = manager.createProject(name: "Test CIMCO", icon: "snowflake")
        #expect(project.name == "Test CIMCO")
        #expect(project.icon == "snowflake")
        #expect(manager.projects.contains(where: { $0.id == project.id }))

        // Cleanup
        manager.deleteProject(id: project.id)
        #expect(!manager.projects.contains(where: { $0.id == project.id }))
    }

    @Test("Active projects filters correctly")
    @MainActor
    func activeProjects() async throws {
        let manager = ProjectManager.shared
        let p1 = manager.createProject(name: "Active")
        var p2 = manager.createProject(name: "Archived")
        p2.isArchived = true
        manager.updateProject(p2)

        let active = manager.activeProjects
        #expect(active.contains(where: { $0.id == p1.id }))
        #expect(!active.contains(where: { $0.id == p2.id }))

        manager.deleteProject(id: p1.id)
        manager.deleteProject(id: p2.id)
    }

    @Test("Project context builds from instructions")
    @MainActor
    func projectContext() async throws {
        let manager = ProjectManager.shared
        var project = Project(name: "Context Test", instructions: "Always use metric units")
        ProjectStore.save(project)
        manager.reload()

        let context = await manager.projectContext(for: project.id)
        #expect(context?.contains("Always use metric units") == true)

        manager.deleteProject(id: project.id)
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --package-path Packages/OsaurusCore --filter ProjectManagerTests 2>&1 | head -20`
Expected: FAIL — `ProjectManager` not found

- [ ] **Step 3: Create ProjectManager**

```swift
// Managers/ProjectManager.swift
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
        guard let url = try? URL(
            resolvingBookmarkData: bookmarkData,
            options: .withSecurityScope,
            relativeTo: nil,
            bookmarkDataIsStale: &isStale
        ) else { return }

        if isStale {
            print("[Osaurus] Bookmark stale for project \(project.name) — re-authorization needed")
            // TODO: Prompt user via NSOpenPanel to re-authorize
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
```

- [ ] **Step 4: Run tests**

Run: `swift test --package-path Packages/OsaurusCore --filter ProjectManagerTests 2>&1 | head -30`
Expected: ALL PASS

- [ ] **Step 5: Commit**

```bash
git add Packages/OsaurusCore/Managers/ProjectManager.swift Packages/OsaurusCore/Tests/Project/ProjectManagerTests.swift
git commit -m "feat: add ProjectManager with CRUD, context building, and bookmark lifecycle"
```

---

## Task 5: ChatMode Extension + ChatWindowState Navigation

**Files:**

- Modify: `Packages/OsaurusCore/Models/Chat/ChatMode.swift:11-30`
- Modify: `Packages/OsaurusCore/Managers/Chat/ChatWindowState.swift:23-67, 179-203`
- Test: `Packages/OsaurusCore/Tests/Project/ProjectNavigationTests.swift`

- [ ] **Step 1: Write failing test for navigation stack**

```swift
// Tests/Project/ProjectNavigationTests.swift
import Foundation
import Testing

@testable import OsaurusCore

@Suite("Project Navigation Tests")
struct ProjectNavigationTests {

    @Test("ChatMode has project case")
    func chatModeProject() {
        let mode = ChatMode.project
        #expect(mode.rawValue == "project")
        #expect(mode.displayName == "Projects")
        #expect(mode.icon == "folder.fill")
    }

    @Test("SidebarContentMode has all cases")
    func sidebarContentMode() {
        let modes: [SidebarContentMode] = [.chat, .projects, .scheduled]
        #expect(modes.count == 3)
    }

    @Test("ProjectSession is a value type")
    func projectSessionValueType() {
        var session = ProjectSession()
        session.activeProjectId = UUID()
        session.showInspector = false
        var copy = session
        copy.showInspector = true
        // Prove it's a value type — original unchanged
        #expect(session.showInspector == false)
        #expect(copy.showInspector == true)
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --package-path Packages/OsaurusCore --filter ProjectNavigationTests 2>&1 | head -20`
Expected: FAIL — `ChatMode.project` not found

- [ ] **Step 3: Extend ChatMode with `.project` case**

In `Models/Chat/ChatMode.swift`, replace the full enum (lines 11-30):

```swift
public enum ChatMode: String, Codable, Sendable {
    /// Standard chat mode - conversational interaction
    case chat
    /// Work mode - task execution with issue tracking
    case work = "agent"
    /// Project mode - project home with scoped context
    case project

    public var displayName: String {
        switch self {
        case .chat: return L("Chat")
        case .work: return L("Work")
        case .project: return L("Projects")
        }
    }

    public var icon: String {
        switch self {
        case .chat: return "bubble.left.and.bubble.right"
        case .work: return "bolt.circle"
        case .project: return "folder.fill"
        }
    }
}
```

- [ ] **Step 4: Add SidebarContentMode and ProjectSession to ChatWindowState**

In `Managers/Chat/ChatWindowState.swift`, add before the class definition (after line 19):

```swift
/// Controls what the main content area displays based on sidebar nav selection.
/// Orthogonal to ChatMode — ChatMode drives which engine is active,
/// SidebarContentMode drives content panel routing.
public enum SidebarContentMode: Sendable {
    case chat
    case projects
    case scheduled
}

/// Lightweight state for the active project context. Plain struct stored as
/// @Published on ChatWindowState (which is ObservableObject, not @Observable).
public struct ProjectSession: Equatable, Sendable {
    public var activeProjectId: UUID?
    public var showInspector: Bool = true

    public init(activeProjectId: UUID? = nil, showInspector: Bool = true) {
        self.activeProjectId = activeProjectId
        self.showInspector = showInspector
    }
}

/// Entry in the navigation stack for back/forward support.
public struct NavigationEntry: Equatable, Sendable {
    public let mode: ChatMode
    public let projectId: UUID?
    public let sessionId: UUID?

    public init(mode: ChatMode, projectId: UUID? = nil, sessionId: UUID? = nil) {
        self.mode = mode
        self.projectId = projectId
        self.sessionId = sessionId
    }
}
```

Inside the `ChatWindowState` class, add new `@Published` properties after the existing ones (after line ~61):

```swift
// MARK: - Project State

@Published var projectSession: ProjectSession?
@Published var sidebarContentMode: SidebarContentMode = .chat
@Published var showProjectInspector: Bool = true

// MARK: - Navigation Stack

@Published private(set) var navigationStack: [NavigationEntry] = []
@Published private(set) var navigationIndex: Int = -1

var canGoBack: Bool { navigationIndex > 0 }
var canGoForward: Bool { navigationIndex < navigationStack.count - 1 }

func pushNavigation(_ entry: NavigationEntry) {
    // Truncate forward history
    if navigationIndex < navigationStack.count - 1 {
        navigationStack = Array(navigationStack.prefix(navigationIndex + 1))
    }
    navigationStack.append(entry)
    navigationIndex = navigationStack.count - 1
}

func goBack() {
    guard canGoBack else { return }
    navigationIndex -= 1
    let entry = navigationStack[navigationIndex]
    restoreNavigationEntry(entry)
}

func goForward() {
    guard canGoForward else { return }
    navigationIndex += 1
    let entry = navigationStack[navigationIndex]
    restoreNavigationEntry(entry)
}

private func restoreNavigationEntry(_ entry: NavigationEntry) {
    switchMode(to: entry.mode)
    if let projectId = entry.projectId {
        projectSession = ProjectSession(activeProjectId: projectId)
        ProjectManager.shared.setActiveProject(projectId)
    }
}
```

- [ ] **Step 5: Extend switchMode(to:) for .project**

In `ChatWindowState.switchMode(to:)` (line 179-203), extend the method. Replace the existing implementation:

```swift
func switchMode(to newMode: ChatMode) {
    guard newMode != mode else { return }

    // Save current chat if switching away from chat mode
    if mode == .chat && !session.turns.isEmpty {
        session.save()
    }

    mode = newMode
    sidebarContentMode = .chat  // Reset sidebar content on mode change

    switch newMode {
    case .work:
        WorkToolManager.shared.registerTools()
        if workSession == nil {
            workSession = WorkSession(agentId: agentId, windowState: self)
        }
        refreshWorkTasks()
    case .project:
        WorkToolManager.shared.unregisterTools()
        if projectSession == nil {
            projectSession = ProjectSession()
        }
    case .chat:
        WorkToolManager.shared.unregisterTools()
    }
}
```

- [ ] **Step 6: Run tests**

Run: `swift test --package-path Packages/OsaurusCore --filter ProjectNavigationTests 2>&1 | head -20`
Expected: ALL PASS

- [ ] **Step 7: Verify full compile**

Run: `cd Packages/OsaurusCore && swift build 2>&1 | grep -E "error:" | grep -v "IkigaJSON"`
Expected: empty (may have warnings about exhaustive switch, which we'll fix in Task 6)

- [ ] **Step 8: Commit**

```bash
git add Packages/OsaurusCore/Models/Chat/ChatMode.swift Packages/OsaurusCore/Managers/Chat/ChatWindowState.swift Packages/OsaurusCore/Tests/Project/ProjectNavigationTests.swift
git commit -m "feat: add ChatMode.project, ProjectSession, navigation stack on ChatWindowState"
```

---

## Task 6: ModeToggleButton 3-Segment Refactor

**Files:**

- Modify: `Packages/OsaurusCore/Views/Common/SharedHeaderComponents.swift:45-94`
- Modify: `Packages/OsaurusCore/Managers/Chat/ChatWindowManager.swift:730-738`

**Note:** The spec mentions "3 call sites" but there is only **1 call site** (`ChatWindowManager.swift:730`). The spec was incorrect — Step 2 below covers the only update needed.

- [ ] **Step 1: Refactor ModeToggleButton to use ChatMode directly**

In `Views/Common/SharedHeaderComponents.swift`, replace lines 44-94 (the entire ModeToggleButton struct):

```swift
/// Segmented toggle for switching between Chat, Work, and Projects modes with sliding indicator.
struct ModeToggleButton: View {
    let currentMode: ChatMode
    var isDisabled: Bool = false
    let action: (ChatMode) -> Void

    @State private var isHovered = false
    @Environment(\.theme) private var theme
    @Namespace private var animation

    var body: some View {
        HStack(spacing: 0) {
            segment(mode: .chat, isSelected: currentMode == .chat)
            segment(mode: .work, isSelected: currentMode == .work)
            segment(mode: .project, isSelected: currentMode == .project)
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 2)
        .opacity(isDisabled ? 0.4 : 1.0)
        .disabled(isDisabled)
        .help(isDisabled ? "Set up a model to use Work mode" : "Switch mode")
    }

    @ViewBuilder
    private func segment(mode: ChatMode, isSelected: Bool) -> some View {
        HStack(spacing: 5) {
            Image(systemName: mode.icon).font(.system(size: 10, weight: .semibold))
            Text(mode.displayName).font(.system(size: 11, weight: .semibold))
        }
        .fixedSize()
        .foregroundColor(isSelected ? theme.primaryText : theme.tertiaryText)
        .padding(.horizontal, 14)
        .padding(.vertical, 5)
        .background {
            if isSelected {
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .fill(theme.secondaryBackground.opacity(0.8))
                    .shadow(color: theme.shadowColor.opacity(0.08), radius: 1.5, x: 0, y: 0.5)
                    .matchedGeometryEffect(id: "modeIndicator", in: animation)
            }
        }
        .contentShape(Rectangle())
        .animation(theme.springAnimation(), value: isSelected)
        .onTapGesture { action(mode) }
    }
}
```

Note: This changes the Work segment icon from `bolt.fill` to `bolt.circle` (via `ChatMode.icon`). This is an intentional alignment.

- [ ] **Step 2: Update the call site in ChatWindowManager**

In `Managers/Chat/ChatWindowManager.swift`, replace lines 730-738:

```swift
        ModeToggleButton(
            currentMode: windowState.mode,
            isDisabled: windowState.mode != .work && !session.hasAnyModel,
            action: { tappedMode in
                guard tappedMode != windowState.mode else { return }
                windowState.switchMode(to: tappedMode)
            }
        )
        .environment(\.theme, windowState.theme)
```

- [ ] **Step 3: Verify compile**

Run: `cd Packages/OsaurusCore && swift build 2>&1 | grep -E "error:" | grep -v "IkigaJSON"`
Expected: empty

- [ ] **Step 4: Commit**

```bash
git add Packages/OsaurusCore/Views/Common/SharedHeaderComponents.swift Packages/OsaurusCore/Managers/Chat/ChatWindowManager.swift
git commit -m "feat: refactor ModeToggleButton to 3-segment (Chat/Work/Projects)"
```

---

## Task 7: Toolbar Back/Forward Items

**Files:**

- Modify: `Packages/OsaurusCore/Managers/Chat/ChatWindowManager.swift:615-700`

- [ ] **Step 1: Add toolbar item identifiers**

Find the toolbar item identifier constants in `ChatWindowManager.swift` (look for `NSToolbarItem.Identifier` extensions or inline strings like `"ChatToolbar.sidebar"`). Add:

```swift
private static let backItemId = NSToolbarItem.Identifier("ChatToolbar.back")
private static let forwardItemId = NSToolbarItem.Identifier("ChatToolbar.forward")
```

- [ ] **Step 2: Register new items in toolbar delegate**

In the `ChatToolbarDelegate`'s `toolbarAllowedItemIdentifiers` and `toolbarDefaultItemIdentifiers` methods, add `backItemId` and `forwardItemId` after the sidebar toggle item.

- [ ] **Step 3: Create the toolbar item views**

In `toolbar(_:itemForItemIdentifier:)`, add cases for the back/forward items. Use `NSToolbarItem` with SwiftUI hosting:

```swift
case Self.backItemId:
    let item = NSToolbarItem(itemIdentifier: identifier)
    item.view = NSHostingView(rootView:
        Button(action: { [weak self] in self?.windowState?.goBack() }) {
            Image(systemName: "chevron.left")
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(windowState?.canGoBack == true ? theme.primaryText : theme.tertiaryText)
        }
        .buttonStyle(.plain)
        .disabled(windowState?.canGoBack != true)
        .help("Back")
        .environment(\.theme, windowState?.theme ?? DefaultTheme())
    )
    return item
```

Similar pattern for forward with `"chevron.right"` and `goForward()`.

- [ ] **Step 4: Verify compile**

Run: `cd Packages/OsaurusCore && swift build 2>&1 | grep -E "error:" | grep -v "IkigaJSON"`
Expected: empty

- [ ] **Step 5: Commit**

```bash
git add Packages/OsaurusCore/Managers/Chat/ChatWindowManager.swift
git commit -m "feat: add back/forward toolbar items for project navigation"
```

---

## Task 8: Memory Scoping (MemoryService + MemoryContextAssembler)

**Files:**

- Modify: `Packages/OsaurusCore/Services/Memory/MemoryService.swift:33-39`
- Modify: `Packages/OsaurusCore/Services/Memory/MemoryContextAssembler.swift:27-76`
- Test: `Packages/OsaurusCore/Tests/Memory/MemoryProjectScopingTests.swift`

- [ ] **Step 1: Write failing test**

```swift
// Tests/Memory/MemoryProjectScopingTests.swift
import Foundation
import Testing

@testable import OsaurusCore

@Suite("Memory Project Scoping Tests")
struct MemoryProjectScopingTests {

    @Test("MemoryContextAssembler cache key includes projectId")
    func cacheKeyComposite() async {
        // The assembleContext method should accept a projectId parameter.
        // This test verifies the API accepts it without crashing.
        let context = await MemoryContextAssembler.assembleContext(
            agentId: "test-agent",
            config: MemoryConfiguration(),
            projectId: "test-project"
        )
        // Empty context is fine — we just need the API to exist
        _ = context
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --package-path Packages/OsaurusCore --filter MemoryProjectScopingTests 2>&1 | head -20`
Expected: FAIL — extra argument `projectId` in call

- [ ] **Step 3: Add projectId to MemoryContextAssembler**

In `Services/Memory/MemoryContextAssembler.swift`:

1. Add a new overload of `assembleContext` (after line 28):

```swift
/// Assemble context scoped to a specific project.
public static func assembleContext(
    agentId: String,
    config: MemoryConfiguration,
    projectId: String?
) async -> String {
    await shared.assembleContextCached(agentId: agentId, config: config, projectId: projectId)
}

/// Assemble context with query-aware retrieval, scoped to a project.
public static func assembleContext(
    agentId: String,
    config: MemoryConfiguration,
    query: String,
    projectId: String?
) async -> String {
    await shared.assembleContextWithQuery(agentId: agentId, config: config, query: query, projectId: projectId)
}
```

2. Add a **new private overload** of `assembleContextCached` that accepts `projectId`. Do NOT rename or modify the existing parameterless version — it's called by the existing public API (line 28). The new overload sits alongside:

```swift
private func assembleContextCached(agentId: String, config: MemoryConfiguration, projectId: String? = nil) -> String {
    guard config.enabled else { return "" }

    let cacheKey = "\(agentId):\(projectId ?? "global")"
    if let cached = cache[cacheKey], Date().timeIntervalSince(cached.timestamp) < Self.cacheTTL {
        return cached.context
    }

    let context = buildContext(agentId: agentId, config: config, projectId: projectId)
    cache[cacheKey] = CacheEntry(context: context, timestamp: Date())
    return context
}
```

3. Update `invalidateCache` to handle composite keys:

```swift
public func invalidateCache(agentId: String? = nil) {
    if let agentId {
        // Remove all cache entries for this agent (any project)
        cache = cache.filter { !$0.key.hasPrefix("\(agentId):") }
    } else {
        cache.removeAll()
    }
}
```

4. Thread `projectId` through `buildContext` and `assembleContextWithQuery` — add the parameter with default `nil` and pass through to MemoryDatabase load calls. The DB already has the `project_id` column from Task 3.

Note: The existing overloads without `projectId` continue to work (they pass nil internally). No breaking changes.

- [ ] **Step 4: Add projectId to MemoryService.recordConversationTurn**

In `Services/Memory/MemoryService.swift`, add `projectId: String? = nil` parameter to `recordConversationTurn` (line 33):

```swift
public func recordConversationTurn(
    userMessage: String,
    assistantMessage: String?,
    agentId: String,
    conversationId: String,
    sessionDate: String? = nil,
    projectId: String? = nil
) async {
```

Thread `projectId` through to the `db.insertPendingSignal` call and any subsequent memory entry creation.

- [ ] **Step 5: Run test**

Run: `swift test --package-path Packages/OsaurusCore --filter MemoryProjectScopingTests 2>&1 | head -20`
Expected: PASS

- [ ] **Step 6: Run existing memory tests for regression**

Run: `swift test --package-path Packages/OsaurusCore --filter MemoryTests 2>&1 | tail -10`
Expected: all pass

- [ ] **Step 7: Commit**

```bash
git add Packages/OsaurusCore/Services/Memory/MemoryService.swift Packages/OsaurusCore/Services/Memory/MemoryContextAssembler.swift Packages/OsaurusCore/Tests/Memory/MemoryProjectScopingTests.swift
git commit -m "feat: add project scoping to MemoryService and MemoryContextAssembler"
```

---

## Task 9: System Prompt Integration

**Files:**

- Modify: `Packages/OsaurusCore/Services/Chat/SystemPromptComposer.swift:44-66, 91-136`

- [ ] **Step 1: Add project context injection to SystemPromptComposer**

In `Services/Chat/SystemPromptComposer.swift`, add a new method after `appendMemory` (after line 66):

```swift
/// Append project context (instructions + .md files from project folder).
public mutating func appendProjectContext(projectId: UUID?) async {
    guard let projectId else { return }
    guard let context = await ProjectManager.shared.projectContext(for: projectId) else { return }
    append(.dynamic(id: "project", label: "Project Context", content: """
    <project-context>
    \(context)
    </project-context>
    """))
}
```

- [ ] **Step 2: Wire into finalizeContext pipeline**

In the `finalizeContext` method (line ~91), add project context injection after the base prompt and before memory. Find line 99 (`await comp.appendMemory(...)`) and add before it:

```swift
// Inject active project context
let activeProjectId = ProjectManager.shared.activeProjectId
await comp.appendProjectContext(projectId: activeProjectId)
```

Also thread `projectId` through to `appendMemory` so memory retrieval is project-scoped:

```swift
await comp.appendMemory(agentId: agentId.uuidString, query: query, projectId: activeProjectId?.uuidString)
```

This requires adding the `projectId` parameter to `appendMemory`:

```swift
public mutating func appendMemory(agentId: String, query: String? = nil, projectId: String? = nil) async {
    let config = MemoryConfigurationStore.load()
    let context: String
    if let query, !query.isEmpty {
        context = await MemoryContextAssembler.assembleContext(
            agentId: agentId, config: config, query: query, projectId: projectId
        )
    } else {
        context = await MemoryContextAssembler.assembleContext(
            agentId: agentId, config: config, projectId: projectId
        )
    }
    append(.dynamic(id: "memory", label: "Memory", content: context))
}
```

- [ ] **Step 3: Verify compile**

Run: `cd Packages/OsaurusCore && swift build 2>&1 | grep -E "error:" | grep -v "IkigaJSON"`
Expected: empty

- [ ] **Step 4: Run existing tests**

Run: `swift test --package-path Packages/OsaurusCore --filter ChatEngineTests 2>&1 | tail -5`
Expected: all pass

- [ ] **Step 5: Commit**

```bash
git add Packages/OsaurusCore/Services/Chat/SystemPromptComposer.swift
git commit -m "feat: inject project context into system prompt pipeline"
```

---

## Task 10: CollapsibleSection + SidebarNavRow Components

**Files:**

- Create: `Packages/OsaurusCore/Views/Common/CollapsibleSection.swift`
- Create: `Packages/OsaurusCore/Views/Sidebar/SidebarNavRow.swift`

- [ ] **Step 1: Create CollapsibleSection**

```swift
// Views/Common/CollapsibleSection.swift
import SwiftUI

/// Reusable collapsible section with chevron toggle, following macOS System Settings pattern.
struct CollapsibleSection<Content: View, HeaderAccessory: View>: View {
    let title: String
    @Binding var isExpanded: Bool
    let headerAccessory: HeaderAccessory
    let content: Content

    @Environment(\.theme) private var theme

    init(
        _ title: String,
        isExpanded: Binding<Bool>,
        @ViewBuilder headerAccessory: () -> HeaderAccessory = { EmptyView() },
        @ViewBuilder content: () -> Content
    ) {
        self.title = title
        self._isExpanded = isExpanded
        self.headerAccessory = headerAccessory()
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button(action: { withAnimation(.easeInOut(duration: 0.2)) { isExpanded.toggle() } }) {
                HStack {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundColor(theme.tertiaryText)
                        .rotationEffect(.degrees(isExpanded ? 90 : 0))
                        .animation(.easeInOut(duration: 0.2), value: isExpanded)

                    Text(title)
                        .font(.headline)
                        .foregroundColor(theme.primaryText)

                    Spacer()

                    headerAccessory
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(title)
            .accessibilityHint(isExpanded ? "Collapse section" : "Expand section")
            .accessibilityAddTraits(.isButton)

            if isExpanded {
                content
                    .padding(.horizontal, 16)
                    .padding(.bottom, 12)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
    }
}
```

- [ ] **Step 2: Create SidebarNavRow**

```swift
// Views/Sidebar/SidebarNavRow.swift
import SwiftUI

/// A navigation item row for the unified sidebar (Projects, Scheduled, Customize).
struct SidebarNavRow: View {
    let icon: String
    let label: String
    var badge: Int? = nil
    let action: () -> Void

    @State private var isHovered = false
    @Environment(\.theme) private var theme

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(theme.secondaryText)
                    .frame(width: 20)

                Text(label)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(theme.primaryText)

                Spacer()

                if let badge, badge > 0 {
                    Text("\(badge)")
                        .font(.caption2)
                        .foregroundColor(theme.tertiaryText)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(
                            Capsule().fill(theme.secondaryBackground.opacity(0.5))
                        )
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(isHovered ? theme.secondaryBackground.opacity(0.4) : Color.clear)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .accessibilityLabel(label)
        .accessibilityHint("Navigate to \(label)")
    }
}
```

- [ ] **Step 3: Verify compile**

Run: `cd Packages/OsaurusCore && swift build 2>&1 | grep -E "error:" | grep -v "IkigaJSON"`
Expected: empty

- [ ] **Step 4: Commit**

```bash
git add Packages/OsaurusCore/Views/Common/CollapsibleSection.swift Packages/OsaurusCore/Views/Sidebar/SidebarNavRow.swift
git commit -m "feat: add CollapsibleSection and SidebarNavRow components"
```

---

## Task 11: Unified AppSidebar

**Files:**

- Create: `Packages/OsaurusCore/Views/Sidebar/AppSidebar.swift`
- Modify: `Packages/OsaurusCore/Views/Chat/ChatView.swift:~1292` (swap sidebar)

This is a large UI task. The AppSidebar replaces `ChatSessionSidebar` and `WorkTaskSidebar` with a unified component, but preserves both `SessionRow` and `TaskRow` inline.

- [ ] **Step 1: Create AppSidebar**

```swift
// Views/Sidebar/AppSidebar.swift
import SwiftUI

/// Unified sidebar for all three modes (Chat, Work, Projects).
/// Renders consistently across modes — nav items + active project chip + interleaved recents.
struct AppSidebar: View {
    @ObservedObject var windowState: ChatWindowState
    @ObservedObject var session: ChatSession

    @AppStorage("isRecentsExpanded") private var isRecentsExpanded = true
    @Environment(\.theme) private var theme

    var body: some View {
        VStack(spacing: 0) {
            // Existing New Chat button
            newChatButton
                .padding(.horizontal, 12)
                .padding(.top, 8)
                .padding(.bottom, 4)

            // Existing search field
            SidebarSearchField(text: $session.searchQuery, placeholder: "Search conversations...")
                .padding(.horizontal, 12)
                .padding(.bottom, 8)

            Divider().padding(.horizontal, 12)

            // Nav items
            VStack(spacing: 2) {
                SidebarNavRow(
                    icon: "folder.fill",
                    label: "Projects",
                    badge: ProjectManager.shared.activeProjects.count,
                    action: {
                        windowState.sidebarContentMode = .projects
                    }
                )
                SidebarNavRow(
                    icon: "calendar.badge.clock",
                    label: "Scheduled",
                    action: {
                        windowState.sidebarContentMode = .scheduled
                    }
                )
                SidebarNavRow(
                    icon: "slider.horizontal.3",
                    label: "Customize",
                    action: {
                        AppDelegate.shared?.showManagementWindow()
                    }
                )
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)

            Divider().padding(.horizontal, 12)

            // Active project chip
            if let project = ProjectManager.shared.activeProject {
                activeProjectChip(project)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)

                Divider().padding(.horizontal, 12)
            }

            // Recents (collapsible)
            CollapsibleSection("Recents", isExpanded: $isRecentsExpanded) {
                recentsList
            }

            Spacer()
        }
    }

    // MARK: - Subviews

    private var newChatButton: some View {
        Button(action: { windowState.startNewChat() }) {
            HStack {
                Image(systemName: "plus.bubble")
                    .font(.system(size: 13, weight: .medium))
                Text("New Chat")
                    .font(.system(size: 12, weight: .medium))
                Spacer()
            }
            .foregroundColor(theme.primaryText)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(theme.secondaryBackground.opacity(0.3))
            )
        }
        .buttonStyle(.plain)
    }

    private func activeProjectChip(_ project: Project) -> some View {
        HStack(spacing: 8) {
            Image(systemName: project.icon)
                .font(.system(size: 11))
                .foregroundColor(theme.secondaryText)
            Text(project.name)
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(theme.primaryText)
                .lineLimit(1)
            Spacer()
            Button(action: {
                ProjectManager.shared.setActiveProject(nil)
                windowState.projectSession = nil
            }) {
                Image(systemName: "xmark")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundColor(theme.tertiaryText)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(theme.secondaryBackground.opacity(0.4))
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .strokeBorder(theme.borderColor.opacity(0.3), lineWidth: 1)
                )
        )
    }

    private var recentsList: some View {
        // SCAFFOLD: The full implementation must interleave SessionRow and TaskRow by date.
        // Data sources:
        //   - Chat sessions: windowState.filteredSessions ([ChatSessionData])
        //     filtered by projectId when windowState.projectSession?.activeProjectId is set
        //   - Work tasks: windowState.workTasks ([WorkTask])
        //     filtered by projectId when set
        // Both should be sorted by updatedAt DESC, then rendered with their existing
        // row components (SessionRow from ChatSessionSidebar, TaskRow from WorkTaskSidebar).
        ScrollView {
            LazyVStack(spacing: 1) {
                ForEach(windowState.filteredSessions) { sessionData in
                    Text(sessionData.title)
                        .font(.system(size: 12))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                }
            }
        }
    }
}
```

Note: The `recentsList` is a scaffold. The full implementation requires extracting `SessionRow` and `TaskRow` from their respective sidebar files and rendering them interleaved. This is a UI refinement step that should be done with the app running to verify animations.

- [ ] **Step 2: Wire AppSidebar into ChatView**

In `Views/Chat/ChatView.swift`, find where `ChatSessionSidebar` is used (search for `ChatSessionSidebar`) and replace with `AppSidebar(windowState: windowState, session: observedSession)`. Keep the existing conditional for work mode's `WorkTaskSidebar` — the `AppSidebar` will eventually replace both, but v1 can coexist.

- [ ] **Step 3: Verify compile**

Run: `cd Packages/OsaurusCore && swift build 2>&1 | grep -E "error:" | grep -v "IkigaJSON"`
Expected: empty

- [ ] **Step 4: Commit**

```bash
git add Packages/OsaurusCore/Views/Sidebar/AppSidebar.swift Packages/OsaurusCore/Views/Chat/ChatView.swift
git commit -m "feat: add unified AppSidebar with nav items, project chip, and collapsible recents"
```

---

## Task 12: Project View — 3-Panel Layout

**Files:**

- Create: `Packages/OsaurusCore/Views/Projects/ProjectView.swift`
- Create: `Packages/OsaurusCore/Views/Projects/ProjectHomeView.swift`
- Create: `Packages/OsaurusCore/Views/Projects/ProjectInspectorPanel.swift`
- Create: `Packages/OsaurusCore/Views/Projects/FolderTreeView.swift`
- Create: `Packages/OsaurusCore/Views/Projects/MemorySummaryView.swift`

- [ ] **Step 1: Create ProjectView (3-panel coordinator)**

```swift
// Views/Projects/ProjectView.swift
import SwiftUI

/// Coordinator for the project 3-panel layout: sidebar (handled by parent) + center + right inspector.
struct ProjectView: View {
    @ObservedObject var windowState: ChatWindowState
    let session: ProjectSession

    @Environment(\.theme) private var theme

    var body: some View {
        ZStack(alignment: .trailing) {
            // Center content
            if let projectId = session.activeProjectId,
               let project = ProjectManager.shared.projects.first(where: { $0.id == projectId }) {
                ProjectHomeView(
                    project: project,
                    windowState: windowState
                )
            } else {
                // No project selected — should not happen, but graceful fallback
                ProjectListView(windowState: windowState)
            }

            // Right inspector overlay
            if windowState.showProjectInspector,
               let projectId = session.activeProjectId,
               let project = ProjectManager.shared.projects.first(where: { $0.id == projectId }) {
                ProjectInspectorPanel(project: project)
                    .frame(width: 300)
                    .transition(.move(edge: .trailing))
            }
        }
        .animation(.spring(response: 0.3, dampingFraction: 0.85), value: windowState.showProjectInspector)
    }
}
```

- [ ] **Step 2: Create ProjectHomeView (center panel)**

```swift
// Views/Projects/ProjectHomeView.swift
import SwiftUI

/// Center panel of the project view — header, input, outputs grid, and recents list.
struct ProjectHomeView: View {
    let project: Project
    @ObservedObject var windowState: ChatWindowState

    @Environment(\.theme) private var theme

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                // Header
                headerSection

                // Chat input — wired in Task 14.5 (FloatingInputCard integration)

                // Outputs
                outputsSection

                // Recents
                recentsSection
            }
            .padding(20)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.trailing, windowState.showProjectInspector ? 300 : 0)
    }

    private var headerSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(project.name)
                    .font(.title)
                    .foregroundColor(theme.primaryText)

                Spacer()

                Button(action: { windowState.showProjectInspector.toggle() }) {
                    Image(systemName: "sidebar.right")
                        .font(.system(size: 14))
                        .foregroundColor(theme.secondaryText)
                }
                .buttonStyle(.plain)
                .help("Toggle inspector")
            }

            Text("What would you like to work on in this project?")
                .font(.subheadline)
                .foregroundColor(theme.secondaryText)

            if let folderPath = project.folderPath {
                Button(action: {
                    NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: folderPath)
                }) {
                    HStack(spacing: 4) {
                        Image(systemName: "folder")
                            .font(.system(size: 11))
                        Text(folderPath)
                            .font(.system(size: 11))
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                    .foregroundColor(theme.tertiaryText)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .fill(theme.secondaryBackground.opacity(0.3))
                    )
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var outputsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Outputs")
                .font(.headline)
                .foregroundColor(theme.primaryText)

            // Horizontal scrolling card grid of SharedArtifacts
            // Query: artifacts from project-scoped sessions, ordered by created_at DESC, limit 8
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    // TODO: Query artifacts for this project
                    Text("No outputs yet")
                        .font(.subheadline)
                        .foregroundColor(theme.tertiaryText)
                        .padding(20)
                }
            }
        }
    }

    private var recentsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Recents")
                .font(.headline)
                .foregroundColor(theme.primaryText)

            // TODO: Interleaved SessionRow / TaskRow list for this project
            Text("No recent conversations")
                .font(.subheadline)
                .foregroundColor(theme.tertiaryText)
        }
    }
}
```

- [ ] **Step 3: Create ProjectInspectorPanel**

```swift
// Views/Projects/ProjectInspectorPanel.swift
import SwiftUI

/// Right inspector panel for project details — instructions, scheduled, context, memory.
/// Follows the overlay pattern from Work mode's IssueTrackerPanel.
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
                    Button(action: { /* TODO: create schedule */ }) {
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
                    Button(action: { /* TODO: open NSOpenPanel */ }) {
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
                .foregroundColor(theme.borderColor.opacity(0.2)),
            alignment: .leading
        )
        .onAppear {
            instructionsText = project.instructions ?? ""
        }
    }
}
```

- [ ] **Step 4: Create FolderTreeView**

```swift
// Views/Projects/FolderTreeView.swift
import SwiftUI

/// Recursive directory tree browser for the project context section.
struct FolderTreeView: View {
    let rootPath: String

    @State private var expandedDirs: Set<String> = []
    @Environment(\.theme) private var theme

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("On your computer")
                .font(.system(size: 10, weight: .semibold))
                .foregroundColor(theme.tertiaryText)
                .textCase(.uppercase)
                .padding(.bottom, 4)

            let items = listDirectory(at: rootPath)
            ForEach(items, id: \.path) { item in
                fileRow(item, depth: 0)
            }
        }
    }

    @ViewBuilder
    private func fileRow(_ item: FileItem, depth: Int) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            HStack(spacing: 4) {
                if item.isDirectory {
                    Image(systemName: expandedDirs.contains(item.path) ? "chevron.down" : "chevron.right")
                        .font(.system(size: 8))
                        .foregroundColor(theme.tertiaryText)
                        .frame(width: 12)
                        .onTapGesture {
                            if expandedDirs.contains(item.path) {
                                expandedDirs.remove(item.path)
                            } else {
                                expandedDirs.insert(item.path)
                            }
                        }
                } else {
                    Spacer().frame(width: 12)
                }

                Image(systemName: item.isDirectory ? "folder" : (item.isMd ? "doc.text" : "doc"))
                    .font(.system(size: 11))
                    .foregroundColor(item.isMd ? theme.accentColor : theme.tertiaryText)

                Text(item.name)
                    .font(.system(size: 11))
                    .foregroundColor(theme.primaryText)
                    .lineLimit(1)

                if item.isMd {
                    Text("context")
                        .font(.system(size: 9))
                        .foregroundColor(theme.accentColor.opacity(0.7))
                        .padding(.horizontal, 4)
                        .padding(.vertical, 1)
                        .background(
                            Capsule().fill(theme.accentColor.opacity(0.1))
                        )
                }
            }
            .padding(.leading, CGFloat(depth) * 16)
            .padding(.vertical, 2)

            if item.isDirectory && expandedDirs.contains(item.path) {
                let children = listDirectory(at: item.path)
                ForEach(children, id: \.path) { child in
                    fileRow(child, depth: depth + 1)
                }
            }
        }
    }

    private struct FileItem {
        let name: String
        let path: String
        let isDirectory: Bool
        var isMd: Bool { !isDirectory && name.hasSuffix(".md") }
    }

    private func listDirectory(at path: String) -> [FileItem] {
        let fm = FileManager.default
        let url = URL(fileURLWithPath: path)
        guard let contents = try? fm.contentsOfDirectory(
            at: url, includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles]
        ) else { return [] }

        return contents.compactMap { fileURL in
            let isDir = (try? fileURL.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory ?? false
            return FileItem(name: fileURL.lastPathComponent, path: fileURL.path, isDirectory: isDir)
        }.sorted { a, b in
            if a.isDirectory != b.isDirectory { return a.isDirectory }
            return a.name.localizedCaseInsensitiveCompare(b.name) == .orderedAscending
        }
    }
}
```

- [ ] **Step 5: Create MemorySummaryView**

```swift
// Views/Projects/MemorySummaryView.swift
import SwiftUI

/// Compact view of project-scoped memory entries for the inspector panel.
struct MemorySummaryView: View {
    let projectId: UUID

    @Environment(\.theme) private var theme

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            // TODO: Query MemoryDatabase for entries with project_id matching projectId
            // For now, show placeholder
            Text("Memory entries for this project will appear here")
                .font(.system(size: 11))
                .foregroundColor(theme.tertiaryText)
        }
    }
}
```

- [ ] **Step 6: Verify compile**

Run: `cd Packages/OsaurusCore && swift build 2>&1 | grep -E "error:" | grep -v "IkigaJSON"`
Expected: empty

- [ ] **Step 7: Commit**

```bash
git add Packages/OsaurusCore/Views/Projects/
git commit -m "feat: add ProjectView 3-panel layout with inspector, folder tree, and memory summary"
```

---

## Task 13: Project List + Editor Views

**Files:**

- Create: `Packages/OsaurusCore/Views/Projects/ProjectListView.swift`
- Create: `Packages/OsaurusCore/Views/Projects/ProjectEditorSheet.swift`

- [ ] **Step 1: Create ProjectListView**

```swift
// Views/Projects/ProjectListView.swift
import SwiftUI

/// Grid of projects with search and "New project" button.
/// Shown when sidebarContentMode == .projects.
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

            SidebarSearchField(text: $searchText, placeholder: "Search projects...")
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
                            .strokeBorder(theme.borderColor.opacity(0.2), lineWidth: 1)
                    )
            )
        }
        .buttonStyle(.plain)
    }
}
```

- [ ] **Step 2: Create ProjectEditorSheet**

```swift
// Views/Projects/ProjectEditorSheet.swift
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
```

- [ ] **Step 3: Verify compile**

Run: `cd Packages/OsaurusCore && swift build 2>&1 | grep -E "error:" | grep -v "IkigaJSON"`
Expected: empty

- [ ] **Step 4: Commit**

```bash
git add Packages/OsaurusCore/Views/Projects/ProjectListView.swift Packages/OsaurusCore/Views/Projects/ProjectEditorSheet.swift
git commit -m "feat: add ProjectListView and ProjectEditorSheet"
```

---

## Task 14: View Routing — Wire Everything Together

**Files:**

- Modify: `Packages/OsaurusCore/Views/Chat/ChatView.swift:~1292`

- [ ] **Step 1: Add project routing to ChatView body**

In `Views/Chat/ChatView.swift`, find the `body` view builder. Currently it branches:

```swift
if windowState.mode == .work, let workSession = windowState.workSession {
    WorkView(...)
} else {
    chatModeContent
}
```

Replace with:

```swift
if windowState.sidebarContentMode == .projects {
    ProjectListView(windowState: windowState)
} else if windowState.sidebarContentMode == .scheduled {
    // TODO: ScheduleListView filtered by active project
    Text("Scheduled tasks")
} else if windowState.mode == .project, let projectSession = windowState.projectSession {
    ProjectView(windowState: windowState, session: projectSession)
} else if windowState.mode == .work, let workSession = windowState.workSession {
    WorkView(windowState: windowState, session: workSession)
} else {
    chatModeContent
}
```

- [ ] **Step 2: Verify compile**

Run: `cd Packages/OsaurusCore && swift build 2>&1 | grep -E "error:" | grep -v "IkigaJSON"`
Expected: empty

- [ ] **Step 3: Run all tests**

Run: `swift test --package-path Packages/OsaurusCore 2>&1 | tail -10`
Expected: all pass

- [ ] **Step 4: Commit**

```bash
git add Packages/OsaurusCore/Views/Chat/ChatView.swift
git commit -m "feat: wire project view routing into ChatView body"
```

---

## Task 14.5: Wire FloatingInputCard into ProjectHomeView

**Files:**

- Modify: `Packages/OsaurusCore/Views/Projects/ProjectHomeView.swift`

The project home needs a working chat input that creates project-scoped sessions. This requires creating a lightweight `ChatSession` for the project input and passing all `FloatingInputCard` params including slash-command support from v0.16.9.

- [ ] **Step 1: Add session state to ProjectHomeView**

Add a `@StateObject` for a temporary `ChatSession` used only for the project input:

```swift
@StateObject private var inputSession: ChatSession

init(project: Project, windowState: ChatWindowState) {
    self.project = project
    self._windowState = ObservedObject(wrappedValue: windowState)
    self._inputSession = StateObject(wrappedValue: ChatSession())
}
```

- [ ] **Step 2: Add FloatingInputCard to the body**

Replace the `// Chat input — wired in Task 14.5` comment with:

```swift
// Chat input
FloatingInputCard(
    text: $inputSession.input,
    selectedModel: $inputSession.selectedModel,
    pendingAttachments: $inputSession.pendingAttachments,
    onSend: {
        let message = inputSession.input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !message.isEmpty else { return }
        // Create a new chat session scoped to this project
        windowState.startNewChat()
        windowState.session.input = message
        windowState.session.projectId = project.id
        windowState.switchMode(to: .chat)
        windowState.pushNavigation(NavigationEntry(mode: .chat, projectId: project.id))
        windowState.session.sendMessage()
        inputSession.input = ""
    },
    onClearChat: { inputSession.reset() },
    onSkillSelected: { skillId in
        inputSession.pendingOneOffSkillId = skillId
    },
    pendingSkillId: $inputSession.pendingOneOffSkillId
)
.frame(maxWidth: 800)
```

Note: The `FloatingInputCard` init has many parameters with defaults. Only pass the ones needed for project home. Check the current init signature in `FloatingInputCard.swift` and pass required non-defaulted params.

- [ ] **Step 3: Verify compile**

Run: `cd Packages/OsaurusCore && swift build 2>&1 | grep -E "error:" | grep -v "IkigaJSON"`
Expected: empty

- [ ] **Step 4: Commit**

```bash
git add Packages/OsaurusCore/Views/Projects/ProjectHomeView.swift
git commit -m "feat: wire FloatingInputCard into ProjectHomeView with slash command support"
```

---

## Task 15: Integration Smoke Test

This final task verifies the end-to-end flow compiles and all tests pass.

- [ ] **Step 1: Full compile check**

Run: `cd Packages/OsaurusCore && swift build 2>&1 | grep -E "error:" | grep -v "IkigaJSON"`
Expected: empty output

- [ ] **Step 2: Run all tests**

Run: `swift test --package-path Packages/OsaurusCore 2>&1 | tail -15`
Expected: all existing + new tests pass

- [ ] **Step 3: Verify no regressions in key areas**

Run each independently:

```bash
swift test --package-path Packages/OsaurusCore --filter ChatEngineTests
swift test --package-path Packages/OsaurusCore --filter MemoryTests
swift test --package-path Packages/OsaurusCore --filter WorkExecutionEngineTests
swift test --package-path Packages/OsaurusCore --filter ProjectStoreTests
swift test --package-path Packages/OsaurusCore --filter ProjectManagerTests
swift test --package-path Packages/OsaurusCore --filter ProjectNavigationTests
swift test --package-path Packages/OsaurusCore --filter MemoryProjectScopingTests
```

Expected: ALL PASS

- [ ] **Step 4: Final commit**

```bash
git add -A
git commit -m "feat: Projects as first-class concept — complete v1 implementation"
```

---

## Post-Implementation Notes

### What v1 Delivers

- Project model + JSON persistence
- ProjectManager with CRUD, context building, bookmark lifecycle
- ChatMode.project + ModeToggleButton 3-segment
- Navigation stack with back/forward toolbar buttons
- Memory scoping (MemoryDatabase V4, MemoryContextAssembler project-aware)
- WorkDatabase V5 migration (project_agents table)
- System prompt injection for project context
- Unified AppSidebar with nav items, project chip, collapsible recents
- 3-panel project view with inspector overlay
- Project list with search + create sheet
- Collapsible inspector with instructions, scheduled, context tree, memory

### Known Scaffolds (Refinement Needed)

- **AppSidebar recents list**: Currently placeholder — needs SessionRow/TaskRow extraction and interleaving (data sources: `filteredSessions` for chats, `workTasks` for tasks, both filtered by projectId)
- **ProjectHomeView outputs**: Needs artifact query wiring to IssueStore
- **MemorySummaryView**: Needs actual MemoryDatabase queries
- **Inspector Scheduled section**: Needs ScheduleManager integration

### Future Polish (Not in v1)

- NSSplitView migration for resizable panels
- Project export/import
- Project templates
- Drag-and-drop reordering
