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

    // MARK: - Project Model Tests

    @Test func projectRoundTripsJSON() throws {
        let id = UUID()
        let now = Date()
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

    // MARK: - ProjectStore Tests

    @Test func storeSaveAndLoad() async throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        OsaurusPaths.overrideRoot = tempDir
        defer {
            OsaurusPaths.overrideRoot = nil
            try? FileManager.default.removeItem(at: tempDir)
        }

        let project = Project(name: "Store Test", description: "Testing save/load")
        await ProjectStore.save(project)

        let loaded = await ProjectStore.load(id: project.id)
        #expect(loaded != nil)
        #expect(loaded?.name == "Store Test")
        #expect(loaded?.description == "Testing save/load")
    }

    @Test func storeLoadAll() async throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        OsaurusPaths.overrideRoot = tempDir
        defer {
            OsaurusPaths.overrideRoot = nil
            try? FileManager.default.removeItem(at: tempDir)
        }

        let p1 = Project(name: "Alpha")
        let p2 = Project(name: "Beta")
        await ProjectStore.save(p1)
        await ProjectStore.save(p2)

        let all = await ProjectStore.loadAll()
        #expect(all.count == 2)
        // loadAll should sort by name
        #expect(all[0].name == "Alpha")
        #expect(all[1].name == "Beta")
    }

    @Test func storeDelete() async throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        OsaurusPaths.overrideRoot = tempDir
        defer {
            OsaurusPaths.overrideRoot = nil
            try? FileManager.default.removeItem(at: tempDir)
        }

        let project = Project(name: "To Delete")
        await ProjectStore.save(project)
        #expect(await ProjectStore.exists(id: project.id) == true)

        let deleted = await ProjectStore.delete(id: project.id)
        #expect(deleted == true)
        #expect(await ProjectStore.exists(id: project.id) == false)
        #expect(await ProjectStore.load(id: project.id) == nil)
    }

    @Test func storeDeleteNonexistent() async {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        OsaurusPaths.overrideRoot = tempDir
        defer {
            OsaurusPaths.overrideRoot = nil
            try? FileManager.default.removeItem(at: tempDir)
        }

        let deleted = await ProjectStore.delete(id: UUID())
        #expect(deleted == false)
    }

    @Test func storeExists() async {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        OsaurusPaths.overrideRoot = tempDir
        defer {
            OsaurusPaths.overrideRoot = nil
            try? FileManager.default.removeItem(at: tempDir)
        }

        let project = Project(name: "Existence Check")
        #expect(await ProjectStore.exists(id: project.id) == false)

        await ProjectStore.save(project)
        #expect(await ProjectStore.exists(id: project.id) == true)
    }
}
