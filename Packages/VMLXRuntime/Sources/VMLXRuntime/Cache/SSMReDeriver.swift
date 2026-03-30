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

/// Actor that manages async re-derivation of SSM state.
///
/// When SSM checkpoint has been evicted but KV blocks exist:
/// 1. Run full forward pass on cached tokens (all layers — SSM can't run independently)
/// 2. Checkpoint SSM at stable boundary
/// 3. Store checkpoint for future use
/// 4. As side effect: refresh attention KV cache
///
/// Decision logic:
/// - Tokens < syncThreshold (default 512): sync re-derive (wait for result)
/// - Tokens >= syncThreshold: async re-derive (full prefill now, re-derive in background)
///
/// Deduplicates concurrent requests for the same token hash.
public actor SSMReDeriver {

    /// Threshold: below this token count, re-derive synchronously (worth waiting).
    public let syncThreshold: Int

    /// In-progress re-derivation tasks, keyed by token hash.
    private var activeTasks: [String: Task<SSMCheckpoint, Error>] = [:]

    /// Completed checkpoints waiting to be consumed.
    private var completedCheckpoints: [String: SSMCheckpoint] = [:]

    /// SSM state cache to store re-derived checkpoints.
    private let ssmCache: SSMStateCache

    /// Stats
    public private(set) var syncReDerives: Int = 0
    public private(set) var asyncReDerives: Int = 0
    public private(set) var deduplicatedRequests: Int = 0

    public init(ssmCache: SSMStateCache, syncThreshold: Int = 512) {
        self.ssmCache = ssmCache
        self.syncThreshold = syncThreshold
    }

    // MARK: - Decision Logic

    /// Decide whether to re-derive sync or async based on token count.
    public func shouldSyncReDerive(tokenCount: Int) -> Bool {
        tokenCount < syncThreshold
    }

    // MARK: - Re-Derivation

    /// Request SSM state re-derivation for a token sequence.
    /// If sync: waits and returns the checkpoint.
    /// If async: starts background task and returns nil (checkpoint stored when done).
    public func requestReDerive(
        tokens: [Int],
        stableBoundary: Int,
        forceSync: Bool = false
    ) async throws -> SSMCheckpoint? {
        let tokenHash = SSMStateCache.hashTokens(tokens, count: stableBoundary)

        // Check if already completed
        if let existing = completedCheckpoints[tokenHash] {
            return existing
        }

        // Check if already in progress (deduplicate)
        if let existingTask = activeTasks[tokenHash] {
            if forceSync || shouldSyncReDerive(tokenCount: tokens.count) {
                deduplicatedRequests += 1
                return try await existingTask.value
            }
            deduplicatedRequests += 1
            return nil  // Async — will complete later
        }

        // Start new re-derivation
        let task = Task<SSMCheckpoint, Error> {
            // Run full forward pass to recover SSM state
            // In production, this calls the model's forward pass on all tokens
            // For now, create a placeholder checkpoint

            // TODO: Actual forward pass through model
            // 1. Feed tokens[0:stableBoundary] through all layers
            // 2. Extract SSM layer states at stableBoundary
            // 3. Optionally refresh attention KV cache as side effect

            let checkpoint = SSMCheckpoint(
                ssmStates: [],  // Placeholder — populated by actual model forward pass
                boundary: stableBoundary,
                tokenHash: tokenHash
            )

            return checkpoint
        }

        activeTasks[tokenHash] = task

        if forceSync || shouldSyncReDerive(tokenCount: tokens.count) {
            syncReDerives += 1
            let checkpoint = try await task.value
            activeTasks.removeValue(forKey: tokenHash)
            completedCheckpoints[tokenHash] = checkpoint
            ssmCache.store(checkpoint: checkpoint)
            return checkpoint
        } else {
            asyncReDerives += 1
            // Fire and forget — store when complete
            Task {
                do {
                    let checkpoint = try await task.value
                    self.activeTasks.removeValue(forKey: tokenHash)
                    self.completedCheckpoints[tokenHash] = checkpoint
                    self.ssmCache.store(checkpoint: checkpoint)
                } catch {
                    self.activeTasks.removeValue(forKey: tokenHash)
                }
            }
            return nil  // Async — caller should proceed with full prefill
        }
    }

    // MARK: - Queries

    /// Check if a re-derivation is in progress for this token hash.
    public func isReDeriving(tokenHash: String) -> Bool {
        activeTasks[tokenHash] != nil
    }

    /// Check if a completed checkpoint exists.
    public func hasCheckpoint(tokenHash: String) -> Bool {
        completedCheckpoints[tokenHash] != nil
    }

    /// Get a completed checkpoint (and remove from pending).
    public func consumeCheckpoint(tokenHash: String) -> SSMCheckpoint? {
        completedCheckpoints.removeValue(forKey: tokenHash)
    }

    /// Number of active re-derivation tasks.
    public var activeTaskCount: Int {
        activeTasks.count
    }

    /// Clear all completed checkpoints.
    public func clearCompleted() {
        completedCheckpoints.removeAll()
    }

    /// Cancel all active re-derivation tasks.
    public func cancelAll() {
        for (_, task) in activeTasks {
            task.cancel()
        }
        activeTasks.removeAll()
    }
}
