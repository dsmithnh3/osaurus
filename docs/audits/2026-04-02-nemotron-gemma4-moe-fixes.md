# Nemotron, Gemma4, MoE & Multi-Model Fixes

**Date:** 2026-04-02
**Branch:** feature/vmlx
**Commits:** 7ac83e43..4c2141e3 (11 commits)
**Files changed:** 13 files, +476 / -58 lines

---

## Critical Fixes

### 1. NemotronH Attention RoPE Was Completely Missing

**File:** `NemotronHModel.swift:266-281`
**Commit:** `7ac83e43`

The NemotronH attention layer created a RoPE object but **never applied it**. A wrong comment said "NemotronH attention has NO RoPE -- positions come from SSM blocks." This is incorrect -- SSM layers provide sequential ordering through recurrence, but attention layers still need explicit positional encoding.

**Before:** Attention output was position-invariant garbage.
**Fix:** Apply `rope(q, offset: offset)` and `rope(k, offset: offset)` with cache offset for correct multi-turn position indexing.

### 2. NemotronH Conv1d Weight Shape Transposed

**File:** `NemotronHModel.swift:593-598`
**Commit:** `d729e583`

HuggingFace stores depthwise conv1d weights as `[outChannels, 1, kernelSize]` but MLX Conv1d expects `[outChannels, kernelSize, inChannels/groups]`. Without the transpose, Mamba2 convolution produced completely wrong output, corrupting SSM state.

**Verified:** Cascade 30B conv1d.weight shape is `[6144, 1, 4]` in safetensors, needs `[6144, 4, 1]` for MLX.

### 3. Gemma4 Decoder Layer Architecture Wrong (Serial vs Parallel)

**File:** `Gemma4Model.swift:259-279`
**Commit:** `d729e583`

Our code ran attention -> dense MLP -> MoE **serially** with per-block `layer_scalar`. The HuggingFace reference shows dense MLP and MoE are **parallel branches**:

```
Path 1: dense MLP output -> post_feedforward_layernorm_1
Path 2: router(residual) -> experts -> post_feedforward_layernorm_2
Combined: post_feedforward_layernorm(path1 + path2) + residual
Final: * layer_scalar (applied once to full state)
```

**Before:** `postFeedforwardLayernorm1` weight was loaded but never used.

### 4. Gemma4 Router Used `take` Instead of `takeAlong`

**File:** `Gemma4Model.swift:206`
**Commit:** `d729e583`

`take(probs, topKIndices, axis: -1)` gathers by **index value**, not position. `takeAlong(probs, topKIndices, axis: -1)` correctly gathers the probability values at the selected expert positions. Every other model (StandardModel, Mistral4, NemotronH) used `takeAlong` correctly.

### 5. VMLXSwitchGLU Activation Hardcoded to SiLU

**File:** `SwitchLayers.swift:60-75`
**Commit:** `9e4116b2`

`isSilu` was hardcoded `true` regardless of the `activation` parameter. Gemma4 passes `geluApproximate` but got SiLU applied instead. Fixed by adding explicit `isSilu` and `isGelu` parameters.

### 6. Compiled Sampler Crashes (RandomBits)

**File:** `Sampler.swift:5-14`
**Commit:** `4c2141e3`

`compile(shapeless: true)` wrapping `MLXRandom.categorical` crashes with "RandomBits cannot infer output shapes" because MLX's compile tracer cannot handle random number generation primitives. Disabled compilation on the sampler. Other compiled functions (SwiGLU, GeGLU, GatedDelta) are pure math -- safe to compile.

---

## Performance Fixes

### 7. bfloat16 Conversion Threshold Lowered

**File:** `ModelRegistry.swift:171-184`
**Commit:** `9e4116b2`

Threshold changed from `numExperts >= 256` to `numExperts > 1`. ALL MoE models benefit from bfloat16 conversion -- prevents float16/float32 mixed-dtype promotion in Metal gate routing that kills performance. Gemma4 (128 experts) and Nemotron Cascade (128 experts) were missing bfloat16.

### 8. NemotronH `n_routed_experts` Detection

**File:** `ModelRegistry.swift:214`
**Commit:** `730d491a`

`_getNumExperts()` only checked `num_local_experts` and `num_experts` -- NemotronH uses `n_routed_experts`. Without this, Nemotron models skipped bfloat16 conversion entirely.

### 9. Prefill Throttle Raised for MoE

**File:** `VMLXRuntimeActor.swift:134-152`
**Commit:** `0a1bed4d`

Expert threshold raised from 256 to 512. Qwen3.5-35B has 256 experts but only activates 4 per token (3B active) -- runs fine at full prefill step. Only truly massive MoE (512+ like MiniMax-M2.5) needs throttling.

---

## TQ / Cache Compatibility Fixes

### 10. NemotronH Attention Uses Protocol-Level Cache

**Files:** `NemotronHModel.swift:279-286, 535`
**Commits:** `8a018081`, `683d740a`

