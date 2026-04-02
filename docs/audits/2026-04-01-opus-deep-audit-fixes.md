# Opus Deep Audit Fixes — 2026-04-01

Full codebase audit of VMLXRuntime + OsaurusCore integration covering:
hybrid SSM, cache rehit, async rederivation, paged cache, TurboQuant, model implementations.

Four parallel audit agents were dispatched. All findings below were verified and fixed.

---

## Fixes Applied

### C1: NemotronH @ParameterInfo for aLog, D, dtBias (CRITICAL)

**File:** `Packages/VMLXRuntime/Sources/VMLXRuntime/Models/NemotronHModel.swift` lines 130-154

**Bug:** `aLog`, `D`, and `dtBias` in `NemotronHMamba2Mixer` were declared as plain `var` instead of `@ParameterInfo`-decorated properties. MLXNN's `model.update(parameters:)` never loaded weights for these fields from checkpoints. All SSM layers ran on zero-initialized defaults — SSM inference was completely wrong.

**Fix:** Changed to:
```swift
@ParameterInfo(key: "A_log") var aLog: MLXArray
@ParameterInfo(key: "D") var D: MLXArray
@ParameterInfo(key: "dt_bias") var dtBias: MLXArray
```
Updated init to use `_aLog.wrappedValue = ...` pattern.

**Verified against:** mlx-swift-lm reference `NemotronH.swift` lines 111-113.

---

### C2: NemotronH gate sizing for 512-expert variant (CRITICAL)

**File:** `Packages/VMLXRuntime/Sources/VMLXRuntime/Models/NemotronHModel.swift` lines 315-320

**Bug:** The MoE gate `Linear` was sized `hiddenSize/4` (latentDim) for the 512-expert variant, but `callAsFunction` feeds the full `hiddenSize` tensor to the gate at line 339. This would crash with a shape mismatch on the 120B Super model.

**Fix:** Gate always uses `config.hiddenSize` as input dimension — the latent projection is only for expert input/output, not the gate itself. Removed `gateDim` variable, hardcoded gate to `Linear(config.hiddenSize, config.nRoutedExperts, bias: false)`.

**Verified against:** Python reference `mlx-lm/models/nemotron_h.py` — gate weight is always `[num_experts, hidden_size]`.

---

### C3: SSM snapshot lazy copy corruption (CRITICAL)

**File:** `Packages/VMLXRuntime/Sources/VMLXRuntime/Integration/VMLXRuntimeActor.swift` line 656

**Bug:** `_captureCurrentSSMSnapshot()` used `$0[.ellipsis]` to "copy" MLXArrays. This creates a lazy view that shares the underlying buffer. Since Mamba2 state is modified in-place by subsequent forward passes, the snapshot was corrupted — it reflected post-generation state, not boundary state.

**Fix:** Changed to `$0 * 1` which forces a real buffer copy (same pattern used by `SSMStateCache._deepCopy` at line 132).

---

### C4: SSM layers dropped from HybridCache on partial cache-hit (CRITICAL)

**File:** `Packages/VMLXRuntime/Sources/VMLXRuntime/Integration/VMLXRuntimeActor.swift` lines 1237-1264

**Bug:** The post-generation cache store loop only appended SSM layers if `prefillSSMSnapshot != nil`. On partial cache-hit turns where the boundary capture conditions weren't met (e.g., `totalPrefillTokens <= 1` and `cachedTokenCount < storeTokensCount`), `prefillSSMSnapshot` was nil. SSM layers were silently dropped, making `HybridCache.layers.count < cache.count`. The layer-count guard in `_restoreCachedHybrid` would then reject all subsequent fetches, causing full cache misses for the rest of the session.

**Fix:** Added fallback capture: if `needSSMSnapshot && prefillSSMSnapshot == nil` at store time, capture SSM state then. This guarantees `HybridCache.layers.count == cache.count` invariant.

---

