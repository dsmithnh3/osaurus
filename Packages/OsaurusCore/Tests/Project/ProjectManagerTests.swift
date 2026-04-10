//
//  ProjectManagerTests.swift
//  osaurus
//
//  Tests for ProjectManager CRUD and context building.
//

import Foundation
import Testing

@testable import OsaurusCore

/// Tests operate on the real ProjectManager.shared singleton.
/// Each test creates and cleans up its own projects.
@Suite("ProjectManager Tests", .serialized)
struct ProjectManagerTests {

    @Test("Create and retrieve a project")
    @MainActor
    func createProject() async throws {
        let manager = ProjectManager.shared
        let project = manager.createProject(name: "Test CIMCO \(UUID().uuidString.prefix(8))", icon: "snowflake")
        defer { manager.deleteProject(id: project.id) }

        #expect(project.icon == "snowflake")
        #expect(manager.projects.contains(where: { $0.id == project.id }))

        manager.deleteProject(id: project.id)
        #expect(!manager.projects.contains(where: { $0.id == project.id }))
    }

    @Test("Active projects filters correctly")
    @MainActor
    func activeProjects() async throws {
        let manager = ProjectManager.shared
        let p1 = manager.createProject(name: "Active \(UUID().uuidString.prefix(8))")
        defer { manager.deleteProject(id: p1.id) }
        var p2 = manager.createProject(name: "Archived \(UUID().uuidString.prefix(8))")
        defer { manager.deleteProject(id: p2.id) }
        p2.isArchived = true
        manager.updateProject(p2)

        let active = manager.activeProjects
        #expect(active.contains(where: { $0.id == p1.id }))
        #expect(!active.contains(where: { $0.id == p2.id }))
    }

    @Test("Project context builds from instructions")
    @MainActor
    func projectContext() async throws {
        let manager = ProjectManager.shared
        let project = manager.createProject(name: "Context \(UUID().uuidString.prefix(8))", instructions: "Always use metric units")
        defer { manager.deleteProject(id: project.id) }

        let context = await manager.projectContext(for: project.id)
        #expect(context?.contains("Always use metric units") == true)
    }
}
