//
//  ProjectManagementViewTests.swift
//  osaurus
//
//  Tests for project management view helper logic.
//

import Foundation
import Testing

@testable import OsaurusCore

@Suite("Project Management View Tests")
struct ProjectManagementViewTests {

    @Test("Project list filter returns active projects only")
    func activeFilterReturnsActiveProjects() {
        let active = Project(name: "Website Redesign")
        let archived = Project(name: "Archive", isActive: false, isArchived: true)

        let filtered = ProjectListFilter.active.projects(from: [active, archived], searchText: "")

        #expect(filtered == [active])
    }

    @Test("Project list filter returns archived projects only")
    func archivedFilterReturnsArchivedProjects() {
        let active = Project(name: "Active")
        let archived = Project(name: "Roadmap", isActive: false, isArchived: true)

        let filtered = ProjectListFilter.archived.projects(from: [active, archived], searchText: "")

        #expect(filtered == [archived])
    }

    @Test("Project list filter searches names and descriptions")
    func projectListFilterSearchesMetadata() {
        let product = Project(name: "Product Launch", description: "Quarterly release planning")
        let docs = Project(name: "Docs", description: "Support articles")

        let filtered = ProjectListFilter.active.projects(
            from: [product, docs],
            searchText: "release"
        )

        #expect(filtered == [product])
    }

    @Test("Project management actions differ for active and archived projects")
    func projectManagementActionsReflectArchiveState() {
        let active = Project(name: "Active")
        let archived = Project(name: "Archived", isActive: false, isArchived: true)

        #expect(
            ProjectManagementAction.available(for: active)
                == [.open, .editSettings, .archive, .delete]
        )
        #expect(
            ProjectManagementAction.available(for: archived)
                == [.editSettings, .unarchive, .delete]
        )
    }

    @Test("Selection normalization clears stale project identifiers")
    func selectionNormalizationClearsMissingProject() {
        let project = Project(name: "Active")

        #expect(
            ProjectManagementSelection.normalizedProjectId(project.id, in: [project]) == project.id
        )
        #expect(
            ProjectManagementSelection.normalizedProjectId(UUID(), in: [project]) == nil
        )
        #expect(ProjectManagementSelection.normalizedProjectId(nil, in: [project]) == nil)
    }

    @Test("Editor presentation resolves existing project and ignores missing IDs")
    func editorPresentationResolvesExistingProject() {
        let project = Project(name: "Settings")

        #expect(ProjectEditorPresentation.create.project(from: [project]) == nil)
        #expect(ProjectEditorPresentation.edit(project.id).project(from: [project]) == project)
        #expect(ProjectEditorPresentation.edit(UUID()).project(from: [project]) == nil)
    }
}
