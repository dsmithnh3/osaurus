# Settings & Cache Stack Audit — 2026-04-02

Deep audit of VMLXRuntime cache settings UI, TurboQuant lifecycle, L2 disk cache,
and setting interdependencies. Covers: what's broken, what's confusing, what's missing.

---

## Settings Inventory

### Cache Stack Settings (ConfigurationView.swift ~483-507)

| # | Setting | UI Control | Property | Default | Validation | Issues |
|---|---------|-----------|----------|---------|------------|--------|
| 1 | TurboQuant | Toggle | `enableTurboQuant` | nil (off) | None | No gating with other settings |
| 2 | Disk Cache (L2) | Toggle | `enableDiskCache` | nil (off) | None | No gating with TQ |
| 3 | Memory Cache Budget | Slider | `cacheMemoryPercent` | nil (0.30) | 10-60% | Scale confusion (stored as 0.1-0.6) |

### KV Cache Settings (ConfigurationView.swift ~432-476)

| # | Setting | UI Control | Property | Default | Validation | Issues |
|---|---------|-----------|----------|---------|------------|--------|
| 4 | Max Context Length | Stepper | `genMaxKVSize` | 8192 | 1024-131072 | No model-aware cap |
| 5 | Cache Bits (KV Quant) | Stepper | `genKVBits` | nil (auto) | 2-8 | UI shows default=8, actual=nil |
| 6 | Group Size | Stepper | `genKVGroupSize` | 64 | 1-256 | OK |
| 7 | Quantized Start | Stepper | `genQuantizedKVStart` | 0 | 0-1024 | Active even when KV bits=nil |
| 8 | Prefill Step | Stepper | `genPrefillStepSize` | nil (auto) | 64-2048 | OK |

### Hidden/Missing Settings (only in SchedulerConfig, no UI)

| # | Setting | Property | Default | Impact |
|---|---------|----------|---------|--------|
| 9 | Use Paged Cache | `usePagedCache` | true | Major cache behavior change |
| 10 | Use Memory-Aware Cache | `useMemoryAwareCache` | true | Controls L1 strategy |
| 11 | Disk Cache Max Size | `diskCacheMaxGB` | 10.0 GB | No user control |
| 12 | TQ Bit Depth (keys) | `defaultKeyBits` | 3 | Hardcoded, no user control |
| 13 | TQ Bit Depth (values) | `defaultValueBits` | 3 | Hardcoded, no user control |

---

## Issues Found

### ISSUE 1: genQuantizedKVStart active when genKVBits is nil (HIGH)

**Location:** ConfigurationView.swift ~460-467
**Problem:** The "Quantized Start" stepper is always editable, but it only has meaning when KV Cache Bits is set. Setting it without KV bits does nothing.
**Fix:** Disable/hide the field when `tempKVBits` is empty.

### ISSUE 2: genKVBits default display misleading (MEDIUM)

**Location:** ConfigurationView.swift ~450
**Problem:** UI shows `defaultValue: 8` in the stepper, but the actual default in ServerConfiguration is `nil` (auto-detect). User sees "8" and thinks that's what's active.
**Fix:** Show placeholder "Auto" when empty. Remove misleading defaultValue.

### ISSUE 3: TurboQuant + KV Quant (genKVBits) can both be on — no warning (MEDIUM)

**Problem:** User can enable TQ (3-bit compression) AND set KV bits to 4. Both apply — KV quant during layer creation, then TQ on top after prefill. Double compression with no indication.
**Fix:** When TQ is on, show info text that TQ overrides/supplements KV quant. Or disable genKVBits when TQ is on.

### ISSUE 4: TurboQuant + Disk Cache no guidance (MEDIUM)

**Problem:** Both are independent toggles with no explanation of how they interact:
- TQ ON + Disk ON = compressed on disk (optimal — 5x smaller files)
- TQ OFF + Disk ON = float on disk (large files, ~33MB/layer for 4K context)
- TQ ON + Disk OFF = compressed in RAM only, lost on exit
- Both OFF = float in RAM only

**Fix:** Add descriptive help text. Optionally: when Disk Cache is enabled and TQ is off, show a note that enabling TQ reduces disk usage 5x.

### ISSUE 5: cacheMemoryPercent scale confusion (LOW)

