import Testing
import Foundation
@testable import VMLXRuntime

@Suite("SSMReDeriver")
struct SSMReDeriverTests {

    @Test("Sync threshold decision")
    func syncThreshold() async {
        let cache = SSMStateCache(maxEntries: 10)
        let deriver = SSMReDeriver(ssmCache: cache, syncThreshold: 512)

        #expect(await deriver.shouldSyncReDerive(tokenCount: 100))   // Short — sync
        #expect(await deriver.shouldSyncReDerive(tokenCount: 511))   // Just under — sync
        #expect(await !deriver.shouldSyncReDerive(tokenCount: 512))  // At threshold — async
        #expect(await !deriver.shouldSyncReDerive(tokenCount: 1000)) // Long — async
    }

    @Test("Sync re-derive returns checkpoint")
    func syncReDerive() async throws {
        let cache = SSMStateCache(maxEntries: 10)
        let deriver = SSMReDeriver(ssmCache: cache, syncThreshold: 1000)

        let checkpoint = try await deriver.requestReDerive(
            tokens: [1, 2, 3, 4, 5],
            stableBoundary: 5,
            forceSync: true
        )

        #expect(checkpoint != nil)
        #expect(checkpoint?.boundary == 5)
        #expect(await deriver.syncReDerives == 1)
    }

    @Test("Async re-derive returns nil immediately")
    func asyncReDerive() async throws {
        let cache = SSMStateCache(maxEntries: 10)
        let deriver = SSMReDeriver(ssmCache: cache, syncThreshold: 1)  // Very low threshold

        let result = try await deriver.requestReDerive(
            tokens: Array(0..<100),
            stableBoundary: 100
        )

        #expect(result == nil)  // Async — returns nil immediately
        #expect(await deriver.asyncReDerives == 1)
    }

    @Test("Deduplicates concurrent requests")
    func deduplication() async throws {
        let cache = SSMStateCache(maxEntries: 10)
        let deriver = SSMReDeriver(ssmCache: cache, syncThreshold: 1000)

        // First request starts re-derive
        let r1 = try await deriver.requestReDerive(
            tokens: [1, 2, 3],
            stableBoundary: 3,
            forceSync: true
        )

        // Same tokens should return completed checkpoint
        let r2 = try await deriver.requestReDerive(
            tokens: [1, 2, 3],
            stableBoundary: 3,
            forceSync: true
        )

        #expect(r1 != nil)
        #expect(r2 != nil)
    }

    @Test("Stores checkpoint in SSM cache")
    func storesInCache() async throws {
        let cache = SSMStateCache(maxEntries: 10)
        let deriver = SSMReDeriver(ssmCache: cache, syncThreshold: 1000)

        _ = try await deriver.requestReDerive(
            tokens: [1, 2, 3],
            stableBoundary: 3,
            forceSync: true
        )

        #expect(cache.count == 1)  // Stored in SSM cache
    }

    @Test("Cancel all active tasks")
    func cancelAll() async {
        let cache = SSMStateCache(maxEntries: 10)
        let deriver = SSMReDeriver(ssmCache: cache)

        await deriver.cancelAll()
        #expect(await deriver.activeTaskCount == 0)
    }

    @Test("Has checkpoint check")
    func hasCheckpoint() async throws {
        let cache = SSMStateCache(maxEntries: 10)
        let deriver = SSMReDeriver(ssmCache: cache, syncThreshold: 1000)

        let tokenHash = SSMStateCache.hashTokens([1, 2, 3], count: 3)
        #expect(await !deriver.hasCheckpoint(tokenHash: tokenHash))

        _ = try await deriver.requestReDerive(tokens: [1, 2, 3], stableBoundary: 3, forceSync: true)
        #expect(await deriver.hasCheckpoint(tokenHash: tokenHash))
    }

    @Test("Consume removes checkpoint")
    func consumeCheckpoint() async throws {
        let cache = SSMStateCache(maxEntries: 10)
        let deriver = SSMReDeriver(ssmCache: cache, syncThreshold: 1000)

        let tokenHash = SSMStateCache.hashTokens([1, 2, 3], count: 3)
        _ = try await deriver.requestReDerive(tokens: [1, 2, 3], stableBoundary: 3, forceSync: true)

        let cp = await deriver.consumeCheckpoint(tokenHash: tokenHash)
        #expect(cp != nil)
        #expect(await !deriver.hasCheckpoint(tokenHash: tokenHash))  // Consumed
    }
}
