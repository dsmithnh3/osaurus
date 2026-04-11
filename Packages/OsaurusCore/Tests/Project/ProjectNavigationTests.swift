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

    @Test("ProjectSession is a value type with subMode")
    func projectSessionValueType() {
        var session = ProjectSession()
        session.activeProjectId = UUID()
        session.subMode = .work
        var copy = session
        copy.subMode = .chat
        // Prove it's a value type — original unchanged
        #expect(session.subMode == .work)
        #expect(copy.subMode == .chat)
    }

    @Test("ProjectSubMode defaults to chat and toggles to work")
    func projectSubMode() {
        var session = ProjectSession()
        #expect(session.subMode == .chat)
        session.subMode = .work
        #expect(session.subMode == .work)
        session.subMode = .chat
        #expect(session.subMode == .chat)
    }

    @Test("ProjectSession initializes with activeProjectId for restoration")
    func projectSessionRestoration() {
        let projectId = UUID()
        let session = ProjectSession(activeProjectId: projectId)
        #expect(session.activeProjectId == projectId)
        #expect(session.subMode == .chat)
    }

    @Test("NavigationEntry carries subMode for project entries")
    func navigationEntrySubMode() {
        let projectId = UUID()
        let sessionId = UUID()
        let chatEntry = NavigationEntry(
            mode: .project, projectId: projectId, sessionId: sessionId, subMode: .chat
        )
        #expect(chatEntry.subMode == .chat)

        let workEntry = NavigationEntry(
            mode: .project, projectId: projectId, sessionId: sessionId, subMode: .work
        )
        #expect(workEntry.subMode == .work)

        // Non-project entries default to nil subMode
        let chatModeEntry = NavigationEntry(mode: .chat)
        #expect(chatModeEntry.subMode == nil)
    }
}