### H1: NemotronH dense MLP block type "-" handling (HIGH)

**File:** `Packages/VMLXRuntime/Sources/VMLXRuntime/Models/NemotronHModel.swift` lines 443-470

**Bug:** Block type `"-"` (dense MLP) in `hybridOverridePattern` fell through to the `default` case which creates `NemotronHMoE`. Any NemotronH variant with dense MLP layers would run MoE forward pass instead of a simple up/down projection.

**Fix:** Added `NemotronHDenseMLP` class using `intermediateSize` (not `moeIntermediateSize`) with relu-squared activation. Added `case "-"` to both init switch and `callAsFunction` switch.

**Verified against:** mlx-swift-lm reference `NemotronH.swift` — four block types: M (Mamba), * (attention), - (dense MLP), E (MoE).

---

### H4: SSMReDeriver chunked prefill (HIGH)

**File:** `Packages/VMLXRuntime/Sources/VMLXRuntime/Cache/SSMReDeriver.swift` lines 120-132

**Bug:** Re-deriver ran the full token sequence through `container.forward()` in a single call. For large MoE models (Mistral-119B, MiniMax-122B), this would OOM. The main generation path in VMLXRuntimeActor uses adaptive chunking (8-32 tokens for large models), but the re-deriver bypassed it entirely.

**Fix:** Added chunked prefill loop with adaptive chunk sizes:
- `>2048` tokens: 32-token chunks
- `>512` tokens: 128-token chunks
- `<=512` tokens: 512-token chunks

Added `Task.checkCancellation()` for cooperative cancellation and `Memory.clearCache()` between chunks.

---

### M1: TQ finalizePrefillIfNeeded decode window guard (MEDIUM)

**File:** `Packages/VMLXRuntime/Sources/VMLXRuntime/Quantization/TurboQuantKVCache.swift` lines 151-154

**Bug:** When `phase == .compressed` and `floatWindowKeys != nil` (active decode window), an external `finalizePrefillIfNeeded()` call would bypass the guard and re-quantize the entire decoded prefix + window. This destroyed the decode window, wasted encode/decode cycles, and could produce slightly different quantized values (lossy round-trip).

**Fix:** Changed guard from `phase == .compressed && floatWindowKeys == nil` to simply `phase == .compressed`. Already-compressed caches should never re-quantize — the decode window is intentionally kept as float.

---

### M2: TQ exportCacheEntry silent float fallback logging (MEDIUM)

**File:** `Packages/VMLXRuntime/Sources/VMLXRuntime/Quantization/TurboQuantKVCache.swift` lines 348-358

**Bug:** When `exportCacheEntry()` tried to merge a compressed prefix with a float decode window and the merge failed (e.g., asymmetric KV shapes), execution silently fell through to return full float KV. No logging, no indication that compression was permanently lost for that layer.

**Fix:** Added `#if DEBUG` print statement at the fallthrough point showing the layer index and window token count.

---

### M3: BlockMemoizer.clear() missing state resets (MEDIUM)

**File:** `Packages/OsaurusCore/Managers/BlockMemoizer.swift` lines 177-187

**Bug:** `clear()` reset all primary fingerprint fields but omitted `lastIsStreaming` and `lastHasStats`. Stale values from before the clear could cause incorrect fast-path decisions after re-population.

**Fix:** Added `lastIsStreaming = false` and `lastHasStats = false` to `clear()`.

---

### M4: SSMReDeriver completedCheckpoints memory leak (MEDIUM)

**File:** `Packages/VMLXRuntime/Sources/VMLXRuntime/Cache/SSMReDeriver.swift` lines 47, 155, 164, 196-210

**Bug:** `completedCheckpoints` dict grew unboundedly over long sessions — never evicted. `cancelAll()` cleared `activeTasks` but not `completedCheckpoints`. Over many prompts, this leaked memory proportional to the number of unique prompt prefixes.

