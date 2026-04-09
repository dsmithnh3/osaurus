//
//  Project.swift
//  osaurus
//
//  A project groups conversations, work tasks, schedules, watchers,
//  and memory under shared context.
//

import Foundation

/// A project that groups related work under shared context.
public struct Project: Identifiable, Codable, Sendable, Equatable {
    /// Unique identifier for the project
    public let id: UUID
    /// Display name of the project
    public var name: String
    /// Optional description of the project
    public var description: String?
    /// SF Symbol icon name
    public var icon: String
    /// Optional hex color string
    public var color: String?
    /// Optional folder path on disk
    public var folderPath: String?
    /// Security-scoped bookmark data for the folder
    public var folderBookmark: Data?
    /// Optional instructions injected into system prompt when this project is active
    public var instructions: String?
    /// Whether this project is actively being worked on
    public var isActive: Bool
    /// Whether this project has been archived
    public var isArchived: Bool
    /// When the project was created
    public let createdAt: Date
    /// When the project was last modified
    public var updatedAt: Date

    public init(
        id: UUID = UUID(),
        name: String,
        description: String? = nil,
        icon: String = "folder.fill",
        color: String? = nil,
        folderPath: String? = nil,
        folderBookmark: Data? = nil,
        instructions: String? = nil,
        isActive: Bool = true,
        isArchived: Bool = false,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.name = name
        self.description = description
        self.icon = icon
        self.color = color
        self.folderPath = folderPath
        self.folderBookmark = folderBookmark
        self.instructions = instructions
        self.isActive = isActive
        self.isArchived = isArchived
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}
