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
            mode: .project,
            projectId: projectId,
            sessionId: sessionId,
            subMode: .chat
        )
        #expect(chatEntry.subMode == .chat)

        let workEntry = NavigationEntry(
            mode: .project,
            projectId: projectId,
            sessionId: sessionId,
            subMode: .work
        )
        #expect(workEntry.subMode == .work)

        // Non-project entries default to nil subMode
        let chatModeEntry = NavigationEntry(mode: .chat)
        #expect(chatModeEntry.subMode == nil)
    }

    @Test("Restoring an unavailable project falls back to project list state")
    func restoreUnavailableProjectFallsBackToList() {
        let projectId = UUID()
        let archivedProject = Project(name: "Archived", isArchived: true)

        let deletedFallback = ChatWindowState.restoredProjectSession(
            projectId: projectId,
            requestedSubMode: .work,
            availableProjects: []
        )
        #expect(deletedFallback.activeProjectId == nil)
        #expect(deletedFallback.subMode == .chat)

        let archivedFallback = ChatWindowState.restoredProjectSession(
            projectId: archivedProject.id,
            requestedSubMode: .work,
            availableProjects: [archivedProject]
        )
        #expect(archivedFallback.activeProjectId == nil)
        #expect(archivedFallback.subMode == .chat)
    }

    @Test("Restoring an active project preserves requested sub-mode")
    func restoreActiveProjectPreservesSubMode() {
        let project = Project(name: "Active")

        let restored = ChatWindowState.restoredProjectSession(
            projectId: project.id,
            requestedSubMode: .work,
            availableProjects: [project]
        )

        #expect(restored.activeProjectId == project.id)
        #expect(restored.subMode == .work)
    }

    @Test("Reconciling an invalid active project clears project mode safely")
    func reconcileInvalidProjectInProjectMode() {
        let projectId = UUID()
        var session = ProjectSession(activeProjectId: projectId)
        session.subMode = .work

        let result = ChatWindowState.reconcileInvalidProject(
            mode: .project,
            projectSession: session,
            invalidProjectId: projectId
        )

        #expect(result.didChange)
        #expect(result.projectSession?.activeProjectId == nil)
        #expect(result.projectSession?.subMode == .chat)
        #expect(result.shouldUnregisterWorkTools)
    }

    @Test("Reconciling a different project leaves navigation state unchanged")
    func reconcileDifferentProjectDoesNothing() {
        let activeProjectId = UUID()
        let otherProjectId = UUID()
        let session = ProjectSession(activeProjectId: activeProjectId)

        let result = ChatWindowState.reconcileInvalidProject(
            mode: .project,
            projectSession: session,
            invalidProjectId: otherProjectId
        )

        #expect(!result.didChange)
        #expect(result.projectSession == session)
        #expect(!result.shouldUnregisterWorkTools)
    }
}
