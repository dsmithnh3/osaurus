//
//  SystemPromptProjectTests.swift
//  osaurus
//
//  Tests for project context injection in SystemPromptComposer.
//

import Foundation
import Testing

@testable import OsaurusCore

/// Tests must run serially because they mutate shared state (ProjectManager, OsaurusPaths).
@Suite("SystemPromptComposer – project context injection", .serialized)
struct SystemPromptProjectTests {

    @Test("appendProjectContext wraps instructions in project-context tags")
    @MainActor
    func appendProjectContextAddsTagsWhenInstructionsExist() async throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        OsaurusPaths.overrideRoot = tempDir
        defer {
            OsaurusPaths.overrideRoot = nil
            try? FileManager.default.removeItem(at: tempDir)
        }

        let project = Project(name: "Tag Test", instructions: "Always prefer Swift actors.")
        ProjectStore.save(project)
        ProjectManager.shared.reload()

        var composer = SystemPromptComposer()
        await composer.appendProjectContext(projectId: project.id)

        let rendered = composer.render()
        #expect(rendered.contains("<project-context>"))
        #expect(rendered.contains("</project-context>"))
        #expect(rendered.contains("Always prefer Swift actors."))

        ProjectManager.shared.deleteProject(id: project.id)
    }

    @Test("appendProjectContext adds nothing when projectId is nil")
    func appendProjectContextWithNilIdProducesEmptyRender() async {
        var composer = SystemPromptComposer()
        await composer.appendProjectContext(projectId: nil)

        let rendered = composer.render()
        #expect(rendered.isEmpty)
    }

    @Test("appendProjectContext adds nothing for an unknown project UUID")
    @MainActor
    func appendProjectContextWithUnknownIdProducesNoTags() async {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        OsaurusPaths.overrideRoot = tempDir
        defer {
            OsaurusPaths.overrideRoot = nil
            try? FileManager.default.removeItem(at: tempDir)
        }

        var composer = SystemPromptComposer()
        await composer.appendProjectContext(projectId: UUID())

        let rendered = composer.render()
        #expect(rendered.isEmpty)
    }

    @Test("appendProjectContext adds nothing when project has no instructions")
    @MainActor
    func appendProjectContextWithNoInstructionsProducesNoTags() async throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        OsaurusPaths.overrideRoot = tempDir
        defer {
            OsaurusPaths.overrideRoot = nil
            try? FileManager.default.removeItem(at: tempDir)
        }

        let project = Project(name: "No Instructions")
        ProjectStore.save(project)
        ProjectManager.shared.reload()

        var composer = SystemPromptComposer()
        await composer.appendProjectContext(projectId: project.id)

        let rendered = composer.render()
        #expect(!rendered.contains("<project-context>"))

        ProjectManager.shared.deleteProject(id: project.id)
    }
}
