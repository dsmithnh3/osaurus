//
//  ProjectManagerTests.swift
//  osaurus
//
//  Tests for ProjectManager CRUD and context building.
//

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
        let project = Project(name: "Context Test", instructions: "Always use metric units")
        ProjectStore.save(project)
        manager.reload()

        let context = await manager.projectContext(for: project.id)
        #expect(context?.contains("Always use metric units") == true)

        manager.deleteProject(id: project.id)
    }
}
