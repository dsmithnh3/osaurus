import Foundation
import MLX

/// TurboQuant-compressed key cache for a single attention layer.
/// Stored as packed codebook indices + quantized norms.
/// Stays compressed in GPU memory during decode (zero decompression overhead).
public struct EncodedKeys: @unchecked Sendable {
    /// Packed codebook indices (uint32). Multiple indices packed per uint32 element.
    public let indicesPacked: MLXArray

    /// Packed QJL (Quantized Johnson-Lindenstrauss) sign bits (uint32).
    /// Used for residual correction during decode.
    public let qjlPacked: MLXArray

    /// Per-vector residual norms (float16). Corrects quantization error.
    public let residualNorms: MLXArray

    /// Per-vector norms (float16). Scales the decoded vectors.
    public let vectorNorms: MLXArray

    /// Original tensor shape before compression (for reshape on decode).
    public let shape: [Int]

    /// Bits per codebook index (3-8). Lower = more compression, less precision.
    public let indexBits: Int

    public init(
        indicesPacked: MLXArray,
        qjlPacked: MLXArray,
        residualNorms: MLXArray,
        vectorNorms: MLXArray,
        shape: [Int],
        indexBits: Int
    ) {
        self.indicesPacked = indicesPacked
        self.qjlPacked = qjlPacked
        self.residualNorms = residualNorms
        self.vectorNorms = vectorNorms
        self.shape = shape
        self.indexBits = indexBits
    }

    /// Estimated memory in bytes (compressed representation).
    public var estimatedBytes: Int {
        indicesPacked.nbytes + qjlPacked.nbytes + residualNorms.nbytes + vectorNorms.nbytes
    }

    /// Number of vectors (tokens * heads) encoded.
    public var vectorCount: Int {
        vectorNorms.size
    }

    /// Compression ratio vs float16 original.
    /// float16 key: shape[0] * shape[1] * shape[2] * shape[3] * 2 bytes
    /// TQ key: estimatedBytes
    public var compressionRatio: Float {
        guard shape.count == 4 else { return 1.0 }
        let originalBytes = shape.reduce(1, *) * 2  // float16 = 2 bytes per element
        guard estimatedBytes > 0 else { return Float.infinity }
        return Float(originalBytes) / Float(estimatedBytes)
    }
}