**Fix:**
1. Added `maxCompletedCheckpoints = 8` cap
2. Added `_evictCompletedIfNeeded()` called after every checkpoint store
3. Made `cancelAll()` also clear `completedCheckpoints`

---

## Known Issues NOT Fixed (Documented for Future Work)

These were identified by audit but not fixed in this pass:

| ID | File | Description |
|----|------|-------------|
| H2 | VMLXRuntimeActor.swift:623-635 | `_injectSSMCheckpoint` double-restores SSM state from different boundary than `_restoreCachedHybrid` |
| H3 | CacheCoordinator.swift:271-307 | TOCTOU race in paged cache between block walk and reconstruction |
| H5 | GPTOSSModel.swift:372-410 | Mask reuse captures wrong layer index if `layerTypes` doesn't start with respective type |
| H6 | VMLXRuntimeActor.swift:1304 | `_trackGeneration` dispatches async — task can complete before registration |
| H7 | GPTOSSModel.swift:155-160 | `xUp`/`xGate` SwiGLU argument order needs Python reference verification |
| M5 | VMLXRuntimeActor.swift:399-411 | `unloadModel(name:)` doesn't cancel active generations or clear stale cache |
| M6 | VMLXRuntimeActor.swift:329-337 | `loadModel(name:)` uses substring matching fallback (violates No Name Matching rule) |
| M7 | CacheCoordinator.swift:720-733 | `_syncPagedWriteSession` data race on updateBlock+forkBlock under `@unchecked Sendable` |
| M9 | Mistral4Model.swift:419-431 | Llama4 position-dependent scaling reads post-update offset (latent, only if beta != 0) |
| M10 | SwitchLayers.swift:71 | `isSilu` always hardcoded true — custom activation silently ignored |
| L1 | CacheCoordinatorTests.swift:68-69 | Test asserts `detail == .memory` but default config enables paged cache |
| L2 | GPTOSSModel.swift:470-475 | Sliding window layers use non-rotating cache — unbounded memory on long sequences |

---

## Parser/Reasoning Resolution Fix

### Problem: UI Middleware and Engine Disagreed on Reasoning Format in Auto Mode

**Root cause:** Two independent resolution chains for reasoning format:

1. **Engine (VMLXRuntimeActor):** Falls back to `config.json model_type` → `ModelFamilyConfig.reasoningFormat`
2. **UI (StreamingMiddlewareResolver):** Falls back to model name substring matching (e.g., `id.contains("qwen3")`)

When no explicit override is set (auto mode), these fallbacks can disagree:
- Model with `model_type: "qwen3"` but custom name → engine detects correctly, UI misses
- Model named "qwen3-custom" with `model_type: "llama"` → UI falsely matches, engine doesn't

### Fix: Propagate Engine Config to UI Layer

**Files changed:**

| File | Change |
|------|--------|
| `VMLXRuntimeActor.swift` | Added `loadedFamilyConfig` public property |
| `VMLXService.swift` | Added `loadedFamilyConfig` async property |
| `VMLXServiceBridge.swift` | Captures config after model load; exposes via async and sync static accessors |
| `StreamingMiddleware.swift` | Refactored `StreamingMiddlewareResolver.resolve()` to accept `configReasoningFormat` and `configThinkInTemplate`; split into 3 clear priority stages |
| `StreamingDeltaProcessor.swift` | Added `configReasoningFormat` and `configThinkInTemplate` params, stored for `reset()` |
| `ChatView.swift` | Queries `VMLXServiceBridge.getConfigReasoningFormat()` before creating processor |
| `WorkSession.swift` | Uses `VMLXServiceBridge.lastKnownReasoningFormat` (sync snapshot) |

**New resolution priority (all 3 UI surfaces unified):**

```
1. Per-model override (ModelOptionsStore, set in ModelDetailView or Chat popover)
   ↓ if "auto"
2. Global override (ServerConfiguration, set in Settings/Inference)
   ↓ if "auto" or nil
3. Engine config (config.json model_type → ModelFamilyConfig.reasoningFormat)
   ↓ if nil (no model loaded or non-VMLX)
4. Name matching fallback (only for remote/non-VMLX models)
```

