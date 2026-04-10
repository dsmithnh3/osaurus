# Budget-Aware Project Context Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add token-budgeted, priority-tiered file selection and a security-scoped bookmark fix to `ProjectManager.projectContext(for:)`.

**Architecture:** All changes are confined to `ProjectManager.swift` (rewrite `projectContext(for:)` and `discoverMarkdownFiles(in:)`) and a new test file. The method signature and return type are unchanged — callers are unaffected. Files are discovered with exclusion patterns and a depth limit, sorted by a 6-tier priority system, and read in order until a 32,000-character budget is exhausted.

**Tech Stack:** Swift 6.2, Foundation (FileManager, URL), swift-testing framework

**Spec:** `docs/superpowers/specs/2026-04-10-budget-aware-project-context-design.md`

---

## File Structure

| File                                                                 | Responsibility                                 |
| -------------------------------------------------------------------- | ---------------------------------------------- |
| `Packages/OsaurusCore/Managers/ProjectManager.swift`                 | Project lifecycle, context building (modified) |
| `Packages/OsaurusCore/Tests/Project/ProjectContextBudgetTests.swift` | Budget, priority, exclusion, depth tests (new) |

---

### Task 1: Add Constants and Priority Tier Logic

Add the static constants and a helper method that assigns a priority tier to a discovered file URL relative to the project root.

**Files:**

- Modify: `Packages/OsaurusCore/Managers/ProjectManager.swift:14` (inside `ProjectManager` class)

- [ ] **Step 1: Write failing test — tier assignment**

