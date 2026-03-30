import Testing
import Foundation
@testable import VMLXRuntime

@Suite("TransformerConfig")
struct TransformerConfigTests {

    @Test("Parse from Qwen3.5 config")
    func parseQwen() {
        let config: [String: Any] = [
            "hidden_size": 2048,
            "num_hidden_layers": 36,
            "num_attention_heads": 16,
            "num_key_value_heads": 2,
            "intermediate_size": 8960,
            "vocab_size": 151936,
            "rms_norm_eps": 1e-6,
            "rope_theta": 1000000.0,
            "max_position_embeddings": 40960
        ]
        let tc = TransformerConfig.from(config: config)
        #expect(tc.hiddenSize == 2048)
        #expect(tc.numLayers == 36)
        #expect(tc.numAttentionHeads == 16)
        #expect(tc.numKVHeads == 2)
        #expect(tc.intermediateSize == 8960)
        #expect(tc.vocabSize == 151936)
        #expect(tc.headDim == 128)  // 2048/16
    }

    @Test("Parse from nested text_config (VL model)")
    func parseVL() {
        let config: [String: Any] = [
            "model_type": "qwen3_5",
            "text_config": [
                "hidden_size": 3584,
                "num_hidden_layers": 28,
                "num_attention_heads": 28,
                "num_key_value_heads": 4,
                "intermediate_size": 18944,
                "vocab_size": 151936,
                "rms_norm_eps": 1e-6
            ] as [String: Any]
        ]
        let tc = TransformerConfig.from(config: config)
        #expect(tc.hiddenSize == 3584)
        #expect(tc.numLayers == 28)
        #expect(tc.numKVHeads == 4)
    }

    @Test("Defaults for missing fields")
    func defaults() {
        let tc = TransformerConfig.from(config: [:])
        #expect(tc.hiddenSize == 4096)
        #expect(tc.numLayers == 32)
        #expect(tc.rmsNormEps == 1e-6)
        #expect(tc.ropeTheta == 10000.0)
    }

    @Test("Head dim computed from hidden/heads")
    func headDim() {
        let config: [String: Any] = [
            "hidden_size": 4096,
            "num_attention_heads": 32
        ]
        let tc = TransformerConfig.from(config: config)
        #expect(tc.headDim == 128)  // 4096/32
    }

    @Test("Explicit head_dim override")
    func headDimOverride() {
        let config: [String: Any] = [
            "hidden_size": 4096,
            "num_attention_heads": 32,
            "head_dim": 64  // Override
        ]
        let tc = TransformerConfig.from(config: config)
        #expect(tc.headDim == 64)
    }
}
