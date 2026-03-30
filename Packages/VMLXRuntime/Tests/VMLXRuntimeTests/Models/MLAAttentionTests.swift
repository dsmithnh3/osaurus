import Testing
import Foundation
@testable import VMLXRuntime

@Suite("MLAConfig")
struct MLAConfigTests {

    @Test("Parse from Mistral 4 config")
    func parseMistral4() {
        let config: [String: Any] = [
            "text_config": [
                "hidden_size": 4096,
                "num_attention_heads": 32,
                "kv_lora_rank": 256,
                "q_lora_rank": 1024,
                "qk_nope_head_dim": 64,
                "qk_rope_head_dim": 64,
                "v_head_dim": 128,
                "rope_theta": 10000.0,
                "rope_interleave": true,
            ] as [String: Any]
        ]

        let mla = MLAConfig.from(config: config)
        #expect(mla != nil)
        #expect(mla!.hiddenSize == 4096)
        #expect(mla!.numAttentionHeads == 32)
        #expect(mla!.kvLoraRank == 256)
        #expect(mla!.qLoraRank == 1024)
        #expect(mla!.qkNopeHeadDim == 64)
        #expect(mla!.qkRopeHeadDim == 64)
        #expect(mla!.vHeadDim == 128)
        #expect(mla!.totalQKHeadDim == 128)  // 64 + 64
        #expect(mla!.ropeInterleave == true)
    }

    @Test("Parse from DeepSeek V3 config (top-level)")
    func parseDeepSeekV3() {
        let config: [String: Any] = [
            "hidden_size": 7168,
            "num_attention_heads": 128,
            "kv_lora_rank": 512,
            "q_lora_rank": 1536,
            "qk_nope_head_dim": 128,
            "qk_rope_head_dim": 64,
            "v_head_dim": 128,
            "rope_theta": 10000.0,
        ]

        let mla = MLAConfig.from(config: config)
        #expect(mla != nil)
        #expect(mla!.hiddenSize == 7168)
        #expect(mla!.numAttentionHeads == 128)
        #expect(mla!.kvLoraRank == 512)
        #expect(mla!.qLoraRank == 1536)
        #expect(mla!.qkNopeHeadDim == 128)
        #expect(mla!.qkRopeHeadDim == 64)
        #expect(mla!.vHeadDim == 128)
        #expect(mla!.totalQKHeadDim == 192)  // 128 + 64
    }

    @Test("Returns nil for non-MLA models")
    func nonMLA() {
        // Standard GQA model without kv_lora_rank
        let config: [String: Any] = [
            "hidden_size": 4096,
            "num_attention_heads": 32,
            "num_key_value_heads": 8,
        ]
        #expect(MLAConfig.from(config: config) == nil)
    }

    @Test("Returns nil when kv_lora_rank is zero")
    func zeroKVRank() {
        let config: [String: Any] = [
            "kv_lora_rank": 0,
            "hidden_size": 4096,
        ]
        #expect(MLAConfig.from(config: config) == nil)
    }

    @Test("Defaults for optional fields")
    func defaults() {
        let config: [String: Any] = [
            "kv_lora_rank": 256,
        ]
        let mla = MLAConfig.from(config: config)
        #expect(mla != nil)
        #expect(mla!.hiddenSize == 4096)
        #expect(mla!.numAttentionHeads == 32)
        #expect(mla!.qkNopeHeadDim == 128)
        #expect(mla!.qkRopeHeadDim == 64)
        #expect(mla!.vHeadDim == 128)
        #expect(mla!.ropeTheta == 10000.0)
        #expect(mla!.qLoraRank == nil)
        #expect(mla!.ropeInterleave == false)
    }

    @Test("No q_lora_rank means direct Q projection")
    func noQLora() {
        let config: [String: Any] = [
            "kv_lora_rank": 256,
            "hidden_size": 2048,
            "num_attention_heads": 16,
        ]
        let mla = MLAConfig.from(config: config)
        #expect(mla != nil)
        #expect(mla!.qLoraRank == nil)
    }

    @Test("totalKeyDim matches totalQKHeadDim")
    func totalDims() {
        let config: [String: Any] = [
            "kv_lora_rank": 256,
            "qk_nope_head_dim": 96,
            "qk_rope_head_dim": 32,
        ]
        let mla = MLAConfig.from(config: config)!
        #expect(mla.totalQKHeadDim == 128)
        #expect(mla.totalKeyDim == 128)
        #expect(mla.totalQKHeadDim == mla.totalKeyDim)
    }
}