Create the test file with a test that calls a `priorityTier(for:relativeTo:)` method (which doesn't exist yet).

Create: `Packages/OsaurusCore/Tests/Project/ProjectContextBudgetTests.swift`

```swift
//
//  ProjectContextBudgetTests.swift
//  osaurus
//
//  Tests for budget-aware project context file selection.
//

import Foundation
import Testing

@testable import OsaurusCore

@Suite("Project Context Budget Tests")
struct ProjectContextBudgetTests {

    // MARK: - Priority Tier Assignment

    @Test("CLAUDE.md gets tier 1 (case-insensitive)")
    func claudeMdTier1() {
        let root = URL(fileURLWithPath: "/tmp/testproject/")
        let file = URL(fileURLWithPath: "/tmp/testproject/claude.md")
        let tier = ProjectManager.priorityTier(for: file, relativeTo: root)
        #expect(tier == 1)
    }

    @Test("CLAUDE.md uppercase gets tier 1")
    func claudeMdUppercase() {
        let root = URL(fileURLWithPath: "/tmp/testproject/")
        let file = URL(fileURLWithPath: "/tmp/testproject/CLAUDE.md")
        let tier = ProjectManager.priorityTier(for: file, relativeTo: root)
        #expect(tier == 1)
    }

    @Test("TASKS.md gets tier 2")
    func tasksMdTier2() {
        let root = URL(fileURLWithPath: "/tmp/testproject/")
        let file = URL(fileURLWithPath: "/tmp/testproject/TASKS.md")
        let tier = ProjectManager.priorityTier(for: file, relativeTo: root)
        #expect(tier == 2)
    }

    @Test("active-projects.md gets tier 3")
    func activeProjectsTier3() {
        let root = URL(fileURLWithPath: "/tmp/testproject/")
        let file = URL(fileURLWithPath: "/tmp/testproject/active-projects.md")
        let tier = ProjectManager.priorityTier(for: file, relativeTo: root)
        #expect(tier == 3)
    }

    @Test("Root yaml gets tier 4")
    func rootYamlTier4() {
        let root = URL(fileURLWithPath: "/tmp/testproject/")
        let file = URL(fileURLWithPath: "/tmp/testproject/workspace.yaml")
        let tier = ProjectManager.priorityTier(for: file, relativeTo: root)
        #expect(tier == 4)
    }

    @Test("config/ yaml gets tier 4")
    func configYamlTier4() {
        let root = URL(fileURLWithPath: "/tmp/testproject/")
        let file = URL(fileURLWithPath: "/tmp/testproject/config/project.yaml")
        let tier = ProjectManager.priorityTier(for: file, relativeTo: root)
        #expect(tier == 4)
    }

    @Test("Deep yaml does NOT get tier 4")
    func deepYamlNotTier4() {
        let root = URL(fileURLWithPath: "/tmp/testproject/")
        let file = URL(fileURLWithPath: "/tmp/testproject/sub/config/data.yaml")
        let tier = ProjectManager.priorityTier(for: file, relativeTo: root)
        // Deep yaml files are not in any tier (they're not .md either)
        #expect(tier == nil)
    }

    @Test("Other root .md gets tier 5")
    func otherRootMdTier5() {
        let root = URL(fileURLWithPath: "/tmp/testproject/")
        let file = URL(fileURLWithPath: "/tmp/testproject/CONTRIBUTING.md")
        let tier = ProjectManager.priorityTier(for: file, relativeTo: root)
        #expect(tier == 5)
    }

    @Test("Deeper .md at depth 2 gets tier 6")
    func deeperMdTier6() {
        let root = URL(fileURLWithPath: "/tmp/testproject/")
        let file = URL(fileURLWithPath: "/tmp/testproject/docs/guide/intro.md")
        let tier = ProjectManager.priorityTier(for: file, relativeTo: root)
        #expect(tier == 6)
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --package-path Packages/OsaurusCore --filter ProjectContextBudgetTests 2>&1 | tail -20`
Expected: FAIL — `priorityTier` does not exist

- [ ] **Step 3: Implement constants and priorityTier method**

Add these inside the `ProjectManager` class in `Packages/OsaurusCore/Managers/ProjectManager.swift`, after the `// MARK: - Context` comment (line 86):

```swift
    // MARK: - Project Context Constants

    // internal (not private) so tests can reference these values directly
    static let projectContextBudgetChars = 32_000  // ~8,000 tokens
    static let truncatedPreviewChars = 500
    static let maxDiscoveryDepth = 3

    static let excludePatterns = [
        "memory/", ".build/", "DerivedData/", "node_modules/",
        "docs/superpowers/", "benchmarks/", "results/",
    ]

    private static let tier1Names: Set<String> = ["claude.md", "agents.md", "gemini.md"]
    private static let tier2Names: Set<String> = ["tasks.md", "readme.md"]
    private static let tier3Names: Set<String> = ["active-projects.md"]

    /// Assign a priority tier (1-6) to a file URL relative to the project root.
    /// Returns nil if the file should not be included (unsupported extension at depth, etc.).
    static func priorityTier(for fileURL: URL, relativeTo root: URL) -> Int? {
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
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `swift test --package-path Packages/OsaurusCore --filter ProjectContextBudgetTests 2>&1 | tail -20`
Expected: All 9 tests PASS

- [ ] **Step 5: Compile check**

Run: `cd Packages/OsaurusCore && swift build 2>&1 | grep -E "error:" | grep -v "IkigaJSON"`
Expected: No errors

- [ ] **Step 6: Commit**

```bash
git add Packages/OsaurusCore/Managers/ProjectManager.swift Packages/OsaurusCore/Tests/Project/ProjectContextBudgetTests.swift
git commit -m "feat: add priority tier constants and assignment logic for project context"
```

---

### Task 2: Rewrite File Discovery with Exclusions and Depth Limit

Replace `discoverMarkdownFiles(in:)` with `discoverProjectFiles(in:)` that respects exclusion patterns, depth limits, and discovers both `.md` and `.yaml` files.

**Files:**

- Modify: `Packages/OsaurusCore/Managers/ProjectManager.swift:115-130` (replace `discoverMarkdownFiles`)
- Test: `Packages/OsaurusCore/Tests/Project/ProjectContextBudgetTests.swift`

- [ ] **Step 1: Write failing tests — discovery with exclusions and depth**

Add to `ProjectContextBudgetTests.swift`:

```swift
    // MARK: - File Discovery

    @Test("Discovery excludes memory/ directory")
    func discoveryExcludesMemory() throws {
        let tmp = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tmp) }

        // Create files
        try "root doc".write(to: tmp.appendingPathComponent("README.md"), atomically: true, encoding: .utf8)
        let memoryDir = tmp.appendingPathComponent("memory")
        try FileManager.default.createDirectory(at: memoryDir, withIntermediateDirectories: true)
        try "memory file".write(to: memoryDir.appendingPathComponent("notes.md"), atomically: true, encoding: .utf8)

        let files = ProjectManager.discoverProjectFiles(in: tmp)
        let names = files.map { $0.lastPathComponent }
        #expect(names.contains("README.md"))
        #expect(!names.contains("notes.md"))
    }

    @Test("Discovery respects depth limit")
    func discoveryRespectsDepthLimit() throws {
        let tmp = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tmp) }

        // depth 0
        try "root".write(to: tmp.appendingPathComponent("root.md"), atomically: true, encoding: .utf8)
        // depth 3 (at limit)
        let d3 = tmp.appendingPathComponent("a/b/c")
        try FileManager.default.createDirectory(at: d3, withIntermediateDirectories: true)
        try "depth3".write(to: d3.appendingPathComponent("deep.md"), atomically: true, encoding: .utf8)
        // depth 4 (beyond limit)
        let d4 = tmp.appendingPathComponent("a/b/c/d")
        try FileManager.default.createDirectory(at: d4, withIntermediateDirectories: true)
        try "depth4".write(to: d4.appendingPathComponent("tooDeep.md"), atomically: true, encoding: .utf8)

        let files = ProjectManager.discoverProjectFiles(in: tmp)
        let names = files.map { $0.lastPathComponent }
        #expect(names.contains("root.md"))
        #expect(names.contains("deep.md"))
        #expect(!names.contains("tooDeep.md"))
    }

    @Test("Discovery includes yaml in root and config/")
    func discoveryIncludesYaml() throws {
        let tmp = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tmp) }

        try "root yaml".write(to: tmp.appendingPathComponent("workspace.yaml"), atomically: true, encoding: .utf8)
        let configDir = tmp.appendingPathComponent("config")
        try FileManager.default.createDirectory(at: configDir, withIntermediateDirectories: true)
        try "config yaml".write(to: configDir.appendingPathComponent("project.yaml"), atomically: true, encoding: .utf8)

        let files = ProjectManager.discoverProjectFiles(in: tmp)
        let names = files.map { $0.lastPathComponent }
        #expect(names.contains("workspace.yaml"))
        #expect(names.contains("project.yaml"))
    }

    @Test("Empty folder returns empty array")
    func emptyFolderReturnsEmpty() throws {
        let tmp = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tmp) }

        let files = ProjectManager.discoverProjectFiles(in: tmp)
        #expect(files.isEmpty)
    }
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `swift test --package-path Packages/OsaurusCore --filter ProjectContextBudgetTests 2>&1 | tail -20`
Expected: FAIL — `discoverProjectFiles` does not exist

