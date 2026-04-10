//
//  ProjectStoreTests.swift
//  osaurus
//
//  Tests for Project model encoding and ProjectStore persistence.
//

import Foundation
import Testing

@testable import OsaurusCore

struct ProjectStoreTests {

    // MARK: - Project Model Tests (no I/O, no overrideRoot)

    @Test func projectRoundTripsJSON() throws {
        let id = UUID()
        // Truncate to whole seconds so ISO8601 round-trip preserves equality
        let now = Date(timeIntervalSinceReferenceDate: Double(Int(Date().timeIntervalSinceReferenceDate)))
        let project = Project(
            id: id,
            name: "Test Project",
            description: "A test project",
            icon: "star.fill",
            color: "#FF0000",
            folderPath: "/tmp/test",
            folderBookmark: nil,
            instructions: "Do the thing",
            isActive: true,
            isArchived: false,
            createdAt: now,
            updatedAt: now
        )

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(project)

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode(Project.self, from: data)

        #expect(decoded == project)
        #expect(decoded.id == id)
        #expect(decoded.name == "Test Project")
        #expect(decoded.description == "A test project")
        #expect(decoded.icon == "star.fill")
        #expect(decoded.color == "#FF0000")
        #expect(decoded.folderPath == "/tmp/test")
        #expect(decoded.instructions == "Do the thing")
        #expect(decoded.isActive == true)
        #expect(decoded.isArchived == false)
    }

    @Test func projectDefaultValues() {
        let project = Project(name: "Minimal")
        #expect(project.name == "Minimal")
        #expect(project.description == nil)
        #expect(project.icon == "folder.fill")
        #expect(project.color == nil)
        #expect(project.folderPath == nil)
        #expect(project.folderBookmark == nil)
        #expect(project.instructions == nil)
        #expect(project.isActive == true)
        #expect(project.isArchived == false)
    }

    // MARK: - ProjectStore Persistence Tests
    // Uses ProjectManager.shared for real file I/O to avoid overrideRoot conflicts.

    @Test @MainActor func storeSaveAndLoad() async throws {
        let project = Project(name: "StoreTest-\(UUID().uuidString.prefix(8))", description: "Testing save/load")
        ProjectStore.save(project)
        defer { ProjectStore.delete(id: project.id) }

        let loaded = ProjectStore.load(id: project.id)
        #expect(loaded != nil)
        #expect(loaded?.name == project.name)
        #expect(loaded?.description == "Testing save/load")
    }

    @Test @MainActor func storeLoadAllContainsSavedProjects() async throws {
        let p1 = Project(name: "LoadAll-A-\(UUID().uuidString.prefix(8))")
        let p2 = Project(name: "LoadAll-B-\(UUID().uuidString.prefix(8))")
        ProjectStore.save(p1)
        ProjectStore.save(p2)
        defer {
            ProjectStore.delete(id: p1.id)
            ProjectStore.delete(id: p2.id)
        }

        let all = ProjectStore.loadAll()
        #expect(all.contains(where: { $0.id == p1.id }))
        #expect(all.contains(where: { $0.id == p2.id }))
    }

    @Test @MainActor func storeDelete() async throws {
        let project = Project(name: "Delete-\(UUID().uuidString.prefix(8))")
        ProjectStore.save(project)
        #expect(ProjectStore.exists(id: project.id) == true)

        let deleted = ProjectStore.delete(id: project.id)
        #expect(deleted == true)
        #expect(ProjectStore.exists(id: project.id) == false)
        #expect(ProjectStore.load(id: project.id) == nil)
    }

    @Test @MainActor func storeDeleteNonexistent() async {
        let deleted = ProjectStore.delete(id: UUID())
        #expect(deleted == false)
    }

    @Test @MainActor func storeExists() async {
        let project = Project(name: "Exists-\(UUID().uuidString.prefix(8))")
        #expect(ProjectStore.exists(id: project.id) == false)

        ProjectStore.save(project)
        defer { ProjectStore.delete(id: project.id) }
        #expect(ProjectStore.exists(id: project.id) == true)
    }
}
