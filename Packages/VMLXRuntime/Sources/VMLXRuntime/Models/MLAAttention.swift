import Foundation
import MLX
import MLXNN
import MLXFast

// MARK: - MLAConfig

/// Configuration for Multi-head Latent Attention (MLA).
///
/// MLA compresses KV projections through a low-rank latent space, reducing
/// KV cache memory from `O(n_heads * head_dim)` to `O(kv_lora_rank)`.
///
/// Used by DeepSeek V2/V3/R1 and Mistral 4 (Mistral Small 4).
///
/// Key config fields from model config.json:
/// - `kv_lora_rank` — latent dimension for KV compression
/// - `q_lora_rank` — latent dimension for Q compression (optional)
/// - `qk_nope_head_dim` — non-positional Q/K head dimension
/// - `qk_rope_head_dim` — rotary positional Q/K head dimension
/// - `v_head_dim` — value head dimension
public struct MLAConfig: Sendable {
    public let hiddenSize: Int
    public let numAttentionHeads: Int
    public let kvLoraRank: Int
    public let qLoraRank: Int?
    public let qkNopeHeadDim: Int
    public let qkRopeHeadDim: Int
    public let vHeadDim: Int
    public let ropeTheta: Float
    public let ropeInterleave: Bool

    /// Total Q/K head dimension = nope + rope.
    public var totalQKHeadDim: Int { qkNopeHeadDim + qkRopeHeadDim }

    /// Total key dimension per head for TQ config compatibility.
    public var totalKeyDim: Int { qkNopeHeadDim + qkRopeHeadDim }

    /// Parse from a model's config.json dictionary.
    /// Returns nil if the model does not use MLA (no `kv_lora_rank` field or zero).
    public static func from(config: [String: Any]) -> MLAConfig? {
        let tc = config["text_config"] as? [String: Any]

        func get<T>(_ key: String) -> T? {
            (config[key] as? T) ?? (tc?[key] as? T)
        }

        // MLA is indicated by the presence of kv_lora_rank > 0
        guard let kvRank: Int = get("kv_lora_rank"), kvRank > 0 else { return nil }

        return MLAConfig(
            hiddenSize: get("hidden_size") ?? 4096,
            numAttentionHeads: get("num_attention_heads") ?? 32,
            kvLoraRank: kvRank,
            qLoraRank: get("q_lora_rank"),
            qkNopeHeadDim: get("qk_nope_head_dim") ?? 128,
            qkRopeHeadDim: get("qk_rope_head_dim") ?? 64,
            vHeadDim: get("v_head_dim") ?? 128,
            ropeTheta: get("rope_theta") ?? 10000.0,
            ropeInterleave: get("rope_interleave") ?? false
        )
    }
}

// MARK: - MLA Latent KV Cache

/// KV cache for MLA that stores the compressed latent `c_kv` instead of
/// full K and V tensors. This is the key memory advantage of MLA:
/// cache size is `O(kv_lora_rank)` instead of `O(n_heads * head_dim)`.
///
/// For a model with kv_lora_rank=256 vs 32 heads * 128 head_dim = 4096,
/// this is a 16x memory reduction for the KV cache.
public final class MLALatentCache {
    /// Compressed KV latent: [B, seqLen, kvLoraRank]
    public var latent: MLXArray?

    /// Cached RoPE keys (rope portion only): [B, numHeads, seqLen, ropeHeadDim]
    public var ropeKeys: MLXArray?

    /// Current sequence length in the cache.
    public var sequenceLength: Int {
        latent?.dim(1) ?? 0
    }

    public init() {}

    /// Append new latent and rope key tensors.
    /// - Parameters:
    ///   - newLatent: shape [B, newSeqLen, kvLoraRank]
    ///   - newRopeKeys: shape [B, numHeads, newSeqLen, ropeHeadDim]
    /// - Returns: (accumulated latent, accumulated rope keys)
    public func update(
        latent newLatent: MLXArray,
        ropeKeys newRopeKeys: MLXArray
    ) -> (MLXArray, MLXArray) {
        if let existingLatent = latent, let existingRopeKeys = ropeKeys {
            let updatedLatent = concatenated([existingLatent, newLatent], axis: 1)
            let updatedRopeKeys = concatenated([existingRopeKeys, newRopeKeys], axis: 2)
            latent = updatedLatent
            ropeKeys = updatedRopeKeys
            return (updatedLatent, updatedRopeKeys)
        } else {
            latent = newLatent
            ropeKeys = newRopeKeys
            return (newLatent, newRopeKeys)
        }
    }
}

