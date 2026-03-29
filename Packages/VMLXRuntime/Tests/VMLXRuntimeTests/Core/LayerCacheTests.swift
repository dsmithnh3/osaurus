import Testing
import MLX
@testable import VMLXRuntime

@Suite("LayerCache")
struct LayerCacheTests {

    @Test("Attention entry stores and retrieves KV tensors")
    func attentionEntry() throws {
        let keys = MLXArray.zeros([1, 8, 64, 128])
        let values = MLXArray.zeros([1, 8, 64, 128])
        let entry = LayerCacheEntry.attention(KVCacheLayer(keys: keys, values: values, offset: 64))

        guard case .attention(let kv) = entry else {
            Issue.record("Expected attention entry")
            return
        }
        #expect(kv.offset == 64)
        #expect(kv.tokenCount == 64)
        #expect(kv.isAttention == true)
    }

    @Test("SSM entry stores cumulative state")
    func ssmEntry() throws {
        let state = [MLXArray.zeros([1, 16, 256])]
        let entry = LayerCacheEntry.ssm(SSMStateLayer(state: state, isCumulative: true))

        guard case .ssm(let ssm) = entry else {
            Issue.record("Expected SSM entry")
            return
        }
        #expect(ssm.isCumulative == true)
        #expect(ssm.canTruncate == false)
    }

    @Test("HybridCache tracks layer types correctly")
    func hybridCache() throws {
        var layers: [LayerCacheEntry] = []
        for i in 0..<48 {
            if i % 4 == 3 {
                let kv = KVCacheLayer(
                    keys: MLXArray.zeros([1, 8, 10, 128]),
                    values: MLXArray.zeros([1, 8, 10, 128]),
                    offset: 10
                )
                layers.append(.attention(kv))
            } else {
                let ssm = SSMStateLayer(
                    state: [MLXArray.zeros([1, 16, 256])],
                    isCumulative: true
                )
                layers.append(.ssm(ssm))
            }
        }

        let cache = HybridCache(layers: layers)
        #expect(cache.layerCount == 48)
        #expect(cache.isHybrid == true)
        #expect(cache.attentionLayerIndices.count == 12)
        #expect(cache.ssmLayerIndices.count == 36)
        #expect(cache.canTruncate == false)
    }

    @Test("Pure attention cache can truncate")
    func pureAttentionTruncate() throws {
        let layers: [LayerCacheEntry] = (0..<32).map { _ in
            .attention(KVCacheLayer(
                keys: MLXArray.zeros([1, 8, 100, 128]),
                values: MLXArray.zeros([1, 8, 100, 128]),
                offset: 100
            ))
        }

        let cache = HybridCache(layers: layers)
        #expect(cache.isHybrid == false)
        #expect(cache.canTruncate == true)

        let truncated = cache.truncated(to: 50)
        #expect(truncated != nil)
        #expect(truncated!.layers.count == 32)

        if case .attention(let kv) = truncated!.layers[0] {
            #expect(kv.offset == 50)
        }
    }

    @Test("Hybrid cache refuses truncation")
    func hybridRefusesTruncate() throws {
        let layers: [LayerCacheEntry] = [
            .attention(KVCacheLayer(keys: MLXArray.zeros([1, 8, 10, 128]), values: MLXArray.zeros([1, 8, 10, 128]), offset: 10)),
            .ssm(SSMStateLayer(state: [MLXArray.zeros([1, 16, 256])], isCumulative: true)),
        ]

        let cache = HybridCache(layers: layers)
        let truncated = cache.truncated(to: 5)
        #expect(truncated == nil)
    }

    @Test("estimateMemoryBytes returns non-zero for populated cache")
    func memoryEstimate() throws {
        let kv = KVCacheLayer(
            keys: MLXArray.zeros([1, 8, 100, 128]),
            values: MLXArray.zeros([1, 8, 100, 128]),
            offset: 100
        )
        let entry = LayerCacheEntry.attention(kv)
        #expect(entry.estimatedBytes > 0)
    }

    @Test("parseHybridPattern converts string to layer types")
    func parsePattern() {
        let pattern = parseHybridPattern("MMM*MMM*")
        #expect(pattern.count == 8)
        #expect(pattern[0] == .ssm)
        #expect(pattern[3] == .attention)
        #expect(pattern[7] == .attention)
    }

    @Test("HybridCache.fromPattern builds correctly")
    func fromPattern() {
        let pattern: [LayerType] = [.ssm, .ssm, .ssm, .attention]
        let cache = HybridCache.fromPattern(
            pattern,
            kvFactory: { KVCacheLayer(keys: MLXArray.zeros([1, 8, 10, 128]), values: MLXArray.zeros([1, 8, 10, 128]), offset: 10) },
            ssmFactory: { SSMStateLayer(state: [MLXArray.zeros([1, 16, 256])]) }
        )
        #expect(cache.layerCount == 4)
        #expect(cache.isHybrid == true)
        #expect(cache.ssmLayerIndices == [0, 1, 2])
        #expect(cache.attentionLayerIndices == [3])
    }

    @Test("Pure attention detection")
    func pureAttention() {
        let layers: [LayerCacheEntry] = [
            .attention(KVCacheLayer(keys: MLXArray.zeros([1, 8, 10, 128]), values: MLXArray.zeros([1, 8, 10, 128]), offset: 10)),
            .attention(KVCacheLayer(keys: MLXArray.zeros([1, 8, 10, 128]), values: MLXArray.zeros([1, 8, 10, 128]), offset: 10)),
        ]
        let cache = HybridCache(layers: layers)
        #expect(cache.isPureAttention == true)
        #expect(cache.isPureSSM == false)
        #expect(cache.isHybrid == false)
    }
}
