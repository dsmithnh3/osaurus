//
//  NavigationStackTests.swift
//  osaurus
//
//  Tests for NavigationEntry value semantics and navigation stack logic.
//
//  ChatWindowState is @MainActor with AppKit dependencies that cannot be
//  instantiated in unit tests. Navigation stack logic is exercised through
//  a lightweight mirror that faithfully reproduces the production algorithm,
//  and NavigationEntry is exercised directly as a value type.
//

import Foundation
import Testing

@testable import OsaurusCore

// MARK: - Navigation Logic Mirror

/// Reproduces the push/back/forward algorithm from ChatWindowState without
/// any AppKit or singleton dependencies. Update this if the production logic changes.
private struct NavigationStack {
    private(set) var entries: [NavigationEntry] = []
    private(set) var index: Int = -1

    var canGoBack: Bool { index > 0 }
    var canGoForward: Bool { index < entries.count - 1 }

    var current: NavigationEntry? {
        guard index >= 0, index < entries.count else { return nil }
        return entries[index]
    }

    mutating func push(_ entry: NavigationEntry) {
        // Truncate forward history
        if index < entries.count - 1 {
            entries = Array(entries.prefix(index + 1))
        }
        entries.append(entry)
        index = entries.count - 1
    }

    mutating func goBack() {
        guard canGoBack else { return }
        index -= 1
    }

    mutating func goForward() {
        guard canGoForward else { return }
        index += 1
    }
}

// MARK: - NavigationEntry Tests

@Suite("NavigationEntry Value Type Tests")
struct NavigationEntryTests {

    @Test("NavigationEntry initializes with mode only")
    func initWithModeOnly() {
        let entry = NavigationEntry(mode: .chat)
        #expect(entry.mode == .chat)
        #expect(entry.projectId == nil)
        #expect(entry.sessionId == nil)
    }

    @Test("NavigationEntry initializes with all fields")
    func initWithAllFields() {
        let projectId = UUID()
        let sessionId = UUID()
        let entry = NavigationEntry(mode: .project, projectId: projectId, sessionId: sessionId)
        #expect(entry.mode == .project)
        #expect(entry.projectId == projectId)
        #expect(entry.sessionId == sessionId)
    }

    @Test("NavigationEntry equality holds for identical values")
    func equalityIdentical() {
        let pid = UUID()
        let sid = UUID()
        let a = NavigationEntry(mode: .work, projectId: pid, sessionId: sid)
        let b = NavigationEntry(mode: .work, projectId: pid, sessionId: sid)
        #expect(a == b)
    }

    @Test("NavigationEntry equality fails on different mode")
    func equalityDifferentMode() {
        let pid = UUID()
        let a = NavigationEntry(mode: .chat, projectId: pid)
        let b = NavigationEntry(mode: .work, projectId: pid)
        #expect(a != b)
    }

    @Test("NavigationEntry equality fails on different projectId")
    func equalityDifferentProjectId() {
        let a = NavigationEntry(mode: .project, projectId: UUID())
        let b = NavigationEntry(mode: .project, projectId: UUID())
        #expect(a != b)
    }

    @Test("NavigationEntry equality fails on different sessionId")
    func equalityDifferentSessionId() {
        let pid = UUID()
        let a = NavigationEntry(mode: .chat, projectId: pid, sessionId: UUID())
        let b = NavigationEntry(mode: .chat, projectId: pid, sessionId: UUID())
        #expect(a != b)
    }

    @Test("NavigationEntry with nil vs set projectId are not equal")
    func equalityNilVsSetProjectId() {
        let a = NavigationEntry(mode: .chat, projectId: nil)
        let b = NavigationEntry(mode: .chat, projectId: UUID())
        #expect(a != b)
    }

    @Test("NavigationEntry is a value type — copy is independent")
    func valueTypeSemantics() {
        let pid = UUID()
        let original = NavigationEntry(mode: .chat, projectId: pid, sessionId: UUID())
        // Reassign to a new entry (structs are values — no mutation needed to prove isolation)
        let copy = original
        #expect(copy == original)
        // A different entry with different sessionId is not equal
        let different = NavigationEntry(mode: .chat, projectId: pid, sessionId: UUID())
        #expect(different != original)
    }

    @Test("NavigationEntry supports all ChatMode cases")
    func allChatModes() {
        let modes: [ChatMode] = [.chat, .work, .project]
        for mode in modes {
            let entry = NavigationEntry(mode: mode)
            #expect(entry.mode == mode)
        }
    }
}

// MARK: - Navigation Stack Tests

@Suite("Navigation Stack Logic Tests")
struct NavigationStackTests {

    @Test("Empty stack has index -1 and cannot navigate")
    func emptyStack() {
        let stack = NavigationStack()
        #expect(stack.entries.isEmpty)
        #expect(stack.index == -1)
        #expect(!stack.canGoBack)
        #expect(!stack.canGoForward)
        #expect(stack.current == nil)
    }

    @Test("Push first entry sets index to 0")
    func pushFirstEntry() {
        var stack = NavigationStack()
        let entry = NavigationEntry(mode: .chat)
        stack.push(entry)
        #expect(stack.entries.count == 1)
        #expect(stack.index == 0)
        #expect(stack.current == entry)
        #expect(!stack.canGoBack)
        #expect(!stack.canGoForward)
    }

    @Test("Push second entry sets index to 1")
    func pushSecondEntry() {
        var stack = NavigationStack()
        stack.push(NavigationEntry(mode: .chat))
        let second = NavigationEntry(mode: .project, projectId: UUID())
        stack.push(second)
        #expect(stack.entries.count == 2)
        #expect(stack.index == 1)
        #expect(stack.current == second)
        #expect(stack.canGoBack)
        #expect(!stack.canGoForward)
    }