// MARK: - MLAAttention

/// Multi-head Latent Attention (MLA) module.
///
/// Instead of separate K,V projections, MLA compresses KV into a low-rank
/// latent space, then expands back to full K,V for attention computation.
///
/// Forward path:
/// 1. Q compression (optional): `c_q = W_qa(x)`, then `Q = W_qb(LayerNorm(c_q))`
///    - Or direct Q: `Q = W_q(x)` if q_lora_rank is nil
/// 2. KV compression: `c_kv = W_dkv(x)` where c_kv has dim `kv_lora_rank`
/// 3. KV expansion: `K_nope = W_uk(LayerNorm(c_kv))`, `V = W_uv(LayerNorm(c_kv))`
/// 4. Split Q,K into nope (non-positional) and rope (rotary) parts
/// 5. Apply RoPE only to rope parts
/// 6. Concatenate: `Q = [Q_nope, Q_rope]`, `K = [K_nope, K_rope]`
/// 7. Standard attention: `softmax(Q @ K^T / sqrt(d)) @ V`
///
/// Weight key mapping (Mistral 4 / DeepSeek naming):
/// ```
/// self_attn.q_a_proj         -> Q down-project (hidden -> q_lora_rank)
/// self_attn.q_a_layernorm    -> Q latent layernorm
/// self_attn.q_b_proj         -> Q up-project (q_lora_rank -> num_heads * totalQKHeadDim)
/// self_attn.kv_a_proj_with_mqa -> KV down-project (hidden -> kv_lora_rank + rope_dim)
/// self_attn.kv_a_layernorm   -> KV latent layernorm
/// self_attn.kv_b_proj        -> KV up-project (kv_lora_rank -> num_heads * (nope + v_head_dim))
/// self_attn.o_proj           -> output projection
/// ```
public class MLAAttention: Module {

    let numHeads: Int
    let kvLoraRank: Int
    let qkNopeHeadDim: Int
    let qkRopeHeadDim: Int
    let vHeadDim: Int
    let totalQKHeadDim: Int
    let scale: Float
    let hasQLora: Bool
    let ropeInterleave: Bool

    // Q path (with LoRA compression)
    @ModuleInfo(key: "q_a_proj") var qAProj: Linear?
    @ModuleInfo(key: "q_a_layernorm") var qALayerNorm: RMSNorm?
    @ModuleInfo(key: "q_b_proj") var qBProj: Linear?

    // Q path (direct, when q_lora_rank is nil)
    @ModuleInfo(key: "q_proj") var qProj: Linear?

    // KV down-projection: hidden -> kv_lora_rank + qk_rope_head_dim
    // The "with_mqa" suffix in Mistral 4 indicates the rope portion is
    // concatenated with the latent to form a single projection.
    @ModuleInfo(key: "kv_a_proj_with_mqa") var kvAProj: Linear

    // KV latent layernorm (applied to latent portion only)
    @ModuleInfo(key: "kv_a_layernorm") var kvALayerNorm: RMSNorm

    // KV up-projection: kv_lora_rank -> num_heads * (qk_nope_head_dim + v_head_dim)
    @ModuleInfo(key: "kv_b_proj") var kvBProj: Linear

    // Output projection
    @ModuleInfo(key: "o_proj") var oProj: Linear

    // RoPE for the rotary portion
    let rope: RoPE

