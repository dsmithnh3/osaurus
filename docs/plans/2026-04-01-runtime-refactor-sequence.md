# Runtime Refactor Sequence

Date: 2026-04-01

Status: COMPLETED

Purpose:
- Finish the remaining large runtime work without hand-waving:
  - persistent TurboQuant runtime cache
  - live paged runtime allocator
  - Qwen 3.5 35B JANG MoE prefill optimization
  - Mistral 4 latent MLA cache
- Keep both local runtime families working:
  - `VMLXRuntime` / JANG / VMLX-native models
  - `MLXService` / `ModelRuntime` / MLX models

This document is the execution order, not a wishlist. The phases are ordered by dependency so we stop doing throwaway work.

## Non-Negotiable Constraints

1. JANG / VMLX fixes must not silently break MLX routing or MLX generation.
2. MLX must not be rewritten to imitate VMLX where the design is intentionally different.
3. Hybrid JANG models must preserve the rule:
   TurboQuant applies to KV-bearing attention layers only, never SSM layers.
4. Mistral 4 must not be mixed into the hybrid SSM path just because it is large and weird.
   Its structural issue is MLA cache shape, not SSM companion logic.
5. UI/settings/runtime wiring must stay truthful:
   if a toggle is VMLX-only, the code and docs must say so.

## Dependency Order

The real dependency chain is:

1. cache substrate refactor
2. persistent TurboQuant runtime cache
3. live paged runtime allocator
4. Qwen 3.5 35B JANG MoE prefill optimization
5. Mistral 4 latent MLA cache
6. routing/UI/settings cleanup and cross-runtime validation

Why this order:
- Persistent TurboQuant and live paged allocation both depend on the same live-cache interfaces.
- Qwen 35B optimization should be done after the cache substrate is stable, otherwise profiling keeps shifting under us.
- Mistral 4 latent MLA is a separate structural refactor and should not be entangled with hybrid SSM cache work.

## Phase 0. Validation Harness First

Goal:
- Make the remaining large work measurable and regression-safe.

Files:
- [docs/audits/2026-04-01-cache-runtime-audit.md](/Users/eric/osa-jang/docs/audits/2026-04-01-cache-runtime-audit.md)
- [Packages/VMLXRuntime/Tests](/Users/eric/osa-jang/Packages/VMLXRuntime/Tests)
- [Packages/OsaurusCore/Tests](/Users/eric/osa-jang/Packages/OsaurusCore/Tests)

Add or tighten:
- focused VMLX cache tests for:
  - live TurboQuant cache restore/store
  - paged block-table lifecycle
  - hybrid cache-hit extension with compressed prefixes
- focused model-family tests for:
  - Nemotron H / Cascade layer-pattern KV-vs-SSM split
  - Qwen 3.5 linear-attention-vs-full-attention split
  - Mistral 4 latent-cache sizing once landed
- MLX regression checks for:
  - cache reuse still works
  - model routing still reaches MLX where intended

Acceptance:
- We can change one phase at a time and prove what moved.
- The audit doc stays synchronized with the real branch state.

## Phase 1. Refactor the Live Cache Substrate

Goal:
- Stop treating every live cache as “just give me float `state` arrays”.
- Create one cache interface that can support:
  - float KV
  - quantized KV
  - persistent TurboQuant KV
  - latent MLA cache
  - later, paged-backed KV

Primary files:
- [KVCache.swift](/Users/eric/osa-jang/Packages/VMLXRuntime/Sources/VMLXRuntime/Models/Utilities/KVCache.swift)
- [TurboQuantKVCache.swift](/Users/eric/osa-jang/Packages/VMLXRuntime/Sources/VMLXRuntime/Quantization/TurboQuantKVCache.swift)
- [ModelContainer.swift](/Users/eric/osa-jang/Packages/VMLXRuntime/Sources/VMLXRuntime/Core/ModelContainer.swift)
- [VMLXRuntimeActor.swift](/Users/eric/osa-jang/Packages/VMLXRuntime/Sources/VMLXRuntime/Integration/VMLXRuntimeActor.swift)
- [LayerCache.swift](/Users/eric/osa-jang/Packages/VMLXRuntime/Sources/VMLXRuntime/Core/LayerCache.swift)
- [HybridCache.swift](/Users/eric/osa-jang/Packages/VMLXRuntime/Sources/VMLXRuntime/Core/HybridCache.swift)

Exact work:
- Extend the live-cache abstraction so store/fetch logic does not have to force everything through decoded float `state`.
- Add explicit store/export and restore/import hooks for cache backends that are not plain float KV.
- Add fast byte-accounting per live cache backend so stats stop depending on fully decoded `state`.
- Keep `VMLXMambaCache` and hybrid restore semantics intact while this abstraction changes.

Acceptance:
- The actor can restore/store cache backends without assuming everything is `VMLXBaseKVCache + float state`.
- This phase must not change MLX runtime behavior.

## Phase 2. Make TurboQuant a Real Persistent Live Cache

