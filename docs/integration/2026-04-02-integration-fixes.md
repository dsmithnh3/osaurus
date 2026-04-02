# Integration Fixes — 2026-04-02

Fixes applied after rebasing feature/vmlx onto latest origin/main (54 team commits).
The team shipped major UI, plugin, Bonjour, and GPU changes that required compatibility work with VMLXRuntime.

---

## Fix 1: GenerationStats not rendering in AppKit chat view

**Problem:** Team replaced SwiftUI chat scroll with NSTableView (NativeMessageCellView). Our `.inferenceStats` content blocks fell through to `configureAsUnsupported()` — zero-height invisible placeholder.

**Files changed:**
- `NativeMessageCellView.swift` — Added `configureAsInferenceStats()` handler, `nativeStatsView` property, cleanup in `removeAllContentViews()`, `.inferenceStats` case in `ContentBlockKindTag` enum and `kindTag` computed property, height estimation (28pt)
- `NativeBlockViews.swift` — Added `NativeInferenceStatsView` class (monospaced label showing `stats.summary`)

**Verified:** Stats now render as a compact bar below assistant messages.

---

## Fix 2: GPU synchronization before Memory.clearCache in VMLXRuntimeActor

**Problem:** On model unload, `VMLXRuntimeActor` called `Memory.clearCache()` without `Stream.gpu.synchronize()`. MLXService's background prefix-cache tasks could still be referencing GPU buffers. Race condition leading to potential crashes.

**Files changed:**
- `VMLXRuntimeActor.swift` — Added `Stream.gpu.synchronize()` before `Memory.clearCache()` in the unload path (line ~410)

**Note:** Other `Memory.clearCache()` call sites are safe — they're all preceded by MLX array materialization which forces GPU work to complete.

---

## Fix 3: VMLX handles() hardcoded remote provider list

**Problem:** `VMLXService.handles()` had a hardcoded list of remote provider prefixes ("openai/", "anthropic/", etc.). Any new remote provider or Bonjour-discovered agent not in the list would be incorrectly routed to VMLX and fail.

**Files changed:**
- `VMLXService.swift` — Replaced hardcoded list with structural detection:
  - Absolute paths (`/Users/...`) and HuggingFace repo IDs (`Org/Model-Name`) accepted as local
  - Any other `prefix/model` pattern rejected as remote
  - Bare names without `/` accepted as local

**Covers:** All current and future remote providers, Bonjour agents, custom endpoints.

---

## Fix 4: ChatEngine routing — dead param + inconsistent priorities

**Problem:** Two issues:
1. `ChatEngine.init(remoteServices:)` param was accepted but never stored — callers thought they were configuring remote services but the value was silently discarded
2. `streamChat()` tried local services first, then remote. `completeChat()` used `ModelServiceRouter.resolve()` which tries remote first for explicit model requests. Same request could route differently depending on streaming vs non-streaming.

**Files changed:**
- `ChatEngine.swift` — Removed dead `remoteServices` param. Rewrote `streamChat()` to use `ModelServiceRouter.resolve()` with ordered fallback (routed service first, then remaining local, then remaining remote)
- `ChatView.swift` — Removed `remoteServices:` argument from ChatEngine constructor call

**Result:** Both endpoints use identical routing logic. Remote providers correctly get priority for explicit model names like "openai/gpt-4".

---

## Fix 5: Dead SwiftUI views causing build failure

**Problem:** Team removed `GroupedToolCallsContainerView`, `ArtifactCardView`, `TypingIndicator`, `PulsingDot` views when moving to AppKit. Our `ContentBlockView.swift` (SwiftUI fallback, never rendered) still referenced them causing build failure.

**Files changed:**
- Deleted `ContentBlockView.swift` — Dead code, completely replaced by `NativeMessageCellView`

**Note:** `ThinkingBlockView.swift` is also dead code (replaced by `NativeThinkingView`) but compiles fine. Left in place.

---

## Fix 6: README updated for beta

**Files changed:**
- `README.md` — Combined main branch product description with VMLXRuntime beta information. Includes architecture diagram with VMLX Runtime, known issues section, beta docs links.

---

## Summary

| Fix | Area | Severity |
|-----|------|----------|
| GenerationStats native renderer | UI | High — stats invisible without this |
| GPU sync on unload | Engine | High — potential crash |
| VMLX handles() remote detection | Routing | High — wrong routing for new providers |
| ChatEngine routing unification | Routing | Medium — inconsistent behavior |
| Dead SwiftUI view cleanup | Build | Blocker — build wouldn't compile |
| README for beta | Docs | Housekeeping |
