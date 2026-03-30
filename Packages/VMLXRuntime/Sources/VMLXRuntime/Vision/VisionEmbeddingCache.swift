import Foundation
import MLX
import CryptoKit
import os

/// Cached vision embedding for an already-processed image.
public struct CachedEmbedding: @unchecked Sendable {
    /// The vision encoder's output embedding.
    public let embedding: MLXArray
    /// SHA-256 hash of the original image data.
    public let dataHash: String
    /// Estimated memory in bytes.
    public let memoryBytes: Int
    /// When this was last accessed.
    public var lastAccessed: CFAbsoluteTime

    public init(embedding: MLXArray, dataHash: String) {
        self.embedding = embedding
        self.dataHash = dataHash
        self.memoryBytes = embedding.nbytes
        self.lastAccessed = CFAbsoluteTimeGetCurrent()
    }
}

/// LRU cache for preprocessed image embeddings.
/// Avoids re-running the vision encoder for identical images across turns.
/// Keyed by SHA-256 hash of the raw image data.
public final class VisionEmbeddingCache: @unchecked Sendable {

    private let lock = OSAllocatedUnfairLock()
    private let maxEntries: Int
    private let maxMemoryBytes: Int

    // LRU ordered: oldest at front, newest at back
    private var entries: [(key: String, value: CachedEmbedding)] = []
    private var currentMemory: Int = 0

    // Stats
    public private(set) var hits: Int = 0
    public private(set) var misses: Int = 0

    public init(maxEntries: Int = 100, maxMemoryMB: Int = 512) {
        self.maxEntries = maxEntries
        self.maxMemoryBytes = maxMemoryMB * 1024 * 1024
    }

    /// Compute SHA-256 hash of image data for cache keying.
    public static func hashData(_ data: Data) -> String {
        let digest = SHA256.hash(data: data)
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    /// Fetch cached embedding for image data hash.
    public func fetch(dataHash: String) -> MLXArray? {
        let result: CachedEmbedding? = lock.withLock {
            guard let idx = entries.firstIndex(where: { $0.key == dataHash }) else {
                misses += 1
                return nil
            }

            // Touch and move to end (MRU)
            entries[idx].value.lastAccessed = CFAbsoluteTimeGetCurrent()
            let entry = entries.remove(at: idx)
            entries.append(entry)

            hits += 1
            return entry.value
        }
        return result?.embedding
    }

    /// Store embedding for image data hash.
    public func store(dataHash: String, embedding: MLXArray) {
        // Build CachedEmbedding outside lock so the @Sendable closure
        // captures the @unchecked Sendable struct, not the raw MLXArray.
        let cached = CachedEmbedding(embedding: embedding, dataHash: dataHash)

        lock.withLock {
            // Remove existing if present
            if let idx = entries.firstIndex(where: { $0.key == dataHash }) {
                let removed = entries.remove(at: idx)
                currentMemory -= removed.value.memoryBytes
            }

            // Evict until within limits
            while (currentMemory + cached.memoryBytes > maxMemoryBytes || entries.count >= maxEntries) && !entries.isEmpty {
                let removed = entries.removeFirst()
                currentMemory -= removed.value.memoryBytes
            }

            entries.append((key: dataHash, value: cached))
            currentMemory += cached.memoryBytes
        }
    }

    /// Check if an embedding is cached.
    public func contains(dataHash: String) -> Bool {
        lock.withLock {
            entries.contains { $0.key == dataHash }
        }
    }

    public var count: Int {
        lock.withLock { entries.count }
    }

    public var memoryUsed: Int {
        lock.withLock { currentMemory }
    }

    public func clear() {
        lock.withLock {
            entries.removeAll()
            currentMemory = 0
        }
    }
}