**Location:** ConfigurationView.swift ~499-507
**Problem:** UI slider shows 10-60%, stored as 0.10-0.60 float. Code comments say "0.1-0.6" which could be misread as 0.1% to 0.6%. Not a bug but confusing.
**Fix:** Standardize all comments/docs to say "10-60% of available RAM."

### ISSUE 6: Changing cache settings silently clears all cached KV (HIGH)

**Location:** VMLXRuntimeActor.swift ~applyUserConfig
**Problem:** When any cache setting changes, a fingerprint is recomputed. If different from previous, CacheCoordinator is rebuilt — clearing ALL multi-turn cache. No warning to user.
**Fix:** Show a brief toast/warning when cache settings change mid-conversation: "Cache settings changed — multi-turn cache cleared."

### ISSUE 7: Paged cache / memory-aware cache not exposed in UI (MEDIUM)

**Location:** SchedulerConfig.swift ~42-58
**Problem:** `usePagedCache` and `useMemoryAwareCache` default to true. User has no visibility or control. Both share the same `cacheMemoryPercent`.
**Fix:** Either expose as an advanced toggle, or document that both are always on and share the budget.

### ISSUE 8: Disk cache max size not configurable (LOW)

**Location:** SchedulerConfig.swift
**Problem:** `diskCacheMaxGB` hardcoded at 10 GB. Power users may want more or less.
**Fix:** Add a stepper in advanced settings (1-50 GB).

### ISSUE 9: TQ bit depth not user-configurable (LOW)

**Problem:** TQ uses 3-bit default, 4-bit for critical layers (first/last 3). No UI to adjust.
**Impact:** Most users don't need this. Power users might want to trade quality for compression.
**Fix:** Low priority — could add an advanced stepper, but current defaults are well-tuned.

### ISSUE 10: Old disk cache files have wrong value index bits (BUG)

**Location:** DiskCache.swift ~403-407
**Problem:** Files written before the `__layer_i_value_index_bits__` fix fallback to `keyIndexBits + 1`, which is wrong when key and value bit depths differ.
**Impact:** Silent quality degradation on restore from old cache files.
**Fix:** Add a cache version field. On load, if version is old, discard and re-prefill instead of decoding with wrong bits. Or just warn and invalidate.

---

## TurboQuant Lifecycle (Reference)

```
1. Model loaded, TQ config resolved from model architecture
2. Prefill forward pass runs (KV cache fills with float16)
3. finalizePrefillIfNeeded() compresses:
   - Keys: (keyBits-1) MSE codebook + 1-bit QJL correction
   - Values: valueBits MSE codebook (no QJL)
   - First 4 tokens preserved as float16 sink tokens
4. Decode generation runs with compressed prefix + float window
5. On generation finish, cache exported:
   - .compressedAttention(EncodedKeys, EncodedValues, offset)
   - Always exports compressed form (never decodes to float for storage)
6. Stored to paged/memory/prefix/disk as-is
7. On next turn restore:
   - Compressed form decoded ONCE for inference buffers
   - NOT re-encoded (single decode, no quality drift)
   - New tokens append as float window
```

## Cache Fetch Order (Reference)

```
CacheCoordinator.fetch(tokens:)
  1. Paged cache  — block-level prefix match
  2. Memory cache — RAM-budget LRU prefix match  
  3. Prefix cache — trie-based (only when paged OFF)
  4. Disk cache   — exact hash + N-1 truncated fallback
  5. MISS         — full prefill
```

TQ compressed data survives ALL tiers without decompression or re-compression.

---

## Fix Priority

| Priority | Issue | Effort |
|----------|-------|--------|
| P0 | #1 Gate quantizedKVStart on kvBits | Small — UI only |
| P0 | #6 Warn on cache settings rebuild | Small — toast |
| P1 | #2 Fix genKVBits default display | Small — UI only |
| P1 | #3 TQ + KV quant interaction guidance | Small — help text |
| P1 | #4 TQ + Disk Cache guidance | Small — help text |
| P1 | #10 Old disk cache value bits bug | Medium — version check |
| P2 | #5 cacheMemoryPercent docs | Trivial |
| P2 | #7 Expose paged/memory-aware toggles | Medium — UI + plumbing |
| P2 | #8 Disk cache max size configurable | Small — UI + plumbing |
| P3 | #9 TQ bit depth configurable | Medium — not needed for beta |
