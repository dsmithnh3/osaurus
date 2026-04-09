//
//  ProjectStore.swift
//  osaurus
//
//  Persistence for Projects — JSON file per project at ~/.osaurus/projects/{uuid}.json
//

import Foundation

@MainActor
public enum ProjectStore {
    // MARK: - Public API

    /// Load all projects sorted by name
    public static func loadAll() -> [Project] {
        let directory = projectsDirectory()
        OsaurusPaths.ensureExistsSilent(directory)

        guard
            let files = try? FileManager.default.contentsOfDirectory(
                at: directory, includingPropertiesForKeys: nil)
        else {
            return []
        }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        var projects: [Project] = []
        for file in files where file.pathExtension == "json" {
            do {
                let data = try Data(contentsOf: file)
                let project = try decoder.decode(Project.self, from: data)
                projects.append(project)
            } catch {
                print("[Osaurus] Failed to load project from \(file.lastPathComponent): \(error)")
            }
        }

        return projects.sorted {
            $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
        }
    }

    /// Load a specific project by ID
    public static func load(id: UUID) -> Project? {
        let url = projectFileURL(for: id)
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }

        do {
            let data = try Data(contentsOf: url)
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            return try decoder.decode(Project.self, from: data)
        } catch {
            print("[Osaurus] Failed to load project \(id): \(error)")
            return nil
        }
    }

    /// Save a project (creates or updates)
    public static func save(_ project: Project) {
        let url = projectFileURL(for: project.id)
        OsaurusPaths.ensureExistsSilent(url.deletingLastPathComponent())

        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            encoder.dateEncodingStrategy = .iso8601
            let data = try encoder.encode(project)
            try data.write(to: url, options: [.atomic])
        } catch {
            print("[Osaurus] Failed to save project \(project.id): \(error)")
        }
    }

    /// Delete a project by ID
    @discardableResult
    public static func delete(id: UUID) -> Bool {
        do {
            try FileManager.default.removeItem(at: projectFileURL(for: id))
            return true
        } catch {
            print("[Osaurus] Failed to delete project \(id): \(error)")
            return false
        }
    }

    /// Check if a project exists
    public static func exists(id: UUID) -> Bool {
        FileManager.default.fileExists(atPath: projectFileURL(for: id).path)
    }

    // MARK: - Private

    private static func projectsDirectory() -> URL {
        OsaurusPaths.projects()
    }

    private static func projectFileURL(for id: UUID) -> URL {
        projectsDirectory().appendingPathComponent("\(id.uuidString).json")
    }
}
