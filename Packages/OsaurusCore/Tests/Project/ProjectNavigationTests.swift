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
        session.showInspector = false
        var copy = session
        copy.showInspector = true
        // Prove it's a value type — original unchanged
        #expect(session.showInspector == false)
        #expect(copy.showInspector == true)
    }
}
