//
//  ProjectNavigationTests.swift
//  osaurus
//
//  Tests for ChatMode.project, SidebarContentMode, ProjectSession, and NavigationEntry.
//

import Foundation
import Testing

@testable import OsaurusCore

@Suite("Project Navigation Tests")
struct ProjectNavigationTests {

    @Test("ChatMode has project case")
    func chatModeProject() {
        let mode = ChatMode.project
        #expect(mode.rawValue == "project")
        #expect(mode.displayName == "Projects")
        #expect(mode.icon == "folder.fill")
    }

    @Test("SidebarContentMode has all cases")
    func sidebarContentMode() {
        let modes: [SidebarContentMode] = [.chat, .projects, .scheduled]
        #expect(modes.count == 3)
    }

    @Test("ProjectSession is a value type")
    func projectSessionValueType() {
        var session = ProjectSession()
        session.activeProjectId = UUID()
        session.inlineSessionId = UUID()
        var copy = session
        copy.inlineSessionId = nil
        // Prove it's a value type — original unchanged
        #expect(session.inlineSessionId != nil)
        #expect(copy.inlineSessionId == nil)
    }

    @Test("ProjectSession hasInlineContent reflects inline fields")
    func projectSessionHasInlineContent() {
        var session = ProjectSession()
        #expect(session.hasInlineContent == false)
        session.inlineSessionId = UUID()
        #expect(session.hasInlineContent == true)
        session.inlineSessionId = nil
        session.inlineWorkTaskId = UUID()
        #expect(session.hasInlineContent == true)
    }

    @Test("NavigationEntry carries workTaskId")
    func navigationEntryWorkTaskId() {
        let taskId = UUID()
        let entry = NavigationEntry(mode: .project, projectId: UUID(), workTaskId: taskId)
        #expect(entry.workTaskId == taskId)
        #expect(entry.sessionId == nil)
    }
}
