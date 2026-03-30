<h1 align="center">Jangosaurus</h1>

<p align="center">
  <strong>VMLXRuntime: Native Swift Inference Engine for Osaurus</strong><br>
  A complete from-scratch replacement of Osaurus's MLX inference backend with production-grade caching, TurboQuant 3-bit KV compression, continuous batching, hybrid SSM support, and native JANG model loading.
</p>

<p align="center">
  <img src="https://img.shields.io/badge/Platform-macOS%20(Apple%20Silicon)-black?logo=apple" alt="Platform">
  <img src="https://img.shields.io/badge/Swift-6.2-orange?logo=swift" alt="Swift">
  <img src="https://img.shields.io/badge/MLX-Metal%20GPU-blue" alt="MLX">
  <img src="https://img.shields.io/badge/Features-153%2F169%20(91%25)-brightgreen" alt="Features">
  <img src="https://img.shields.io/badge/License-MIT-green" alt="License">
</p>

---

## What Is This

**Jangosaurus** is a fork of [Osaurus](https://github.com/osaurus-ai/osaurus) with the entire MLX inference backend replaced by **VMLXRuntime** -- a native Swift inference engine built from scratch. It ports all core features from the [VMLX Python engine](https://github.com/jjang-ai/vmlx) to native Swift, eliminating the Python runtime overhead while adding new capabilities.

### Why Replace the Backend

Osaurus used `mlx-swift-lm` for local inference -- a basic wrapper with simple KV caching, no batching, no TurboQuant, and no hybrid SSM support. VMLXRuntime replaces it entirely with:

| Feature | Old (mlx-swift-lm) | New (VMLXRuntime) |
|---------|--------------------|--------------------|
| KV Cache | Basic 2-tier | 5-layer stack (paged + prefix + memory + disk + SSM) |
| Compression | None | TurboQuant 3-bit (10x KV memory savings) |
| Batching | None | Continuous batching (32+ concurrent requests) |
| Hybrid SSM | None | Full Mamba + attention interleaving |
| Thinking Models | None | Mid-prefill SSM checkpointing + async re-derive |
| Tool Calling | Basic | 14 model-specific parsers (auto-detected) |
| Reasoning | None | 3 parsers (Qwen3, DeepSeek-R1, GPT-OSS) |
| JANG Models | None | Native loading (all 7 profiles, v1 + v2) |
| Model Arch | Transformer only | Transformer + Mamba + MoE + MLA + Hybrid |
| Power Mgmt | None | Sleep/wake/JIT with auto-resume |
| Multi-Model | Single | Gateway routing with aliases |
| Process Overhead | ~200MB Python | 0 (compiled binary) |
| Startup | 3-8 seconds | <100ms |

---

## Architecture

```
Osaurus App (SwiftUI)
  |
  v
VMLXServiceBridge (ToolCapableService)     -- drop-in for MLXService
  |
  v
VMLXRuntimeActor (singleton)               -- replaces ModelRuntime
  |
  +-- ModelContainer (weights + tokenizer)
  +-- Scheduler (continuous batching)
  +-- CacheCoordinator (5-layer stack)
  +-- GenerationEngine (prefill + decode)
  +-- SSMReDeriver (async recovery)
  |
  v
mlx-swift (tensor ops) --> MLX C++ --> Metal GPU
```

All Osaurus subsystems (chat UI, sandbox agents, plugins, work mode, HTTP API, memory) route through `ChatEngine` -> `VMLXServiceBridge` -> `VMLXRuntime` automatically.

---

## Package Structure

```
Packages/VMLXRuntime/           72 source files, 15,379 lines
  Sources/VMLXRuntime/
    Core/          8 files   -- Types, HybridCache, ModelLoader, ModelDetector, ModelConfig
    Cache/        13 files   -- 5-layer stack, TQ disk store, block disk, SSM companion, coordinator
    Quantization/  6 files   -- TurboQuant config/cache/encoder, JANG loader (7 profiles)
    Models/        5 files   -- Transformer, Mamba, MoE, MLA, Hybrid
    Generation/    5 files   -- Sampler, stop detector, stream accumulator, PLD, engine
    Scheduler/     5 files   -- Config, queue, batching, batch builder, MLLM scheduler
    Vision/        3 files   -- CoreImage processor, embedding cache, 7 VLM architectures
    Parsers/      19 files   -- 14 tool parsers + 3 reasoning parsers
    Integration/   3 files   -- VMLXRuntimeActor, VMLXService, ChatMessageMapper
    API/           4 files   -- Anthropic, Ollama, Completions, Embeddings adapters
  Tests/                      42 test files, 6,447 lines
```

---

## Key Features

### 5-Layer Cache Stack

```
Request arrives
  |
  v
L1: Paged Cache (block-level, COW, SHA-256 hash chain)
  |-- miss -->
L1: Memory Cache (RAM-aware LRU, pressure adaptation)
  |-- miss -->
L1: Prefix Cache (token-trie matching)
  |-- miss -->
L2: Disk Cache (SQLite + safetensors on SSD)
  |-- miss -->
Full prefill required

For hybrid models:
  +-- SSM Companion Cache (checkpoint at stable boundary)
  +-- SSM ReDeriver (async background recovery)
```

### TurboQuant 3-bit KV Compression

- Random projection codebook quantization via MLX
- Per-layer bit widths (3-bit default, 4-bit critical layers)
- Hybrid-aware: automatically skips SSM layers
- MLA-aware: custom key/value dimensions for DeepSeek/Mistral
- 26x compressed TQ-native disk serialization
- Two-phase lifecycle: fill (zero overhead) -> compress (after prefill)

### Model Architecture Support

| Architecture | Models | Implementation |
|-------------|--------|----------------|
| **Transformer** (GQA) | Llama 3/4, Qwen3, Gemma | TransformerModel.swift |
| **Mamba SSM** | Qwen3.5, Jamba | MambaLayer.swift |
| **MoE** (256 experts) | Qwen3.5-122B, MiniMax M2.5, Nemotron | MoELayer.swift |
| **MLA** (latent attention) | DeepSeek V2/V3/R1, Mistral 4 | MLAAttention.swift |
| **Hybrid** (SSM + attention) | Nemotron-H, Qwen3.5-A3B | HybridTransformerModel.swift |

### JANG Model Support

Native loading of all JANG quantization profiles from [JANGQ-AI](https://huggingface.co/JANGQ-AI):

| Profile | Target Bits | Description |
|---------|------------|-------------|
| JANG_1L | 2.5 | Extreme compression (128 block) |
| JANG_2L | 2.0 | Heavy compression |
| JANG_2S | 2.5 | Balanced |
| JANG_3M | varies | Medium-3 |
| JANG_4K | 2.5 | Higher quality |
| JANG_4M | 4.0 | Medium quality |
| JANG_4S | 2.5 | Sparse/selective |

Auto-detects JANG models from `jang_config.json`, parses architecture (hybrid_ssm, moe, hybrid_moe_ssm, MLA), and configures TurboQuant automatically.

### Continuous Batching

- FCFS scheduling with priority support
- Configurable max sequences (auto-scaled by RAM)
- Batch builder with variable-length padding
- MLLM scheduler for vision models
- gen_prompt_len stripping for thinking models

### Tool Call Parsers (14)

Auto-detected from model name:

| Parser | Models |
|--------|--------|
| Qwen | Qwen 2.5/3/3.5, QwQ |
| Llama | Llama 3/3.1/3.2/3.3/4 |
| Mistral | Mistral, Mixtral, Codestral, Pixtral |
| DeepSeek | DeepSeek V2/V3/R1 |
| Hermes | NousResearch Hermes |
| Functionary | MeetKai Functionary |
| Granite | IBM Granite |
| GLM | GLM-4.7, ChatGLM4 |
| MiniMax | MiniMax M2.5 |
| Nemotron | NVIDIA Nemotron |
| xLAM | Salesforce xLAM |
| Moonshot | Moonshot/Kimi |
| StepFun | StepFun Step-3.5 |
| Generic | JSON fallback (any model) |

### Reasoning Parsers (3)

| Parser | Models | Format |
|--------|--------|--------|
| ThinkTag | Qwen3, DeepSeek-R1 | `<think>...</think>` |
| GPT-OSS | GLM-4.7, Harmony | `<\|channel\|>...<\|message\|>` |
| Mistral | Mistral 4 | `[THINK]...[/THINK]` |

### Power Management

```swift
await runtime.softSleep()     // Clear caches, keep model loaded
await runtime.deepSleep()     // Unload model, free GPU memory
await runtime.wake()          // Reload from saved path
await runtime.enableJITWake() // Auto-wake on next request
await runtime.enableJIT()     // Metal kernel fusion (20-50% speedup)
```

### Multi-Model Gateway

```swift
// Load multiple models
try await runtime.loadModel(from: qwen4bPath, alias: "fast")
try await runtime.loadModel(from: qwen122bPath, alias: "smart")

// Route by name
let response = try await runtime.generateStream(request)  // Uses active model
runtime.resolveModel("smart")  // Switch to 122B
```

### API Compatibility

| Format | Adapter | Status |
|--------|---------|--------|
| OpenAI Chat | Osaurus native | Built-in |
| OpenAI Completions | CompletionsAdapter | Done |
| Anthropic Messages | AnthropicAdapter | Done |
| Ollama Chat/Generate | OllamaAdapter | Done |
| Embeddings | EmbeddingsService | Done |

### Vision-Language

- CoreImage preprocessing (resize, normalize, CLIP defaults)
- AVFoundation video frame extraction
- Vision embedding cache (SHA-256 keyed LRU)
- 7 VLM architectures: Qwen-VL, Pixtral, InternVL, LLaVA, Gemma 3n, Phi-3-Vision

---

## Osaurus Integration

VMLXRuntime is wired into Osaurus via `VMLXServiceBridge`:

```swift
// ChatEngine.swift — VMLXServiceBridge is in the default services array
init(services: [ModelService] = [FoundationModelService(), VMLXServiceBridge(), MLXService()])
```

All subsystems automatically route through VMLXRuntime:
- **Chat UI** -- direct through ChatEngine
- **Sandbox agents** -- via HostAPIBridgeServer -> ChatEngine
- **Plugins** -- via PluginHostAPI -> ChatEngine
- **Work mode** -- via WorkExecutionEngine -> ChatEngine
- **HTTP API** -- via HTTPHandler -> ChatEngine
- **Memory** -- via ModelServiceRouter

OsaurusCore compiles cleanly with VMLXRuntime: **3290/3290 files, zero errors.**

---

## Innovation: Mid-Prefill SSM Checkpointing

For hybrid SSM models with thinking/reasoning (Qwen3.5-A3B, Nemotron-H), the Python VMLX engine **skips SSM caching entirely** for thinking models because post-generation SSM state is contaminated by gen_prompt tokens.

VMLXRuntime introduces **mid-prefill SSM checkpointing**: checkpoint SSM state at the stable boundary (before gen_prompt_len) DURING prefill, not after generation. This means:

- First turn: full prefill + SSM checkpoint stored
- Subsequent turns: instant SSM + KV cache hit (only gen_prompt tokens re-processed)
- Result: **O(gen_prompt_len) per turn** instead of O(full_context) per turn

When SSM checkpoints are evicted, the **SSMReDeriver** actor runs an async background forward pass to recover the state without blocking the current request.

---

## Feature Completion

| Category | Done | Total | % |
|----------|------|-------|---|
| Model Loading | 17 | 17 | 100% |
| Transformer/SSM/MoE | 17 | 17 | 100% |
| Cache Stack | 16 | 17 | 94% |
| TurboQuant | 14 | 14 | 100% |
| Scheduler | 13 | 14 | 93% |
| Generation | 16 | 16 | 100% |
| Power Management | 6 | 6 | 100% |
| Multi-Model | 6 | 6 | 100% |
| Vision | 10 | 10 | 100% |
| Tool Parsers | 16 | 16 | 100% |
| Reasoning Parsers | 5 | 5 | 100% |
| API Compatibility | 5 | 12 | 42% |
| Integration | 12 | 12 | 100% |
| **Total** | **153** | **169** | **91%** |

### Phase 2 (Deferred)
- Image generation (Flux/Z-Image models)
- Audio TTS (Kokoro) / STT (Whisper)
- Document reranking

---

## Building

```bash
# Build VMLXRuntime standalone
cd Packages/VMLXRuntime
swift build

# Build full Osaurus app (requires Xcode 16.4+, macOS 15.5+)
open osaurus.xcworkspace
# Build & Run from Xcode
```

Requires Apple Silicon Mac (M1 or later).

---

## Documentation

- **[ARCHITECTURE.md](docs/ARCHITECTURE.md)** -- Full architecture with code map (every file, every connection)
- **[FEATURE_COMPARISON.md](docs/FEATURE_COMPARISON.md)** -- Feature-by-feature comparison with VMLX Python
- **[Implementation Plan](docs/plans/2026-03-29-vmlx-runtime-integration.md)** -- Original implementation plan

---

## Credits

- **VMLXRuntime** built by Jinho Eric Jang
- **Osaurus** by [osaurus-ai](https://github.com/osaurus-ai/osaurus) (Terence Pae / tpae)
- **MLX** by Apple
- **JANG Quantization** by [JANGQ-AI](https://huggingface.co/JANGQ-AI)
