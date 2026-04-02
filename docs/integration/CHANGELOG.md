# VMLXRuntime Integration Changelog

## feature/vmlx — 77 commits ahead of main

### Core Runtime (VMLXRuntime package)

**Native Model Implementations**
- StandardModel: Llama, Qwen2.5, Gemma, Phi transformer path
- Qwen35Model: hybrid SSM/attention with layer-type switching
- NemotronHModel: Mamba2 SSM + MoE + latent attention
- Mistral4Model: sliding window + MoE architecture
- GPTOSSModel: GPT-variant support
- MoELayer: router + batched experts + shared expert
- HybridTransformerModel: generic SSM/attention interleave

**Cache System**
- CacheCoordinator: paged → memory → prefix → disk fetch hierarchy
- PagedCacheManager: block-level COW-safe KV storage
- PrefixCache: trie-based token prefix matching
- DiskCache: SQLite-indexed persistent tensor storage
- HybridCache: enforces attention-truncatable / SSM-non-truncatable rules
- SSMReDeriver: reconstructs SSM state from partial cache hits
- TurboQuant encode/decode for KV compression (random projection + codebook)

**Model Loading**
- ModelDetector: config.json-based model_type detection (no name matching)
- ModelLoader: detect → config → model → tokenizer pipeline
- WeightLoader: mixed-precision quantization inference from weight shapes
- JANG format support for custom quantized models
- ModelContainer: holds model + tokenizer + cache state

**Parsers**
- 13 tool-call parsers (Qwen, Llama, Mistral, DeepSeek, Functionary, Granite, etc.)
- Reasoning parsers for thinking-block extraction
- Auto-detection of parser type from model config

**Infrastructure**
- Scheduler + SchedulerConfig (single-generation active, primitives for batching)
- SSD parallel scan for Mamba2 prefill (replaces O(T) sequential loop)
- GatedDelta with 4 kernel variants (scalar/vec x masked/unmasked)

### App Integration (OsaurusCore)

**Service Layer**
- VMLXServiceBridge: routes ChatEngine → VMLXService → VMLXRuntimeActor
- Fallback to MLXService (mlx-swift-lm) when VMLXRuntime declines a model
- UserModelDirectories: discover user-downloaded models on disk

**Inference Stats**
- EngineStats: ttft, prompt tok/s, generation tok/s, cache detail, cache bytes
- Stats flow from actor → stream sentinel → StreamingDeltaProcessor → UI
- OpenAI API response includes `x_engine` and `cached_tokens` fields

**UI Improvements**
- Streaming markdown throttling: skip re-parse for >3KB during streaming
- ThinkingBlockView: tail-only rendering during stream, full render on complete
- StreamingDeltaProcessor: adaptive flush intervals (0-200ms based on output size)
- GenerationStats display in chat UI

**Chat Engine**
- ChatEngine fallback generation captures stats from sentinel events
- GPU task synchronization: cancel → wait for idle → start new generation
- SSM re-derivation cancelled before forward passes to prevent concurrent GPU ops

### Audit & Fixes (Recent)

- Deep cache audit: 8 bugs fixed in hybrid SSM, TurboQuant, paged cache
- TQ cache export: always emit float, never lossy compressed
- Paged cache COW safety, nil layer reconstruction, refCount leak
- NemotronH: SSM scan, MoE routing, latent path, projection dimensions
- Mistral4: config decoding, inference alignment
- Hybrid models: single-phase prefill + SSD state projection
- Weight loader: per-layer quantization inference for mixed-precision JANG