    @Test("canGoBack is true only when index > 0")
    func canGoBackThreshold() {
        var stack = NavigationStack()
        #expect(!stack.canGoBack)
        stack.push(NavigationEntry(mode: .chat))
        #expect(!stack.canGoBack)  // single entry, index = 0
        stack.push(NavigationEntry(mode: .work))
        #expect(stack.canGoBack)   // two entries, index = 1
    }

    @Test("canGoForward is true only when forward history exists")
    func canGoForwardThreshold() {
        var stack = NavigationStack()
        stack.push(NavigationEntry(mode: .chat))
        stack.push(NavigationEntry(mode: .work))
        #expect(!stack.canGoForward)  // at the end
        stack.goBack()
        #expect(stack.canGoForward)   // one entry ahead
    }

    @Test("goBack decrements index")
    func goBackDecrementsIndex() {
        var stack = NavigationStack()
        let first = NavigationEntry(mode: .chat)
        let second = NavigationEntry(mode: .work)
        stack.push(first)
        stack.push(second)
        stack.goBack()
        #expect(stack.index == 0)
        #expect(stack.current == first)
    }

    @Test("goBack does nothing when at start")
    func goBackAtStart() {
        var stack = NavigationStack()
        stack.push(NavigationEntry(mode: .chat))
        stack.goBack()  // no-op
        #expect(stack.index == 0)
    }

    @Test("goBack does nothing on empty stack")
    func goBackOnEmptyStack() {
        var stack = NavigationStack()
        stack.goBack()
        #expect(stack.index == -1)
    }

    @Test("goForward increments index")
    func goForwardIncrementsIndex() {
        var stack = NavigationStack()
        let first = NavigationEntry(mode: .chat)
        let second = NavigationEntry(mode: .project, projectId: UUID())
        stack.push(first)
        stack.push(second)
        stack.goBack()
        stack.goForward()
        #expect(stack.index == 1)
        #expect(stack.current == second)
    }

    @Test("goForward does nothing when at end")
    func goForwardAtEnd() {
        var stack = NavigationStack()
        stack.push(NavigationEntry(mode: .chat))
        stack.goForward()  // no-op
        #expect(stack.index == 0)
    }

    @Test("goForward does nothing on empty stack")
    func goForwardOnEmptyStack() {
        var stack = NavigationStack()
        stack.goForward()
        #expect(stack.index == -1)
    }

    @Test("Push truncates forward history")
    func pushTruncatesForwardHistory() {
        var stack = NavigationStack()
        let a = NavigationEntry(mode: .chat)
        let b = NavigationEntry(mode: .work)
        let c = NavigationEntry(mode: .project, projectId: UUID())
        stack.push(a)
        stack.push(b)
        stack.push(c)
        // Go back twice to index 0
        stack.goBack()
        stack.goBack()
        #expect(stack.index == 0)
        #expect(stack.entries.count == 3)

        // Push new entry — should truncate b and c
        let d = NavigationEntry(mode: .work, projectId: UUID())
        stack.push(d)
        #expect(stack.entries.count == 2)
        #expect(stack.entries[0] == a)
        #expect(stack.entries[1] == d)
        #expect(stack.index == 1)
        #expect(!stack.canGoForward)
    }

    @Test("Push from middle truncates and appends")
    func pushFromMiddle() {
        var stack = NavigationStack()
        stack.push(NavigationEntry(mode: .chat))
        stack.push(NavigationEntry(mode: .work))
        stack.push(NavigationEntry(mode: .project, projectId: UUID()))
        stack.goBack()  // index = 1

        let newEntry = NavigationEntry(mode: .chat, projectId: UUID())
        stack.push(newEntry)
        #expect(stack.index == 2)
        #expect(stack.entries.count == 3)
        #expect(stack.current == newEntry)
        #expect(!stack.canGoForward)
    }

    @Test("Back then forward returns to same entry")
    func backThenForwardIsIdempotent() {
        var stack = NavigationStack()
        let first = NavigationEntry(mode: .chat)
        let second = NavigationEntry(mode: .project, projectId: UUID())
        stack.push(first)
        stack.push(second)
        stack.goBack()
        stack.goForward()
        #expect(stack.current == second)
        #expect(stack.index == 1)
    }

    @Test("Multiple back/forward cycles maintain correct state")
    func multipleCycles() {
        var stack = NavigationStack()
        let entries = [
            NavigationEntry(mode: .chat),
            NavigationEntry(mode: .work),
            NavigationEntry(mode: .project, projectId: UUID()),
        ]
        for e in entries { stack.push(e) }
        // At index 2
        stack.goBack()   // index 1
        stack.goBack()   // index 0
        #expect(!stack.canGoBack)
        stack.goForward()  // index 1
        stack.goForward()  // index 2
        #expect(!stack.canGoForward)
        #expect(stack.current == entries[2])
    }

    @Test("NavigationEntry with projectId preserved through stack operations")
    func projectIdPreservedInStack() {
        var stack = NavigationStack()
        let projectId = UUID()
        let sessionId = UUID()
        let entry = NavigationEntry(mode: .project, projectId: projectId, sessionId: sessionId)
        stack.push(NavigationEntry(mode: .chat))
        stack.push(entry)
        stack.goBack()
        stack.goForward()
        let restored = stack.current
        #expect(restored?.projectId == projectId)
        #expect(restored?.sessionId == sessionId)
        #expect(restored?.mode == .project)
    }
}