- [ ] **Step 3: Implement discoverProjectFiles**

Replace the `discoverMarkdownFiles(in:)` method (lines 115-130) with:

```swift
    /// Discover project files (.md and .yaml) with exclusion patterns and depth limit.
    /// Returns file URLs that pass exclusion and depth filters.
    public static func discoverProjectFiles(in directory: URL) -> [URL] {
        let fm = FileManager.default
        let root = directory.standardizedFileURL
        let rootComponents = root.pathComponents

        guard let enumerator = fm.enumerator(
            at: root,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else { return [] }

        var results: [URL] = []
        for case let fileURL as URL in enumerator {
            let stdURL = fileURL.standardizedFileURL
            let fileComponents = stdURL.pathComponents
            let relativeComponents = Array(fileComponents.dropFirst(rootComponents.count))

            // Check exclusion patterns against relative path
            let relativePath = relativeComponents.joined(separator: "/")
            let excluded = Self.excludePatterns.contains { pattern in
                let dir = pattern.hasSuffix("/") ? String(pattern.dropLast()) : pattern
                return relativeComponents.first(where: { $0.caseInsensitiveCompare(dir) == .orderedSame }) != nil
                    && relativePath.lowercased().hasPrefix(dir.lowercased())
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
```

Also keep the old `discoverMarkdownFiles(in:)` method as a deprecated wrapper so any other callers don't break:

