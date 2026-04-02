import Foundation
import MLX
import CryptoKit
import os

/// Status of a re-derivation task.
public enum ReDeriverStatus: Sendable {
    case idle
    case inProgress(tokenHash: String)
    case completed(SSMCheckpoint)
    case failed(Error)
}

/// Actor that manages re-derivation of SSM state when the SSM companion
/// cache entry has been evicted but attention KV blocks still exist.
///
/// When SSM checkpoint has been evicted but KV blocks exist:
/// 1. Run full forward pass on cached tokens (all layers)
/// 2. Extract SSM state from VMLXMambaCache objects after prefill
/// 3. Store checkpoint for future cache hits
///
/// Decision logic:
/// - Tokens < syncThreshold (default 512): sync re-derive (wait for result)
/// - Tokens >= syncThreshold: async re-derive (full prefill now, re-derive in background)
///
/// Deduplicates concurrent requests for the same token hash.
///
/// ## Integration with VMLXRuntimeActor
///
/// The re-deriver accepts a `VMLXModelContainer` reference for running the
/// forward pass. After prefill, SSM state is extracted from VMLXMambaCache
/// objects in the cache array.
///
/// Currently, the generation loop uses a safe fallback: full prefill on
/// partialHit re-derives SSM state as a side effect, and CacheCoordinator.store()
/// saves the SSM companion for future turns. The re-deriver provides an
/// explicit path for targeted re-derivation when the full fallback is too slow.
public actor SSMReDeriver {

    /// Threshold: below this token count, re-derive synchronously (worth waiting).
    public let syncThreshold: Int

    /// In-progress re-derivation tasks, keyed by token hash.
    private var activeTasks: [String: Task<SSMCheckpoint, Error>] = [:]

    /// Completed checkpoints in insertion order (oldest first). Capped at maxCompletedCheckpoints.
    /// Uses ordered array instead of Dictionary so eviction is truly LRU (oldest inserted).
    private var completedCheckpoints: [(key: String, checkpoint: SSMCheckpoint)] = []
    private let maxCompletedCheckpoints = 8

    /// SSM state cache to store re-derived checkpoints.
    private let ssmCache: SSMStateCache

    /// Model container for running prefill during re-derivation.
    /// When nil, requestReDerive() returns nil immediately.
    private var container: VMLXModelContainer?

    /// Stats
    public private(set) var syncReDerives: Int = 0
    public private(set) var asyncReDerives: Int = 0
    public private(set) var deduplicatedRequests: Int = 0

    public init(ssmCache: SSMStateCache, syncThreshold: Int = 512) {
        self.ssmCache = ssmCache
        self.syncThreshold = syncThreshold
    }

    /// Update the model container reference (call after model load/unload).
    public func setModel(_ container: VMLXModelContainer?) {
        self.container = container
    }

    // MARK: - Decision Logic

    /// Decide whether to re-derive sync or async based on token count.
    public func shouldSyncReDerive(tokenCount: Int) -> Bool {
        tokenCount < syncThreshold
    }

    // MARK: - Re-Derivation

    /// Request SSM state re-derivation for a token sequence.
    ///
    /// Runs prefill on `tokens[0..<stableBoundary]` using the model container.
    /// After prefill, extracts SSM state from VMLXMambaCache objects.
    ///
    /// If sync: waits and returns the checkpoint.
    /// If async: starts background task and returns nil (checkpoint stored when done).
    ///
    /// - Parameters:
    ///   - tokens: Full token sequence for the conversation.
    ///   - stableBoundary: Token index up to which state should be checkpointed.
    ///   - forceSync: If true, always wait for the result regardless of token count.
    public func requestReDerive(
        tokens: [Int],
        stableBoundary: Int,
        forceSync: Bool = false
    ) async throws -> SSMCheckpoint? {
        let tokenHash = SSMStateCache.hashTokens(tokens, count: stableBoundary)

        // Check if already completed
        if let existing = completedCheckpoints.first(where: { $0.key == tokenHash }) {
            return existing.checkpoint
        }

        // Check if already in progress (deduplicate)
        if let existingTask = activeTasks[tokenHash] {
            if forceSync || shouldSyncReDerive(tokenCount: stableBoundary) {
                deduplicatedRequests += 1
                return try await existingTask.value
            }
            deduplicatedRequests += 1
            return nil
        }

        // Need a model to re-derive
        guard let container = self.container else {
            return nil
        }

        // Start new re-derivation
        let prefillTokens = Array(tokens.prefix(stableBoundary))
        let task = Task<SSMCheckpoint, Error> {
            // Run chunked forward pass to re-derive SSM state.
            // Chunking prevents OOM on large MoE models (Mistral-119B, MiniMax-122B).
            let cache = container.newCache()

            if !prefillTokens.isEmpty {
                let inputIds = MLXArray(prefillTokens.map { Int32($0) })
                let totalTokens = prefillTokens.count
                // Adaptive chunk size: small for large token counts to limit peak memory
                let chunkSize = totalTokens > 2048 ? 32 : (totalTokens > 512 ? 128 : 512)
                var pos = 0
                while pos < totalTokens {
                    try Task.checkCancellation()
                    let end = min(pos + chunkSize, totalTokens)
                    let chunk = inputIds[pos..<end].expandedDimensions(axis: 0)
                    _ = container.forward(chunk, cache: cache)
                    MLX.eval(cache)
                    Memory.clearCache()
                    pos = end
                }
            }

            // Extract SSM states from VMLXMambaCache objects
            var ssmStates: [SSMStateLayer] = []
            for c in cache {
                if let mambaCache = c as? VMLXMambaCache, !mambaCache.state.isEmpty {
                    ssmStates.append(SSMStateLayer(state: mambaCache.state))
                }
            }

            return SSMCheckpoint(
                ssmStates: ssmStates,
                boundary: stableBoundary,
                tokenHash: tokenHash
            )
        }

        activeTasks[tokenHash] = task

        if forceSync || shouldSyncReDerive(tokenCount: stableBoundary) {
            syncReDerives += 1
            let checkpoint = try await task.value
            activeTasks.removeValue(forKey: tokenHash)
            _insertCompleted(key: tokenHash, checkpoint: checkpoint)
            _evictCompletedIfNeeded()
            ssmCache.store(checkpoint: checkpoint)
            return checkpoint
        } else {
            asyncReDerives += 1
            Task {
                do {
                    let checkpoint = try await task.value
                    self.activeTasks.removeValue(forKey: tokenHash)
                    self._insertCompleted(key: tokenHash, checkpoint: checkpoint)
                    self._evictCompletedIfNeeded()
                    self.ssmCache.store(checkpoint: checkpoint)
                } catch {
                    self.activeTasks.removeValue(forKey: tokenHash)
                }
            }
            return nil
        }
    }

    // MARK: - Queries

    public func isReDeriving(tokenHash: String) -> Bool {
        activeTasks[tokenHash] != nil
    }

    public func hasCheckpoint(tokenHash: String) -> Bool {
        completedCheckpoints.contains { $0.key == tokenHash }
    }

    public func consumeCheckpoint(tokenHash: String) -> SSMCheckpoint? {
        guard let idx = completedCheckpoints.firstIndex(where: { $0.key == tokenHash }) else { return nil }
        return completedCheckpoints.remove(at: idx).checkpoint
    }

    public var activeTaskCount: Int {
        activeTasks.count
    }

    /// Insert a completed checkpoint, replacing any existing entry with the same key.
    private func _insertCompleted(key: String, checkpoint: SSMCheckpoint) {
        if let idx = completedCheckpoints.firstIndex(where: { $0.key == key }) {
            completedCheckpoints.remove(at: idx)
        }
        completedCheckpoints.append((key: key, checkpoint: checkpoint))
    }

    /// Evict oldest completed checkpoints when over the cap.
    /// Ordered array: index 0 is oldest (inserted first), so removeFirst is true LRU.
    private func _evictCompletedIfNeeded() {
        while completedCheckpoints.count > maxCompletedCheckpoints {
            completedCheckpoints.removeFirst()
        }
    }

    public func clearCompleted() {
        completedCheckpoints.removeAll()
    }

    public func cancelAll() {
        for (_, task) in activeTasks {
            task.cancel()
        }
        activeTasks.removeAll()
        completedCheckpoints.removeAll()
    }
}