Goal:
- After prefill, eligible attention layers stay in `TurboQuantKVCache` rather than being encoded then immediately downgraded to float.

Status:
- Landed on the active VMLX path.
- Remaining explicit gap: `TQDiskStore` still is not the active L2 backend.

Primary files:
- [TurboQuantKVCache.swift](/Users/eric/osa-jang/Packages/VMLXRuntime/Sources/VMLXRuntime/Quantization/TurboQuantKVCache.swift)
- [TurboQuantEncoder.swift](/Users/eric/osa-jang/Packages/VMLXRuntime/Sources/VMLXRuntime/Quantization/TurboQuantEncoder.swift)
- [ModelContainer.swift](/Users/eric/osa-jang/Packages/VMLXRuntime/Sources/VMLXRuntime/Core/ModelContainer.swift)
- [VMLXRuntimeActor.swift](/Users/eric/osa-jang/Packages/VMLXRuntime/Sources/VMLXRuntime/Integration/VMLXRuntimeActor.swift)
- [DiskCache.swift](/Users/eric/osa-jang/Packages/VMLXRuntime/Sources/VMLXRuntime/Cache/DiskCache.swift)
- [CacheCoordinator.swift](/Users/eric/osa-jang/Packages/VMLXRuntime/Sources/VMLXRuntime/Cache/CacheCoordinator.swift)

Exact work:
- Make `TurboQuantKVCache` conform to the live cache protocol instead of being a dead helper.
- Decide and enforce interaction with `VMLXQuantizedKVCache`:
  - either mutual exclusion, or
  - explicit ordering and layer ownership
- Replace the actor’s decode-once manual pass with cache-native lifecycle:
  - fill during prefill
  - compress at prefill boundary
  - append decode tokens into the live TQ window
- Restore `.compressedAttention` directly into live TQ caches when possible.
- Keep the KV-only rule enforced from `TurboQuantConfig` for hybrid JANG models.

Cross-runtime gate:
- MLX still routes and generates normally.
- MLX reasoning/tool parsing behavior does not change.

Acceptance:
- JANG hybrid attention layers stay compressed after prefill on the live VMLX path.
- Cache-hit turns do not downgrade the live path back to float just because the prefix was restored.
- Stats can report compressed live-cache size without decoding the cache first.

## Phase 3. Turn Paged Cache into a Real Live Runtime Allocator

Goal:
- Replace the old “completed-cache block store only” behavior with live request-scoped paged block commits on the VMLX hot path.

Status:
- Landed as live request-scoped block commits during prefill plus final block rewriting at store time.
- Remaining explicit gap: the attention kernel still consumes contiguous live K/V tensors, not a custom paged-attention kernel.

Primary files:
- [PagedCacheManager.swift](/Users/eric/osa-jang/Packages/VMLXRuntime/Sources/VMLXRuntime/Cache/PagedCacheManager.swift)
- [CacheBlock.swift](/Users/eric/osa-jang/Packages/VMLXRuntime/Sources/VMLXRuntime/Cache/CacheBlock.swift)
- [CacheCoordinator.swift](/Users/eric/osa-jang/Packages/VMLXRuntime/Sources/VMLXRuntime/Cache/CacheCoordinator.swift)
- [Scheduler.swift](/Users/eric/osa-jang/Packages/VMLXRuntime/Sources/VMLXRuntime/Scheduler/Scheduler.swift)
- [Types.swift](/Users/eric/osa-jang/Packages/VMLXRuntime/Sources/VMLXRuntime/Core/Types.swift)
- [VMLXRuntimeActor.swift](/Users/eric/osa-jang/Packages/VMLXRuntime/Sources/VMLXRuntime/Integration/VMLXRuntimeActor.swift)

Exact work:
- Register request-scoped paged write sessions when a request starts using a paged prefix.
- Commit full paged blocks during prefill instead of waiting until the end of the request.
- Rewrite committed blocks at the final store boundary so TQ-compressed attention and final hybrid SSM state are preserved.
- Abort request-scoped paged blocks on cancellation/error without destroying unrelated reusable cached blocks.
- Keep the existing block-prefix L1/L2 reuse story intact during the transition; do not regress cache hits while converting the hot path.

Important scope rule:
- This phase is VMLX-only.
- MLX’s `KVCacheStore` remains its own design; the acceptance criterion is “not broken”, not “identical implementation”.

Acceptance:
- The active VMLX generation path commits paged blocks during prefill instead of waiting until the entire request is over.
- Successful requests rewrite those blocks to the final cache representation at store time.
- Request cleanup can abort in-flight paged blocks without clearing unrelated cached entries.

## Phase 4. Qwen 3.5 35B JANG MoE Prefill Optimization

Goal:
- Fix the real 35B JANG pain point: quantized MoE prefill cost before first token.