```swift
    /// Discover all .md files recursively in a directory.
    @available(*, deprecated, renamed: "discoverProjectFiles(in:)")
    public func discoverMarkdownFiles(in directory: URL) -> [URL] {
        Self.discoverProjectFiles(in: directory).filter { $0.pathExtension.lowercased() == "md" }
    }
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `swift test --package-path Packages/OsaurusCore --filter ProjectContextBudgetTests 2>&1 | tail -20`
Expected: All 13 tests PASS

- [ ] **Step 5: Compile check**

Run: `cd Packages/OsaurusCore && swift build 2>&1 | grep -E "error:" | grep -v "IkigaJSON"`
Expected: No errors (the old `discoverMarkdownFiles` wrapper keeps `projectContext(for:)` compiling)

- [ ] **Step 6: Commit**

```bash
git add Packages/OsaurusCore/Managers/ProjectManager.swift Packages/OsaurusCore/Tests/Project/ProjectContextBudgetTests.swift
git commit -m "feat: add file discovery with exclusion patterns and depth limit"
```

---

### Task 3: Rewrite projectContext(for:) with Budget Logic and Bookmark Fix

Replace the body of `projectContext(for:)` with the budget-aware algorithm: discover files, sort by tier, read within budget, truncate overflow, use security-scoped bookmark URL.

**Files:**

- Modify: `Packages/OsaurusCore/Managers/ProjectManager.swift:90-112` (rewrite `projectContext(for:)`)
- Test: `Packages/OsaurusCore/Tests/Project/ProjectContextBudgetTests.swift`

- [ ] **Step 1: Write failing tests — budget behavior**

Add to `ProjectContextBudgetTests.swift`:

```swift
    // MARK: - Budget and Context Building

    @Test("Priority ordering — tier 1 appears before tier 6")
    @MainActor
    func priorityOrdering() async throws {
        let tmp = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tmp) }

        // Tier 6 file
        let subDir = tmp.appendingPathComponent("docs")
        try FileManager.default.createDirectory(at: subDir, withIntermediateDirectories: true)
        try "deep content".write(to: subDir.appendingPathComponent("guide.md"), atomically: true, encoding: .utf8)

        // Tier 1 file
        try "agent instructions".write(to: tmp.appendingPathComponent("CLAUDE.md"), atomically: true, encoding: .utf8)

        let manager = ProjectManager.shared
        let project = manager.createProject(
            name: "Priority Test \(UUID().uuidString.prefix(8))",
            folderPath: tmp.path
        )
        defer { manager.deleteProject(id: project.id) }

        let context = await manager.projectContext(for: project.id)
        guard let context else {
            Issue.record("Expected non-nil context")
            return
        }

        // CLAUDE.md (tier 1) should appear before guide.md (tier 6)
        let claudeRange = context.range(of: "agent instructions")
        let guideRange = context.range(of: "deep content")
        #expect(claudeRange != nil)
        #expect(guideRange != nil)
        if let c = claudeRange?.lowerBound, let g = guideRange?.lowerBound {
            #expect(c < g)
        }
    }

    @Test("Budget truncation uses correct format")
    @MainActor
    func budgetTruncation() async throws {
        let tmp = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tmp) }

        // Create a file larger than the budget
        let bigContent = String(repeating: "x", count: ProjectManager.projectContextBudgetChars + 1000)
        try bigContent.write(to: tmp.appendingPathComponent("CLAUDE.md"), atomically: true, encoding: .utf8)

        let manager = ProjectManager.shared
        let project = manager.createProject(
            name: "Truncation Test \(UUID().uuidString.prefix(8))",
            folderPath: tmp.path
        )
        defer { manager.deleteProject(id: project.id) }

        let context = await manager.projectContext(for: project.id)
        guard let context else {
            Issue.record("Expected non-nil context")
            return
        }

        #expect(context.contains("[truncated -- full file at CLAUDE.md]"))
        #expect(context.count <= ProjectManager.projectContextBudgetChars + 200)  // allow section header overhead
    }

    @Test("Budget exhaustion — total stays under limit")
    @MainActor
    func budgetExhaustion() async throws {
        let tmp = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tmp) }

        // Create many files that together exceed budget
        for i in 0..<50 {
            let content = String(repeating: "content-\(i) ", count: 200)
            try content.write(to: tmp.appendingPathComponent("file\(i).md"), atomically: true, encoding: .utf8)
        }

        let manager = ProjectManager.shared
        let project = manager.createProject(
            name: "Exhaustion Test \(UUID().uuidString.prefix(8))",
            folderPath: tmp.path
        )
        defer { manager.deleteProject(id: project.id) }

        let context = await manager.projectContext(for: project.id)
        guard let context else {
            Issue.record("Expected non-nil context")
            return
        }

        // Total output must respect budget (with some overhead for section headers/separators)
        #expect(context.count <= ProjectManager.projectContextBudgetChars + 5000)
    }

    @Test("Single CLAUDE.md reads in full without truncation")
    @MainActor
    func singleClaudeMdFullRead() async throws {
        let tmp = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tmp) }

        let content = "These are my project instructions.\nLine two."
        try content.write(to: tmp.appendingPathComponent("CLAUDE.md"), atomically: true, encoding: .utf8)

        let manager = ProjectManager.shared
        let project = manager.createProject(
            name: "Single File \(UUID().uuidString.prefix(8))",
            folderPath: tmp.path
        )
        defer { manager.deleteProject(id: project.id) }

        let context = await manager.projectContext(for: project.id)
        #expect(context?.contains("These are my project instructions.") == true)
        #expect(context?.contains("[truncated") != true)
    }

    @Test("Instructions still included alongside file context")
    @MainActor
    func instructionsPlusFiles() async throws {
        let tmp = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tmp) }

        try "file content".write(to: tmp.appendingPathComponent("README.md"), atomically: true, encoding: .utf8)

        let manager = ProjectManager.shared
        let project = manager.createProject(
            name: "Both Test \(UUID().uuidString.prefix(8))",
            folderPath: tmp.path,
            instructions: "Custom project instructions"
        )
        defer { manager.deleteProject(id: project.id) }

        let context = await manager.projectContext(for: project.id)
        #expect(context?.contains("Custom project instructions") == true)
        #expect(context?.contains("file content") == true)
    }
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `swift test --package-path Packages/OsaurusCore --filter ProjectContextBudgetTests 2>&1 | tail -20`
Expected: Some tests may pass (single file), but budget truncation/exhaustion tests will show incorrect behavior (no truncation happening)

