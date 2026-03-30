import Testing
import Foundation
import MLX
@testable import VMLXRuntime

@Suite("VisionEmbeddingCache")
struct VisionEmbeddingCacheTests {

    @Test("Hash is deterministic")
    func hashDeterministic() {
        let data = Data([1, 2, 3, 4, 5])
        let h1 = VisionEmbeddingCache.hashData(data)
        let h2 = VisionEmbeddingCache.hashData(data)
        #expect(h1 == h2)
        #expect(h1.count == 64)  // SHA-256 hex
    }

    @Test("Different data different hash")
    func differentHash() {
        let h1 = VisionEmbeddingCache.hashData(Data([1, 2, 3]))
        let h2 = VisionEmbeddingCache.hashData(Data([4, 5, 6]))
        #expect(h1 != h2)
    }

    @Test("Store and fetch")
    func storeAndFetch() {
        let cache = VisionEmbeddingCache(maxEntries: 10)
        let embedding = MLXArray.zeros([1, 256, 768])
        cache.store(dataHash: "abc123", embedding: embedding)

        let result = cache.fetch(dataHash: "abc123")
        #expect(result != nil)
        #expect(cache.hits == 1)
    }

    @Test("Miss returns nil")
    func miss() {
        let cache = VisionEmbeddingCache(maxEntries: 10)
        let result = cache.fetch(dataHash: "nonexistent")
        #expect(result == nil)
        #expect(cache.misses == 1)
    }

    @Test("LRU eviction by count")
    func lruEviction() {
        let cache = VisionEmbeddingCache(maxEntries: 2)
        cache.store(dataHash: "a", embedding: MLXArray.zeros([1, 10]))
        cache.store(dataHash: "b", embedding: MLXArray.zeros([1, 10]))
        cache.store(dataHash: "c", embedding: MLXArray.zeros([1, 10]))

        #expect(cache.count == 2)
        #expect(cache.fetch(dataHash: "a") == nil)  // Evicted
        #expect(cache.fetch(dataHash: "b") != nil)
    }

    @Test("Contains check")
    func contains() {
        let cache = VisionEmbeddingCache(maxEntries: 10)
        #expect(!cache.contains(dataHash: "x"))
        cache.store(dataHash: "x", embedding: MLXArray.zeros([1, 10]))
        #expect(cache.contains(dataHash: "x"))
    }

    @Test("Clear removes all")
    func clear() {
        let cache = VisionEmbeddingCache(maxEntries: 10)
        cache.store(dataHash: "a", embedding: MLXArray.zeros([1, 10]))
        cache.store(dataHash: "b", embedding: MLXArray.zeros([1, 10]))
        cache.clear()
        #expect(cache.count == 0)
        #expect(cache.memoryUsed == 0)
    }
}
