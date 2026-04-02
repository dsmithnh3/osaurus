# Cache System Audit Fixes

Audit of hybrid cache SSM re-derivation, paged/disk cache storage, and TurboQuant encode/decode.

---

## Issue #1 — CRITICAL: NemotronH cache always misses (placeholder layer exclusion)

**Status**: FIXED

**Root cause**: NemotronH `hybridOverridePattern` has `-` (Dense MLP) and `E` (Expert MoE) layer types
that create `VMLXArraysCache(size: 0)` placeholders. These return `nil` from `exportCacheEntry()`,
so they're excluded from stored HybridCache. The live cache has 52 entries but the stored HybridCache
has ~30, so the guard `cachedHybrid.layerCount == cache.count` always fails → permanent cache miss.

Additionally, if the guard were bypassed, `_restoreCachedHybrid` maps by sequential index, causing
layer N in HybridCache to restore into wrong live cache slot (index misalignment).

**Files changed**:
- `LayerCache.swift` — add `.placeholder` case to `LayerCacheEntry`
- `KVCache.swift` — `VMLXArraysCache.exportCacheEntry()` returns `.placeholder` for size-0 caches
- `HybridCache.swift` — handle `.placeholder` in all switch/pattern matches
- `VMLXRuntimeActor.swift` — store path includes placeholder entries
- `CacheCoordinator.swift` — reconstruction handles placeholder
- `DiskCache.swift` — serialize/deserialize placeholder entries

**What changed**:
1. `LayerCache.swift`: Added `case placeholder` to `LayerCacheEntry` enum with `isPlaceholder`, `canTruncate: true`, `estimatedBytes: 0`, `truncated() → .placeholder`
2. `KVCache.swift` — `VMLXBaseKVCache.restore()`: Added `case .placeholder: return true` (no-op restore)
3. `KVCache.swift` — `VMLXArraysCache.exportCacheEntry()`: Returns `.placeholder` when `cache.isEmpty` (size-0 caches)
4. `KVCache.swift` — `VMLXArraysCache.restore()`: Accepts `.placeholder` entries (returns true)
5. `HybridCache.swift` — `materialized()`: Added `case .placeholder: break`
6. `VMLXRuntimeActor.swift` — store path (line ~1273): Added `.placeholder` to switch so placeholder entries are included in stored HybridCache
7. `VMLXRuntimeActor.swift` — `_exportLiveHybridCache` switch: Added `.placeholder` alongside `.ssm`
8. `VMLXRuntimeActor.swift` — debug log switch: Added `case .placeholder: return "placeholder"`
9. `CacheCoordinator.swift` — `_makePagedBlockData`: Added `case .placeholder: return .placeholder`
10. `CacheCoordinator.swift` — `_reconstructFromBlocks`: Detects all-placeholder layers and emits `.placeholder` instead of returning nil
11. `DiskCache.swift` — `storeCache`: Serializes `.placeholder` as `"placeholder"` type in metadata
12. `DiskCache.swift` — `fetchCache`: Deserializes `"placeholder"` type back to `.placeholder`
13. `TurboQuantKVCache.swift` — `restore()`: Added `.placeholder` alongside `.ssm` (returns false)

**Build**: Passes (swift build --package-path Packages/VMLXRuntime)

---

## Issue #2 — HIGH: Disk cache hybrid fetch ignores embedded SSM layers

**Status**: FIXED

**Root cause**: `_resolveHybridFetch()` only checks volatile `SSMStateCache` for SSM companion data.
After app restart, SSMStateCache is empty. But disk-loaded HybridCache already contains `.ssm` entries.
These are ignored → always reports `.partialHit` → unnecessary re-derivation or full prefill.

**Files changed**:
- `CacheCoordinator.swift` — `_resolveHybridFetch`

**What changed**:
1. `CacheCoordinator.swift` — `_resolveHybridFetch`: Added Path 2 between SSMStateCache lookup and partialHit fallback. After SSMStateCache miss, checks `cache.ssmLayers` for embedded SSM data. If found, builds ad-hoc `SSMCheckpoint` and promotes to SSMStateCache for future fetches. Returns `.hit` instead of `.partialHit`.
2. Removed the early `guard let ssmCache` that returned `.partialHit` when ssmStateCache was nil — now the embedded SSM check runs regardless.

**Build**: Passes

---

## Issue #3 — MEDIUM: SSM snapshot fallback captures post-decode state

**Status**: FIXED

**Root cause**: Fallback at VMLXRuntimeActor line ~1248 captures SSM state AFTER decode loop.
SSM state is cumulative — now includes generated response tokens. Storing this as boundary
checkpoint contaminates future cache hits.

**Files changed**:
- `VMLXRuntimeActor.swift` — cache store path (line ~1248)

**What changed**:
1. Removed the fallback `_captureCurrentSSMSnapshot()` call that captured post-decode contaminated SSM state
2. When `prefillSSMSnapshot == nil`, logs a warning instead of capturing bad state
3. SSM layers without a valid snapshot now emit `.placeholder` instead of being skipped entirely, preserving layer count alignment
4. The next fetch will see `.placeholder` where SSM data is expected → triggers `.partialHit` → proper SSM re-derivation