    public init(_ config: MLAConfig) {
        self.numHeads = config.numAttentionHeads
        self.kvLoraRank = config.kvLoraRank
        self.qkNopeHeadDim = config.qkNopeHeadDim
        self.qkRopeHeadDim = config.qkRopeHeadDim
        self.vHeadDim = config.vHeadDim
        self.totalQKHeadDim = config.totalQKHeadDim
        self.scale = 1.0 / sqrt(Float(config.totalQKHeadDim))
        self.hasQLora = config.qLoraRank != nil
        self.ropeInterleave = config.ropeInterleave

        // RoPE: applied only to the rope portion of Q and K
        self.rope = RoPE(
            dimensions: config.qkRopeHeadDim,
            traditional: config.ropeInterleave,
            base: config.ropeTheta
        )

        // Q path
        if let qLoraRank = config.qLoraRank {
            // Q with LoRA compression
            self._qAProj.wrappedValue = Linear(config.hiddenSize, qLoraRank, bias: false)
            self._qALayerNorm.wrappedValue = RMSNorm(dimensions: qLoraRank)
            self._qBProj.wrappedValue = Linear(qLoraRank, numHeads * config.totalQKHeadDim, bias: false)
            self._qProj.wrappedValue = nil
        } else {
            // Direct Q projection
            self._qAProj.wrappedValue = nil
            self._qALayerNorm.wrappedValue = nil
            self._qBProj.wrappedValue = nil
            self._qProj.wrappedValue = Linear(config.hiddenSize, numHeads * config.totalQKHeadDim, bias: false)
        }

        // KV path: down-project to latent + rope, then up-project
        // Output of kv_a_proj: [kv_lora_rank + qk_rope_head_dim]
        // The rope portion is split off and not passed through the layernorm/up-project.
        self._kvAProj.wrappedValue = Linear(
            config.hiddenSize,
            config.kvLoraRank + config.qkRopeHeadDim,
            bias: false
        )
        self._kvALayerNorm.wrappedValue = RMSNorm(dimensions: config.kvLoraRank)

        // Up-project: kv_lora_rank -> num_heads * (qk_nope_head_dim + v_head_dim)
        self._kvBProj.wrappedValue = Linear(
            config.kvLoraRank,
            numHeads * (config.qkNopeHeadDim + config.vHeadDim),
            bias: false
        )

        // Output projection
        self._oProj.wrappedValue = Linear(numHeads * config.vHeadDim, config.hiddenSize, bias: false)
    }

    /// Forward pass through MLA attention.
    ///
    /// - Parameters:
    ///   - x: hidden states, shape [B, seqLen, hiddenSize]
    ///   - mask: optional additive attention mask
    ///   - cache: MLA latent cache for autoregressive generation
    ///   - offset: position offset for RoPE
    /// - Returns: output hidden states, shape [B, seqLen, hiddenSize]
    public func callAsFunction(
        _ x: MLXArray,
        mask: MLXArray? = nil,
        cache: MLALatentCache? = nil,
        offset: Int = 0
    ) -> MLXArray {
        let batchSize = x.dim(0)
        let seqLen = x.dim(1)

        // ---------------------------------------------------------------
        // Q projection
        // ---------------------------------------------------------------
        var queries: MLXArray
        if hasQLora, let qA = qAProj, let qNorm = qALayerNorm, let qB = qBProj {
            // Q with LoRA: hidden -> q_lora_rank -> layernorm -> num_heads * totalQKHeadDim
            let cQ = qA(x)
            let cQNorm = qNorm(cQ)
            queries = qB(cQNorm)
        } else if let qDirect = qProj {
            queries = qDirect(x)
        } else {
            fatalError("MLAAttention: no Q projection configured")
        }

        // Reshape Q: [B, seqLen, numHeads * totalQKHeadDim] -> [B, numHeads, seqLen, totalQKHeadDim]
        queries = queries.reshaped(batchSize, seqLen, numHeads, totalQKHeadDim)
            .transposed(0, 2, 1, 3)

        // Split Q into nope and rope parts
        let qNope = queries[0..., 0..., 0..., ..<qkNopeHeadDim]
        var qRope = queries[0..., 0..., 0..., qkNopeHeadDim...]

        // Apply RoPE to Q rope portion
        qRope = rope(qRope, offset: offset)

        // ---------------------------------------------------------------
        // KV projection
        // ---------------------------------------------------------------
        // Down-project: hidden -> [kv_lora_rank + qk_rope_head_dim]
        let kvA = kvAProj(x)

        // Split into latent and rope portions
        let cKV = kvA[0..., 0..., ..<kvLoraRank]          // [B, seqLen, kvLoraRank]
        var kRope = kvA[0..., 0..., kvLoraRank...]         // [B, seqLen, qkRopeHeadDim]

        // Reshape kRope for RoPE: [B, seqLen, ropeHeadDim] -> [B, 1, seqLen, ropeHeadDim]
        kRope = expandedDimensions(kRope, axis: 1)

        // Apply RoPE to K rope portion
        kRope = rope(kRope, offset: offset)

        // Update cache with latent and rope keys
        var fullCKV: MLXArray
        var fullKRope: MLXArray
        if let cache {
            (fullCKV, fullKRope) = cache.update(latent: cKV, ropeKeys: kRope)
        } else {
            fullCKV = cKV
            fullKRope = kRope
        }

        // Up-project the latent: kv_lora_rank -> num_heads * (qk_nope_head_dim + v_head_dim)
        let cKVNorm = kvALayerNorm(fullCKV)
        let kvB = kvBProj(cKVNorm)

        // Reshape: [B, totalSeqLen, numHeads * (nope + vHeadDim)] -> [B, numHeads, totalSeqLen, nope + vHeadDim]
        let totalSeqLen = fullCKV.dim(1)
        let kvReshaped = kvB.reshaped(batchSize, totalSeqLen, numHeads, qkNopeHeadDim + vHeadDim)
            .transposed(0, 2, 1, 3)

        // Split into K_nope and V
        let kNope = kvReshaped[0..., 0..., 0..., ..<qkNopeHeadDim]
        let values = kvReshaped[0..., 0..., 0..., qkNopeHeadDim...]

        // Broadcast kRope from [B, 1, totalSeqLen, ropeHeadDim] to [B, numHeads, totalSeqLen, ropeHeadDim]
        let kRopeBroadcast = MLX.broadcast(fullKRope, to: [batchSize, numHeads, totalSeqLen, qkRopeHeadDim])

        // Concatenate Q and K: [nope, rope]
        let fullQ = concatenated([qNope, qRope], axis: -1)
        let fullK = concatenated([kNope, kRopeBroadcast], axis: -1)

        // ---------------------------------------------------------------
        // Attention
        // ---------------------------------------------------------------
        let output: MLXArray
        if let mask {
            output = MLXFast.scaledDotProductAttention(
                queries: fullQ, keys: fullK, values: values,
                scale: scale, mask: mask
            )
        } else {
            output = MLXFast.scaledDotProductAttention(
                queries: fullQ, keys: fullK, values: values,
                scale: scale, mask: nil
            )
        }

        // output: [B, numHeads, seqLen, vHeadDim] -> [B, seqLen, numHeads * vHeadDim]
        let reshaped = output.transposed(0, 2, 1, 3).reshaped(batchSize, seqLen, numHeads * vHeadDim)

        return oProj(reshaped)
    }
}

