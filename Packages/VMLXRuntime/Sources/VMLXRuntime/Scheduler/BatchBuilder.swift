import Foundation
import MLX

/// A prepared batch of requests ready for model forward pass.
public struct PreparedBatch: @unchecked Sendable {
    /// Batched input token IDs, shape [batchSize, maxSeqLen] (right-padded).
    public let inputIds: MLXArray

    /// Attention mask, shape [batchSize, maxSeqLen]. 1 = real token, 0 = padding.
    public let attentionMask: MLXArray

    /// Request IDs in batch order.
    public let requestIds: [String]

    /// Per-request sequence lengths (before padding).
    public let sequenceLengths: [Int]

    /// Batch size.
    public var batchSize: Int { requestIds.count }

    /// Max sequence length in this batch (includes padding).
    public var maxSeqLen: Int { sequenceLengths.max() ?? 0 }

    /// Per-request cached KV state (nil entries = no cache for that request).
    public let caches: [HybridCache?]

    /// Per-request pixel values for multimodal requests (nil = text only).
    public let pixelValues: [MLXArray?]
}

/// Builds batched tensors from a set of inference requests.
/// Handles variable-length sequences with right-padding.
public struct BatchBuilder: Sendable {

    /// Padding token ID (model-specific, usually 0 or EOS).
    public let padTokenId: Int

    public init(padTokenId: Int = 0) {
        self.padTokenId = padTokenId
    }

    /// Build a batch from a list of requests.
    /// Uses remainingTokenIds if available (cache hit), otherwise full promptTokenIds.
    public func buildPrefillBatch(requests: [InferenceRequest]) -> PreparedBatch {
        guard !requests.isEmpty else {
            return PreparedBatch(
                inputIds: MLXArray.zeros([0, 0], dtype: .int32),
                attentionMask: MLXArray.zeros([0, 0], dtype: .int32),
                requestIds: [],
                sequenceLengths: [],
                caches: [],
                pixelValues: []
            )
        }

        // Get uncached tokens for each request
        let tokenSequences: [[Int]] = requests.map { req in
            req.remainingTokenIds ?? req.promptTokenIds
        }

        let seqLengths = tokenSequences.map(\.count)
        let maxLen = seqLengths.max() ?? 0

        // Build padded arrays
        var paddedTokens: [[Int32]] = []
        var maskValues: [[Int32]] = []

        for tokens in tokenSequences {
            var padded = tokens.map { Int32($0) }
            var mask = [Int32](repeating: 1, count: tokens.count)

            // Right-pad to maxLen
            let padCount = maxLen - tokens.count
            if padCount > 0 {
                padded += [Int32](repeating: Int32(padTokenId), count: padCount)
                mask += [Int32](repeating: 0, count: padCount)
            }

            paddedTokens.append(padded)
            maskValues.append(mask)
        }

        // Convert to MLXArrays
        let flatTokens = paddedTokens.flatMap { $0 }
        let flatMask = maskValues.flatMap { $0 }

        let inputIds = MLXArray(flatTokens, [requests.count, maxLen])
        let attentionMask = MLXArray(flatMask, [requests.count, maxLen])

        return PreparedBatch(
            inputIds: inputIds,
            attentionMask: attentionMask,
            requestIds: requests.map(\.requestId),
            sequenceLengths: seqLengths,
            caches: requests.map(\.promptCache),
            pixelValues: requests.map(\.pixelValues)
        )
    }

    /// Build a decode batch (single token per request).
    /// Used during autoregressive generation after prefill.
    public func buildDecodeBatch(
        requestIds: [String],
        nextTokenIds: [Int]
    ) -> PreparedBatch {
        guard !requestIds.isEmpty else {
            return PreparedBatch(
                inputIds: MLXArray.zeros([0, 1], dtype: .int32),
                attentionMask: MLXArray.ones([0, 1], dtype: .int32),
                requestIds: [],
                sequenceLengths: [],
                caches: [],
                pixelValues: []
            )
        }

        let tokens = nextTokenIds.map { Int32($0) }
        let inputIds = MLXArray(tokens, [requestIds.count, 1])
        let mask = MLXArray([Int32](repeating: 1, count: requestIds.count), [requestIds.count, 1])

        return PreparedBatch(
            inputIds: inputIds,
            attentionMask: mask,
            requestIds: requestIds,
            sequenceLengths: [Int](repeating: 1, count: requestIds.count),
            caches: [HybridCache?](repeating: nil, count: requestIds.count),
            pixelValues: [MLXArray?](repeating: nil, count: requestIds.count)
        )
    }

    /// Split a batch into sub-batches of at most `maxBatchSize` requests.
    public func splitBatch(_ batch: PreparedBatch, maxBatchSize: Int) -> [PreparedBatch] {
        guard batch.batchSize > maxBatchSize else { return [batch] }

        var subBatches: [PreparedBatch] = []
        var offset = 0

        while offset < batch.batchSize {
            let end = min(offset + maxBatchSize, batch.batchSize)
            let subRequestIds = Array(batch.requestIds[offset..<end])
            let subSeqLens = Array(batch.sequenceLengths[offset..<end])
            let subCaches = Array(batch.caches[offset..<end])
            let subPixels = Array(batch.pixelValues[offset..<end])

            // Slice tensors along batch dimension (axis 0)
            let subInputIds = batch.inputIds[offset..<end]
            let subMask = batch.attentionMask[offset..<end]

            subBatches.append(PreparedBatch(
                inputIds: subInputIds,
                attentionMask: subMask,
                requestIds: subRequestIds,
                sequenceLengths: subSeqLens,
                caches: subCaches,
                pixelValues: subPixels
            ))

            offset = end
        }

        return subBatches
    }
}
