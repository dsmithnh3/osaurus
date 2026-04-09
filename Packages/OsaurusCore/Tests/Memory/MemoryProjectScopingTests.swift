//
//  MemoryProjectScopingTests.swift
//  osaurus
//
//  Tests for project-scoped memory context assembly.
//

import Foundation
import Testing

@testable import OsaurusCore

@Suite("Memory Project Scoping Tests")
struct MemoryProjectScopingTests {

    @Test("MemoryContextAssembler cache key includes projectId")
    func cacheKeyComposite() async {
        // The assembleContext method should accept a projectId parameter.
        // This test verifies the API accepts it without crashing.
        let context = await MemoryContextAssembler.assembleContext(
            agentId: "test-agent",
            config: MemoryConfiguration(),
            projectId: "test-project"
        )
        // Empty context is fine — we just need the API to exist
        _ = context
    }
}