// MARK: - MLA Transformer Block

/// A transformer decoder block using MLA attention instead of standard MHA/GQA.
///
/// Weight key mapping:
/// - `self_attn.*` -> MLA attention sub-module
/// - `mlp.*` -> FFN sub-module (standard SwiGLU or MoE)
/// - `input_layernorm.weight` -> pre-attention norm
/// - `post_attention_layernorm.weight` -> pre-FFN norm
public class MLATransformerBlock: Module {

    @ModuleInfo(key: "self_attn") var attention: MLAAttention
    @ModuleInfo(key: "mlp") var ffn: TransformerFFN
    @ModuleInfo(key: "input_layernorm") var inputLayerNorm: RMSNorm
    @ModuleInfo(key: "post_attention_layernorm") var postAttentionLayerNorm: RMSNorm

    public init(_ mlaConfig: MLAConfig, ffnConfig: TransformerConfig) {
        self._attention.wrappedValue = MLAAttention(mlaConfig)
        self._ffn.wrappedValue = TransformerFFN(ffnConfig)
        self._inputLayerNorm.wrappedValue = RMSNorm(
            dimensions: mlaConfig.hiddenSize,
            eps: 1e-6
        )
        self._postAttentionLayerNorm.wrappedValue = RMSNorm(
            dimensions: mlaConfig.hiddenSize,
            eps: 1e-6
        )
    }

    /// Forward pass through the MLA block.
    ///
    /// - Parameters:
    ///   - x: hidden states [B, seqLen, hiddenSize]
    ///   - mask: optional attention mask
    ///   - cache: MLA latent cache for this layer
    ///   - offset: position offset for RoPE
    /// - Returns: updated hidden states [B, seqLen, hiddenSize]
    public func callAsFunction(
        _ x: MLXArray,
        mask: MLXArray? = nil,
        cache: MLALatentCache? = nil,
        offset: Int = 0
    ) -> MLXArray {
        // Pre-norm attention with residual
        var h = x + attention(inputLayerNorm(x), mask: mask, cache: cache, offset: offset)
        // Pre-norm FFN with residual
        h = h + ffn(postAttentionLayerNorm(h))
        return h
    }
}
