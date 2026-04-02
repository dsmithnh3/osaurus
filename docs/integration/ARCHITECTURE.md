# VMLXRuntime Integration Architecture

## System Topology

```
Osaurus App (SwiftUI)
  |
  ChatEngine
  |-- tries VMLXServiceBridge first
  |     |
  |     VMLXService
  |       |
  |       VMLXRuntimeActor (main generation hot path)
  |         |-- ModelContainer (holds loaded model + tokenizer)
  |         |-- CacheCoordinator (paged → memory → prefix → disk)
  |         |-- Scheduler (single-generation for now)
  |         |-- Native models → mlx-swift → Metal GPU
  |
  |-- falls back to MLXService (mlx-swift-lm)
        |
        MLXGenerationEngine (legacy path)
```

## Package Dependencies

```
OsaurusCore
  ├── VMLXRuntime (local package)
  │     └── mlx-swift (jjang-ai fork)
  │     └── swift-transformers (tokenizers)
  │
  ├── mlx-swift-lm (Apple reference, fallback)
  │     └── mlx-swift (ml-explore original) ← identity conflict with above
  │
  └── (other: NIO, Sparkle, MCP, etc.)
```

**Known issue:** `mlx-swift` has two sources (jjang-ai fork for VMLXRuntime, ml-explore original via mlx-swift-lm). SwiftPM resolves this today but warns it will become an error. The long-term fix is removing the `mlx-swift-lm` dependency entirely once VMLXRuntime covers all model families.

## Native Model Support

| Model Family | File | Confidence | Notes |
|-------------|------|-----------|-------|
| Standard transformers (Llama, Qwen2.5, Gemma, Phi) | `StandardModel.swift` | High | Most proven path |
| Qwen 3.5 hybrid SSM | `Qwen35Model.swift` | High | Hybrid cache split/restore active |
| NemotronH | `NemotronHModel.swift` | Medium | Implemented, correctness validation ongoing |
| Mistral Small 4 | `Mistral4Model.swift` | Medium | Implemented, correctness validation ongoing |
| GPT-OSS | `GPTOSSModel.swift` | Medium | Less tested |

## Cache Hierarchy

```
CacheCoordinator
  ├── PagedCacheManager — block-level KV storage, COW-safe
  ├── MemoryCache — fast in-memory LRU
  ├── PrefixCache — trie-based prefix matching
  ├── DiskCache — SQLite-indexed persistent cache
  └── SSMReDeriver — reconstructs SSM state from attention-only cache hits
```

Key design rules:
- Attention KV is positional → can be truncated
- SSM state is path-dependent → CANNOT be truncated
- HybridCache enforces this per-layer
- TurboQuant compresses KV in-flight but exports float for persistence (prevents quality degradation on restore)

## Generation Flow

1. User sends message
2. `ChatEngine.fallbackGenerate()` calls `VMLXServiceBridge`
3. Bridge routes to `VMLXRuntimeActor.generate()`
4. Actor: cancel any active generation → wait for GPU idle → load model if needed
5. Cache lookup: try paged → memory → prefix → disk → miss
6. Forward pass: prefill cached tokens + new tokens
7. Decode loop: sample → forward → emit token → repeat until stop
8. On finish: export cache, emit stats sentinel, close stream
9. Stats flow back through `StreamingDeltaProcessor` to UI

## Key Files

| Area | Path |
|------|------|
| App bridge | `OsaurusCore/Services/Inference/VMLXServiceBridge.swift` |
| Runtime actor | `VMLXRuntime/Integration/VMLXRuntimeActor.swift` |
| Cache coordinator | `VMLXRuntime/Cache/CacheCoordinator.swift` |
| Model loader | `VMLXRuntime/Core/ModelLoader.swift` |
| Model detector | `VMLXRuntime/Core/ModelDetector.swift` |
| TurboQuant | `VMLXRuntime/Quantization/TurboQuantEncoder.swift` |
| Weight loader | `VMLXRuntime/Models/WeightLoader.swift` |
| Streaming processor | `OsaurusCore/Utils/StreamingDeltaProcessor.swift` |
| Chat engine | `OsaurusCore/Services/Chat/ChatEngine.swift` |
