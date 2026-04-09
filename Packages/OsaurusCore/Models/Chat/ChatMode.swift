//
//  ChatMode.swift
//  osaurus
//
//  Defines the operating mode for the chat interface.
//

import Foundation

/// Operating mode for the chat window
public enum ChatMode: String, Codable, Sendable {
    /// Standard chat mode - conversational interaction
    case chat
    /// Work mode - task execution with issue tracking
    case work = "agent"
    /// Project mode - project home with scoped context
    case project

    public var displayName: String {
        switch self {
        case .chat: return L("Chat")
        case .work: return L("Work")
        case .project: return L("Projects")
        }
    }

    public var icon: String {
        switch self {
        case .chat: return "bubble.left.and.bubble.right"
        case .work: return "bolt.circle"
        case .project: return "folder.fill"
        }
    }
}