- [ ] **Step 3: Rewrite projectContext(for:)**

Replace the `projectContext(for:)` method (lines 90-112) with:

```swift
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
        let rootPath = folderURL.path
        for file in ranked {
            guard budgetRemaining > Self.truncatedPreviewChars else { break }

            guard let content = try? String(contentsOf: file.url, encoding: .utf8) else { continue }
            let relativePath = file.url.path.replacingOccurrences(of: rootPath, with: "")
                .trimmingCharacters(in: CharacterSet(charactersIn: "/"))

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
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `swift test --package-path Packages/OsaurusCore --filter ProjectContextBudgetTests 2>&1 | tail -20`
Expected: All 18 tests PASS

- [ ] **Step 5: Run existing ProjectManager tests to ensure no regressions**

Run: `swift test --package-path Packages/OsaurusCore --filter ProjectManagerTests 2>&1 | tail -20`
Expected: All 3 existing tests PASS (the `projectContext` test still works because instructions are still included)

- [ ] **Step 6: Compile check**

Run: `cd Packages/OsaurusCore && swift build 2>&1 | grep -E "error:" | grep -v "IkigaJSON"`
Expected: No errors

- [ ] **Step 7: Commit**

```bash
git add Packages/OsaurusCore/Managers/ProjectManager.swift Packages/OsaurusCore/Tests/Project/ProjectContextBudgetTests.swift
git commit -m "feat: rewrite projectContext with budget, priority tiers, and bookmark fix"
```

---

### Task 4: Final Verification and Cleanup

Run the full test suite, verify no regressions, and clean up any leftover deprecated code if safe.

**Files:**

- Review: `Packages/OsaurusCore/Managers/ProjectManager.swift`
- Review: `Packages/OsaurusCore/Tests/Project/ProjectContextBudgetTests.swift`

- [ ] **Step 1: Run full OsaurusCore test suite**

Run: `swift test --package-path Packages/OsaurusCore 2>&1 | tail -30`
Expected: All tests pass (including existing memory, project, and new budget tests)

- [ ] **Step 2: Compile check on full workspace**

Run: `cd Packages/OsaurusCore && swift build 2>&1 | grep -E "error:" | grep -v "IkigaJSON"`
Expected: No errors

- [ ] **Step 3: Verify discoverMarkdownFiles callers**

Search for any other callers of `discoverMarkdownFiles` in the codebase:

Run: `grep -r "discoverMarkdownFiles" Packages/OsaurusCore/Sources/ --include="*.swift"`

If any callers exist beyond `projectContext(for:)`, ensure the deprecated wrapper still serves them. If `projectContext(for:)` was the only caller, remove the deprecated wrapper entirely.

- [ ] **Step 4: Commit cleanup (if any)**

```bash
git add -A
git commit -m "chore: remove deprecated discoverMarkdownFiles wrapper (no remaining callers)"
```

Only commit if there were actual changes. Skip if the deprecated wrapper is still needed.

---

## Verification Checklist

```bash
# All budget tests pass
swift test --package-path Packages/OsaurusCore --filter ProjectContextBudgetTests

# Existing project tests still pass
swift test --package-path Packages/OsaurusCore --filter ProjectManagerTests

# Full suite passes
swift test --package-path Packages/OsaurusCore

# No compile errors
cd Packages/OsaurusCore && swift build 2>&1 | grep -E "error:" | grep -v "IkigaJSON"
```