Changed `(cache as? VMLXKVCacheSimple)?.offset` to `cache?.offset` and `cache.update()` via protocol. `VMLXKVCacheSimple` cast fails when TurboQuant wraps the cache as `TurboQuantKVCache`, causing:
- RoPE offset always 0 (wrong positions during generation)
- KV not updated (attention sees no context)
- Mask offset always 0 (wrong attention mask in multi-turn)

### 11. MLA vHeadDim Wiring for Mistral4 TQ

**File:** `ModelContainer.swift`
**Commit:** `b841a0f1`

Detect and wire `v_head_dim` from config.json into TQ config for MLA models (Mistral4). Without this, TQ used wrong value dimensions for MLA-style attention compression.

---

## Model Config / Detection Fixes

### 12. Nemotron Reasoning Format

**File:** `ModelConfig.swift:143-145`
**Commit:** `7ac83e43`

Added `reasoningFormat: .qwen3` and `thinkInTemplate: true` to Nemotron family config. Cascade uses `<think>` reasoning tags. Added `</s>` to default stop tokens for proper EOS handling.

### 13. EOS Detection for Nested text_config

**File:** `ModelLoader.swift`
**Commit:** `f70eb83c`

Models like Mistral4 nest `eos_token_id` under `text_config`. Fixed EOS parsing to check nested config when top-level is absent.

### 14. Mistral4 Chat Template Thinking

**File:** `VMLXRuntimeActor.swift`
**Commit:** `47d4497c`

Auto-map `enable_thinking` to `reasoning_effort` for Mistral4's chat template which uses a different parameter name.

### 15. VL Models Route to MLX Fallback

**File:** `ModelRegistry.swift:72-76`
**Commit:** `4c2141e3`

Added `qwen3_vl`, `qwen2_vl`, `qwen2_5_vl` to `mlxServiceOnlyTypes`. VL models need vision encoder pipeline -- loading as StandardTransformerModel crashes with Index out of range due to architecture mismatch.

### 16. Gemma4 Removed from StandardTransformerTypes

**File:** `ModelRegistry.swift:48`
**Commit:** `0a1bed4d`

Gemma4 needs a dedicated `Gemma4TextModel` (MoE + mixed sliding/full attention + dual MLP + custom router). Loading as StandardTransformerModel produces garbage.

### 17. SSM State Force-Unwrap Safety

**File:** `SSM.swift:296`
**Commit:** `7ac83e43`

`currentState!` in `vmlxSSMAttn` could crash on empty sequences. Replaced with safe fallback to zeros.

### 18. GatedDelta Compile Disabled for Hybrid SSM

**File:** `GatedDelta.swift:20-25`
**Commit:** `0a1bed4d`

`compile(shapeless:true)` on `computeGatedDeltaG` crashes during decode on hybrid SSM models. Disabled until MLX framework fixes compile + custom kernel interaction.

---

## Models Affected

| Model | Issues Fixed | Expected Impact |
|-------|-------------|-----------------|
| Nemotron Cascade 30B | #1 #2 #7 #8 #10 #12 #17 | Crash -> working, proper speed |
| Nemotron H-Super 120B | #1 #2 #7 #8 #10 #12 #17 | Same as Cascade |
| Gemma4 26B | #3 #4 #5 #7 #9 #16 | 3x speed gain (correct arch + bfloat16) |
| Mistral4 119B | #7 #11 #13 #14 | TQ works, EOS works, thinking works |
| Qwen3.5 35B MoE | #7 #9 #18 | bfloat16 + better prefill |
| Qwen3.5 4B dense | #17 #18 | SSM safety |
| Qwen3 VL | #15 | Crash -> proper MLX fallback |
| All MoE models | #6 #7 | No sampler crash, bfloat16 perf |

---

## Files Changed

| File | Lines | Changes |
|------|-------|---------|
| NemotronHModel.swift | +24 -12 | RoPE, conv1d transpose, cache protocol, sanitize |
| Gemma4Model.swift | +367 (new) | Full model implementation with correct architecture |
| ModelRegistry.swift | +33 -8 | bfloat16 threshold, VL routing, Gemma4 case, n_routed_experts |
| ModelConfig.swift | +7 -3 | Nemotron reasoning format |
| Sampler.swift | +10 -5 | Disable compiled sampler |
| VMLXRuntimeActor.swift | +22 -22 | Prefill throttle, Mistral4 thinking |
| SwitchLayers.swift | +8 -5 | isSilu/isGelu parameters |
| SSM.swift | +5 -1 | Force-unwrap safety |
| GatedDelta.swift | +7 -3 | Disable compile for hybrid SSM |
| ModelContainer.swift | +16 -2 | MLA vHeadDim wiring |
| ModelDetector.swift | +8 | Detection improvements |
| ModelLoader.swift | +10 | Nested EOS parsing |
| Mistral4Model.swift | +17 -2 | Chat template fixes |
