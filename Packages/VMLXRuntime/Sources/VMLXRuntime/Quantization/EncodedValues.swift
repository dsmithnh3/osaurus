import Foundation
import MLX

/// TurboQuant-compressed value cache for a single attention layer.
/// Simpler than keys — no QJL residual correction needed.
public struct EncodedValues: @unchecked Sendable {
    /// Packed codebook indices (uint32).
    public let indicesPacked: MLXArray

    /// Per-vector norms (float16).
    public let vectorNorms: MLXArray

    /// Original tensor shape before compression.
    public let shape: [Int]

    /// Bits per codebook index.
    public let indexBits: Int

    public init(
        indicesPacked: MLXArray,
        vectorNorms: MLXArray,
        shape: [Int],
        indexBits: Int
    ) {
        self.indicesPacked = indicesPacked
        self.vectorNorms = vectorNorms
        self.shape = shape
        self.indexBits = indexBits
    }

    /// Estimated memory in bytes (compressed).
    public var estimatedBytes: Int {
        indicesPacked.nbytes + vectorNorms.nbytes
    }

    /// Number of encoded vectors.
    public var vectorCount: Int {
        vectorNorms.size
    }

    /// Compression ratio vs float16 original.
    public var compressionRatio: Float {
        guard shape.count == 4 else { return 1.0 }
        let originalBytes = shape.reduce(1, *) * 2
        guard estimatedBytes > 0 else { return Float.infinity }
        return Float(originalBytes) / Float(estimatedBytes)
    }
}