**`thinkInTemplate` handling:** Models where the chat template natively injects `<think>` tags (Qwen3, Qwen3.5, MiniMax) now correctly skip `PrependThinkTagMiddleware`, preventing double `<think>` injection.

**Shared backing store confirmed:** ModelDetailView and Chat popover both read/write to `ModelOptionsStore` keyed by model ID. Changes in one are immediately visible in the other. No clash between the 3 settings surfaces.

---

## Reasoning Box & Inference Audit Fixes

### GPT-OSS reasoningFormat: .qwen3 → .gptoss

**File:** `ModelConfig.swift:163-167`

**Bug:** GPT-OSS ModelFamilyConfig had `reasoningFormat: .qwen3`. This caused `VMLXServiceBridge` to report `configReasoningFormat = "qwen3"` to the UI middleware resolver, which selected `PrependThinkTagMiddleware` instead of `ChannelTagMiddleware`.

**Fix:** Changed to `reasoningFormat: .gptoss`. Also changed `reasoningParserForFormat(.gptoss)` in `ReasoningParser.swift:34-38` to return `ThinkTagReasoningParser()` (not `GPTOSSReasoningParser`) because the VMLX decode loop already converts `<|channel|>` tokens to `<think>` tags before the accumulator runs.

**Files:** `ModelConfig.swift:165`, `ReasoningParser.swift:34-38`

### MLXService reasoningEffort passthrough

**File:** `MLXGenerationEngine.swift:144-156`

**Bug:** `MLXGenerationEngine` only forwarded `disableThinking` to the chat template context. `reasoningEffort` from `modelOptions` was silently dropped for MLX models.

**Fix:** Added `reasoning_effort` to `additionalContext` dict when `modelOptions["reasoningEffort"]` is set. Uses dict merging pattern to combine with `enable_thinking`.

**Known limitation:** `toolParser` and `reasoningParser` per-model overrides cannot be forwarded to mlx-swift-lm — it has its own config.json-based tool call detection. Documented in code comment.

### mlxServiceOnlyTypes stays empty (intentional)

**File:** `ModelRegistry.swift:62-71`

Initially populated with `deepseek_v3`, `falcon_h1`, `granitemoehybrid`, `jamba_3b` — but reverted. Routing models to MLXService loses all VMLX features (TurboQuant, paged cache, L2 disk cache, SSM re-derivation). `StandardTransformerModel` handles most architectures. Models with custom architectures already have dedicated VMLX implementations. Empty set is correct. Added TODO comment for future audit.

### C4: SSM fallback — replaced by .placeholder approach

**File:** `VMLXRuntimeActor.swift:1252-1268`

My original fix captured SSM state at store time as a fallback. This was **replaced** by a better approach (by Eric/linter): when no boundary-aligned snapshot exists, `.placeholder` entries are emitted for SSM layers to preserve layer count alignment. Post-decode SSM state is contaminated with response tokens and would corrupt future cache hits. The placeholder triggers SSM re-derivation on the next fetch — correct behavior.

---

## Verification Summary

All fixes were re-read line-by-line from the actual files. Results:

| Fix | Verified | Notes |
|-----|----------|-------|
| C1: @ParameterInfo for aLog/D/dtBias | OK | Keys match mlx-swift-lm reference |
| C2: Gate sizing hiddenSize | OK | callAsFunction receives hiddenSize |
| C3: SSM snapshot $0 * 1 | OK | Matches _deepCopy pattern |
| C4: SSM placeholder | OK | Replaced by Eric, better than my original |
| H1: Dense MLP "-" block type | OK | Weight key "mixer" matches reference |
| H4: SSMReDeriver chunking | OK | Array-of-tuples type consistent |
| M1: TQ finalize guard | OK | trim() sets .fill first, guard doesn't block |
| M2: TQ export debug log | OK | DEBUG-only |
| M3: BlockMemoizer clear() | OK | Trivial |
| M4: SSMReDeriver eviction | OK | LRU via ordered array |
| GPT-OSS config .gptoss | OK | Engine uses ThinkTag, UI uses Channel |
| MLX reasoningEffort | OK | Dict merging pattern |
| Middleware resolver refactor | OK | All call sites updated |
| mlxServiceOnlyTypes empty | OK | Intentional, documented |

