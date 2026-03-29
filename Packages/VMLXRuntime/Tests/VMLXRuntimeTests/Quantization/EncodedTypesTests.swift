import Testing
import MLX
@testable import VMLXRuntime

@Suite("EncodedKeys")
struct EncodedKeysTests {

    @Test("EncodedKeys stores all components")
    func storesComponents() {
        let ek = EncodedKeys(
            indicesPacked: MLXArray.zeros([100], dtype: .uint32),
            qjlPacked: MLXArray.zeros([50], dtype: .uint32),
            residualNorms: MLXArray.zeros([200]),
            vectorNorms: MLXArray.zeros([200]),
            shape: [1, 8, 100, 128],
            indexBits: 3
        )
        #expect(ek.indexBits == 3)
        #expect(ek.shape == [1, 8, 100, 128])
        #expect(ek.vectorCount == 200)
        #expect(ek.estimatedBytes > 0)
    }

    @Test("Compression ratio > 1 for valid encoding")
    func compressionRatio() {
        // Simulate: 1 batch, 8 heads, 100 tokens, 128 dim
        // Original float16: 1*8*100*128 * 2 = 204800 bytes
        // Compressed: much smaller
        let ek = EncodedKeys(
            indicesPacked: MLXArray.zeros([800], dtype: .uint32),   // ~3200 bytes
            qjlPacked: MLXArray.zeros([400], dtype: .uint32),       // ~1600 bytes
            residualNorms: MLXArray.zeros([800]),                     // ~3200 bytes
            vectorNorms: MLXArray.zeros([800]),                       // ~3200 bytes
            shape: [1, 8, 100, 128],
            indexBits: 3
        )
        #expect(ek.compressionRatio > 1.0)
    }
}

@Suite("EncodedValues")
struct EncodedValuesTests {

    @Test("EncodedValues stores components")
    func storesComponents() {
        let ev = EncodedValues(
            indicesPacked: MLXArray.zeros([100], dtype: .uint32),
            vectorNorms: MLXArray.zeros([200]),
            shape: [1, 8, 100, 128],
            indexBits: 3
        )
        #expect(ev.indexBits == 3)
        #expect(ev.vectorCount == 200)
        #expect(ev.estimatedBytes > 0)
    }

    @Test("Values simpler than keys (no QJL)")
    func simplerThanKeys() {
        // EncodedValues has fewer fields than EncodedKeys
        let ev = EncodedValues(
            indicesPacked: MLXArray.zeros([100], dtype: .uint32),
            vectorNorms: MLXArray.zeros([200]),
            shape: [1, 8, 100, 128],
            indexBits: 3
        )
        let ek = EncodedKeys(
            indicesPacked: MLXArray.zeros([100], dtype: .uint32),
            qjlPacked: MLXArray.zeros([50], dtype: .uint32),
            residualNorms: MLXArray.zeros([200]),
            vectorNorms: MLXArray.zeros([200]),
            shape: [1, 8, 100, 128],
            indexBits: 3
        )
        // Values should use less memory (no QJL, no residual norms)
        #expect(ev.estimatedBytes < ek.estimatedBytes)
    }
}