**Build**: Passes

---

## Issue #4 — MEDIUM: Paged block reconstruction fails for placeholder layers

**Status**: FIXED

**Root cause**: Same as #1. `_reconstructFromBlocks` returns nil when a layer has no data across
all blocks. With placeholder entries, these layers should produce `.placeholder` entries.

**Files changed**:
- `CacheCoordinator.swift` — `_reconstructFromBlocks` and `_makePagedBlockData` handle placeholder

**What changed**:
- (to be filled after fix)

---

## Issue #5 — LOW: SSMReDeriver eviction is not LRU

**Status**: FIXED

**Root cause**: `completedCheckpoints` is a Dictionary (unordered). `keys.first` evicts arbitrary entry.

**Files changed**:
- `SSMReDeriver.swift`

**What changed**:
1. Changed `completedCheckpoints` from `[String: SSMCheckpoint]` (unordered dict) to `[(key: String, checkpoint: SSMCheckpoint)]` (ordered array, oldest first)
2. Added `_insertCompleted(key:checkpoint:)` helper that removes existing entry before appending new one (dedup + ordering)
3. `_evictCompletedIfNeeded()` now uses `removeFirst()` which is true LRU (evicts oldest inserted)
4. `hasCheckpoint()` uses `.contains { $0.key == ... }`
5. `consumeCheckpoint()` uses `firstIndex(where:)` + `remove(at:)`
6. `requestReDerive()` uses `first(where:)` for completed lookup

**Build**: Passes

---

## Issue #6 — LOW: TurboQuant trim lossy decode-truncate-reencode

**Status**: FIXED

**Root cause**: `TurboQuantKVCache.trim()` decodes all compressed data to float, truncates,
then re-encodes — double quantization loss.

**Files changed**:
- `TurboQuantKVCache.swift` — `trim()`

**What changed**:
1. Added fast path before the decode-truncate-reencode fallback:
   - When target offset is within compressed region: uses `TurboQuantLayerCache.sliceCompressedAttention` to slice compressed data directly → `installCompressedState` (zero quantization loss)
   - When target offset is within float window region: truncates `floatWindowKeys`/`floatWindowValues` directly (no re-encode needed)
2. Original decode→truncate→re-encode path is preserved as fallback when direct slicing fails
3. Two common trim scenarios are now lossless: (a) trimming the tail of compressed prefix, (b) trimming decode window tokens

**Build**: Passes

---

## Issue #7 — LOW: Paged write session in-place block update while shared

**Status**: FIXED

**Root cause**: `_syncPagedWriteSession` calls `updateBlock` on a block that may have refCount > 1,
corrupting data seen by other references.

**Files changed**:
- `CacheCoordinator.swift` — `_syncPagedWriteSession`

**What changed**:
1. When finding an existing block by hash that is the last block AND `refCount > 1` (shared): allocates a NEW block with the updated data instead of mutating the shared block in-place. The new block gets its own refCount=1 and is registered in the hash map.
2. When `refCount <= 1` (exclusively owned): updateBlock in-place as before (safe, no other references).
3. Non-last blocks continue to use the existing fork path (no data mutation needed).

**Build**: Passes

---

## Issue #8 — HIGH: TurboQuant only available for JANG models

**Status**: FIXED

**Root cause**: `ModelContainer.create()` only built `TurboQuantConfig` inside a `if model.detected.isJang` gate.
Non-JANG MLX models (standard HuggingFace float16, Q4 GGUF-converted, etc.) got `turboQuantConfig = nil`,
so even when the user enabled TQ via settings, it had no config to use → TQ never activated.
Additionally, `adaptivePrefillStep` was gated on `container.isJang && experts >= 256` which excluded
non-JANG large MoE models from the memory-saving prefill step reduction.

**Files changed**:
- `ModelContainer.swift` — `create()` factory method
- `VMLXRuntimeActor.swift` — `adaptivePrefillStep`

**What changed**:
1. `ModelContainer.create()`: Extracted layer pattern detection to run before the JANG gate. Non-JANG models now get a default `TurboQuantConfig` with sensible defaults (3-bit keys/values, 4-bit critical layers). JANG models still get their customized TQ config from the profile. Both paths share the same `detectedLayerPattern`.
2. Non-JANG MLA models (Mistral4, DeepSeek): MLA dimensions (`mlaKeyDim`) are now set from `config.json` fields (`kvLoraRank`, `qkNopeHeadDim`, `qkRopeHeadDim`) regardless of JANG status.
3. `adaptivePrefillStep`: Changed gate from `container.isJang && experts >= 256` to just `experts >= 256` — any large MoE model benefits from reduced prefill steps.
4. TQ activation remains user-controlled: `scheduler.config.enableTurboQuant` must be true (from UI settings) for TQ to activate at runtime.

**Build**: Passes