---

### C5: TQ cache export always emits float KV (CRITICAL — second-prompt garbage fix)

**File:** `Packages/VMLXRuntime/Sources/VMLXRuntime/Quantization/TurboQuantKVCache.swift` lines 377-383

**Bug:** `exportCacheEntry()` returned `.compressedAttention` when in compressed phase. On cache restore, the TQ-decoded (lossy) keys/values were the SOLE attention prefix — no fresh float window to anchor quality. For models with large headDim (Qwen3.5 headDim=256, 2-bit key codebook = 4 levels), the lossy approximation broke attention weights, producing degenerate output ("!!!!!!!!!") on the second prompt.

**Root cause:** TQ works during live inference because the float decode window provides fresh, exact-precision keys alongside the lossy prefix. On cache restore, the entire prefix is lossy with no anchoring float data, causing attention weight collapse.

**Fix:** `exportCacheEntry()` now ALWAYS returns `.attention` (float) by calling `getKeys()`/`getValues()` which concatenate decoded prefix + float window. TQ compression remains active for live inference memory savings (during the decode loop), but the persistent cache (memory/disk/paged) always stores original-quality float KV.

**Isolation method:** Confirmed via systematic testing:
1. Forced cache miss → works (proves conversation assembly is correct)
2. Skip SSM restore → still fails (proves SSM is not the issue)  
3. Disable TQ finalize → works (proves TQ lossy data is the cause)
4. Float-only export → works (the final fix)

---

### Additional Cache Fixes (2026-04-02)

**Paged cache COW violation in finalize** (`CacheCoordinator.swift`):
When `_syncPagedWriteSession` finalize updated committed blocks that were forked by other sessions (refCount > 1), it mutated shared data. Fix: allocate new block via COW when refCount > 1.

**`_reconstructFromBlocks` nil return** (`CacheCoordinator.swift`):
Layers with no data across all paged blocks (e.g., SSM without final snapshot) caused the entire reconstruction to return nil. Fix: emit `.placeholder` to preserve layer alignment.

**DiskCache `file_size` stale on re-store** (`DiskCache.swift`):
When `storeCache` overwrote an existing entry (e.g., float→TQ re-store), SQLite `file_size` retained the old value. Fix: added `_updateAccessAndSize()` that updates both fields.

**Paged store float→TQ upgrade** (`CacheCoordinator.swift`):
When `_storeToPagedCache` found existing float blocks but the source had TQ-compressed data, it just forked the stale float blocks. Fix: added `_blockHasCompressedUpgrade()` check to upgrade in-place when exclusively owned.

**Paged cache refCount leak** (`CacheCoordinator.swift`):
`_storeToPagedCache` called `forkBlock` on every dedup match with no cleanup path, making blocks non-evictable. Fix: removed `forkBlock` — `peekCachedBlock` already updates LRU timestamp.

---

### Test Gaps Identified

- No test for compressed-phase decode token accumulation (`appendDecodeTokens` after `compress()`)
- No test for `trim()` on compressed-phase cache
- No test for `finalizePrefillIfNeeded()` on compressed cache with float window
- No test for `exportCacheEntry()` with failed tail merge (MLA-asymmetric shapes)
- No test for mixed compressed/uncompressed paged blocks
- VMLXSmokeTest tests 7&8 don't emit `fail()` if no eligible cache entry found
