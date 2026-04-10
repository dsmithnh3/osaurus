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
}
