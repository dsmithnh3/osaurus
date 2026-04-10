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
}
