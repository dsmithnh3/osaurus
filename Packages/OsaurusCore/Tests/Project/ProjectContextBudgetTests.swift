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

    @Test("Depth 3 .md gets tier 6 (at boundary)")
    func depth3MdTier6() {
        let root = URL(fileURLWithPath: "/tmp/testproject/")
        let file = URL(fileURLWithPath: "/tmp/testproject/a/b/c/deep.md")
        let tier = ProjectManager.priorityTier(for: file, relativeTo: root)
        #expect(tier == 6)
    }

    @Test("Depth 4 .md returns nil (beyond limit)")
    func depth4MdNil() {
        let root = URL(fileURLWithPath: "/tmp/testproject/")
        let file = URL(fileURLWithPath: "/tmp/testproject/a/b/c/d/tooDeep.md")
        let tier = ProjectManager.priorityTier(for: file, relativeTo: root)
        #expect(tier == nil)
    }

    @Test(".yml extension gets tier 4 at root")
    func ymlExtensionTier4() {
        let root = URL(fileURLWithPath: "/tmp/testproject/")
        let file = URL(fileURLWithPath: "/tmp/testproject/config.yml")
        let tier = ProjectManager.priorityTier(for: file, relativeTo: root)
        #expect(tier == 4)
    }

    @Test("Known tier-1 name at depth > 0 gets tier 6, not tier 1")
    func knownNameAtDepthGetsTier6() {
        let root = URL(fileURLWithPath: "/tmp/testproject/")
        let file = URL(fileURLWithPath: "/tmp/testproject/docs/CLAUDE.md")
        let tier = ProjectManager.priorityTier(for: file, relativeTo: root)
        #expect(tier == 6)
    }

    @Test("Non-md non-yaml file returns nil")
    func nonMdNonYamlReturnsNil() {
        let root = URL(fileURLWithPath: "/tmp/testproject/")
        let file = URL(fileURLWithPath: "/tmp/testproject/data.json")
        let tier = ProjectManager.priorityTier(for: file, relativeTo: root)
        #expect(tier == nil)
    }

    // MARK: - File Discovery

    @Test("Discovery excludes memory/ directory")
    func discoveryExcludesMemory() throws {
        let tmp = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tmp) }

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

        try "root".write(to: tmp.appendingPathComponent("root.md"), atomically: true, encoding: .utf8)
        let d3 = tmp.appendingPathComponent("a/b/c")
        try FileManager.default.createDirectory(at: d3, withIntermediateDirectories: true)
        try "depth3".write(to: d3.appendingPathComponent("deep.md"), atomically: true, encoding: .utf8)
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
}