Primary files:
- [Qwen35Model.swift](/Users/eric/osa-jang/Packages/VMLXRuntime/Sources/VMLXRuntime/Models/Qwen35Model.swift)
- [SwitchLayers.swift](/Users/eric/osa-jang/Packages/VMLXRuntime/Sources/VMLXRuntime/Models/Utilities/SwitchLayers.swift)
- [WeightLoader.swift](/Users/eric/osa-jang/Packages/VMLXRuntime/Sources/VMLXRuntime/Models/WeightLoader.swift)
- [VMLXRuntimeActor.swift](/Users/eric/osa-jang/Packages/VMLXRuntime/Sources/VMLXRuntime/Integration/VMLXRuntimeActor.swift)
- [ModelRegistry.swift](/Users/eric/osa-jang/Packages/VMLXRuntime/Sources/VMLXRuntime/Models/ModelRegistry.swift)

Current bottleneck:
- the hot stack still points at `Qwen35SparseMoeBlock -> VMLXSwitchGLU -> VMLXQuantizedSwitchLinear` during prefill

Exact work:
- Profile and reduce the cost of quantized expert routing, not just prefill chunk size.
- Improve the grouped/sorted expert path so large expert counts stop thrashing tiny gathers.
- Re-check bfloat16 conversion, expert-group sizing, and the `sortedIndices` route on the quantized switch path.
- Keep hybrid SSM boundary snapshotting intact while the MoE path changes.

Acceptance:
- `Qwen3.5-35B-A3B-JANG_4K` no longer looks like it is “loading forever” before the first token on the same hardware/config where it currently stalls.
- Profiling stops being dominated by the quantized expert path for normal prefill.

## Phase 5. Rework Mistral 4 onto Latent MLA Cache

Goal:
- Stop using full KV cache objects for a model whose main structural advantage is latent MLA state.

Primary files:
- [Mistral4Model.swift](/Users/eric/osa-jang/Packages/VMLXRuntime/Sources/VMLXRuntime/Models/Mistral4Model.swift)
- [MLAAttention.swift](/Users/eric/osa-jang/Packages/VMLXRuntime/Sources/VMLXRuntime/Models/MLAAttention.swift)
- [KVCache.swift](/Users/eric/osa-jang/Packages/VMLXRuntime/Sources/VMLXRuntime/Models/Utilities/KVCache.swift)
- [ModelContainer.swift](/Users/eric/osa-jang/Packages/VMLXRuntime/Sources/VMLXRuntime/Core/ModelContainer.swift)
- [TurboQuantConfig.swift](/Users/eric/osa-jang/Packages/VMLXRuntime/Sources/VMLXRuntime/Quantization/TurboQuantConfig.swift)
- [VMLXRuntimeActor.swift](/Users/eric/osa-jang/Packages/VMLXRuntime/Sources/VMLXRuntime/Integration/VMLXRuntimeActor.swift)

Exact work:
- Add a live latent MLA cache backend that fits the same refactored cache substrate.
- Port Mistral 4 attention to store latent `c_kv` plus rope state instead of full decompressed K/V.
- Update cache store/fetch/export logic to understand latent MLA entries.
- Re-evaluate whether TurboQuant should apply to Mistral 4 at all once the latent cache exists.

Acceptance:
- Mistral 4 cache bytes scale with `kv_lora_rank` latent state rather than full `numHeads * headDim` KV.
- Token/s and cache footprint improve for the real Mistral 4 JANG path.

## Phase 6. Cross-Runtime Routing and UI Truthfulness

Goal:
- After the runtime work lands, make sure the app surfaces, routing, and settings still tell the truth for both MLX and VMLX.

Primary files:
- [VMLXServiceBridge.swift](/Users/eric/osa-jang/Packages/OsaurusCore/Services/Inference/VMLXServiceBridge.swift)
- [MLXService.swift](/Users/eric/osa-jang/Packages/OsaurusCore/Services/Inference/MLXService.swift)
- [ChatEngine.swift](/Users/eric/osa-jang/Packages/OsaurusCore/Services/Chat/ChatEngine.swift)
- [ConfigurationView.swift](/Users/eric/osa-jang/Packages/OsaurusCore/Views/Settings/ConfigurationView.swift)
- [ModelRuntime.swift](/Users/eric/osa-jang/Packages/OsaurusCore/Services/ModelRuntime.swift)
- [MLXGenerationEngine.swift](/Users/eric/osa-jang/Packages/OsaurusCore/Services/ModelRuntime/MLXGenerationEngine.swift)

Exact work:
- Make runtime selection explicit where possible instead of “VMLX first, then fail over”.
- Keep MLX settings and VMLX settings separated where they are not the same thing.
- Extend cache stats so the UI can show meaningful size data for both runtime families where possible.

Acceptance:
- Both MLX and JANG/VMLX models still load, unload, generate, and expose truthful settings after the refactors.

## Immediate Next Step

The first actual code phase should be:
- Phase 1: refactor the live cache substrate

Reason:
- Persistent TurboQuant and latent MLA both need it.
- A real live paged allocator also depends on it.
- Doing Qwen or Mistral performance work before this would lock us into temporary cache plumbing.
