<p align="center">
<img width="865" height="677" alt="Screenshot 2026-03-19 at 3 42 04 PM" src="https://github.com/user-attachments/assets/c16ee8bb-7f31-4659-9c2c-6eaaf8441c26" />
</p>

<h1 align="center">Osaurus</h1>

<p align="center">
  <strong>Own your AI.</strong><br>
  Agents, memory, tools, and identity that live on your Mac. Built purely in Swift. Fully offline. Open source.
</p>

<p align="center">
  <img src="https://img.shields.io/badge/Branch-feature%2Fvmlx-blue" alt="Branch">
  <img src="https://img.shields.io/badge/Status-Team%20Beta-orange" alt="Status">
  <img src="https://img.shields.io/badge/Platform-macOS%20(Apple%20Silicon)-black?logo=apple" alt="Platform">
  <img src="https://img.shields.io/badge/Swift-6.2-orange?logo=swift" alt="Swift">
  <img src="https://img.shields.io/badge/MLX-Metal%20GPU-blue" alt="MLX">
</p>

<p align="center">
  <img src="https://img.shields.io/badge/OpenAI%20API-compatible-0A7CFF" alt="OpenAI API">
  <img src="https://img.shields.io/badge/Anthropic%20API-compatible-0A7CFF" alt="Anthropic API">
  <img src="https://img.shields.io/badge/Ollama%20API-compatible-0A7CFF" alt="Ollama API">
  <img src="https://img.shields.io/badge/MCP-server-0A7CFF" alt="MCP Server">
  <img src="https://img.shields.io/badge/Apple%20Foundation%20Models-supported-0A7CFF" alt="Foundation Models">
</p>

---

> **Beta branch `feature/vmlx`** — This build integrates VMLXRuntime, a native Swift inference engine replacing `mlx-swift-lm`. All existing Osaurus features (agents, memory, tools, plugins, sandbox, MCP, remote providers, Bonjour) are intact. See [What's New in This Beta](#whats-new-in-this-beta) below.

---

## Inference is all you need. Everything else can be owned by you.

Osaurus is the AI harness for macOS. It sits between you and any model -- local or cloud -- and provides the continuity that makes AI personal: agents that remember, execute autonomously, run real code, and stay reachable from anywhere. The models are interchangeable. The harness is what compounds.

Works fully offline with local models. Connect to any cloud provider when you want more power. Nothing leaves your Mac unless you choose.

Native Swift on Apple Silicon. No Electron. No compromises. MIT licensed.

## What's New in This Beta

### VMLXRuntime — Native Inference Engine

This build replaces the `mlx-swift-lm` inference backend with **VMLXRuntime**, a ground-up Swift engine built on raw `mlx-swift`. The app tries VMLXRuntime first and falls back to `mlx-swift-lm` automatically for unsupported architectures.

**Why it matters:**
- Native support for hybrid SSM/transformer models (Qwen 3.5, NemotronH, Mistral Small 4)
- JANG mixed-precision quantization format (3/4/5/8 bit per layer)
- TurboQuant KV cache compression for longer context in limited VRAM
- Multi-layer cache hierarchy: paged + prefix + memory + disk with SSM-safe rules
- Full streaming tool-call and reasoning parsers (13 model families)
- Per-model generation stats: TTFT, prefill tok/s, decode tok/s, cache hit info

**Model support:**

| Family | Status | Notes |
|--------|--------|-------|
| Standard transformers (Llama, Qwen 2.5, Gemma, Phi) | Verified | Primary path, well-tested |
| Qwen 3.5 hybrid SSM | Verified | Hybrid cache split/restore active |
| NemotronH (Mamba2 + MoE) | Beta | Implemented, under validation |
| Mistral Small 4 (MLA + MoE) | Beta | Implemented, under validation |
| GPT-OSS | Beta | Channel protocol + reasoning |

### Bonjour Agent Discovery + Remote Providers

Discover and connect to other Osaurus instances on the local network. Remote providers (OpenAI, Anthropic, custom endpoints) route correctly alongside local VMLX inference -- the engine properly distinguishes remote model names from local ones.

### AppKit Chat Rendering

Chat view rebuilt with pure AppKit (NSTableView) for smooth scrolling and efficient streaming:
- Native markdown rendering with streaming throttle (no UI freeze on long outputs)
- Native thinking block renderer with expand/collapse
- Native inference stats bar showing generation performance
- Dynamic cell height calculation

### Cache System

```
CacheCoordinator
  Paged cache (COW-safe block storage)
  Memory cache (in-memory LRU)
  Prefix cache (token trie)
  Disk cache (SQLite + safetensors)
  SSM companion cache (hybrid model state)
```

Hybrid models get special treatment: attention KV is positional and truncatable, SSM state is path-dependent and never truncated. TurboQuant compresses KV in-flight but exports float for persistence to prevent quality degradation.

---

## Build from Source

```bash
git clone https://github.com/osaurus-ai/osaurus.git
cd osaurus
git checkout feature/vmlx
open osaurus.xcworkspace
```

Build the `osaurus` scheme in **Release** configuration (Debug is significantly slower for inference). Requires Xcode 16+ and macOS 15.5+.

> Requires macOS 15.5+ and Apple Silicon.

## Agents

Agents are the core of Osaurus. Each one gets its own prompts, memory, and visual theme -- a research assistant, a coding partner, a file organizer, whatever you need. Tools and skills are automatically selected via RAG search based on the task at hand -- no manual configuration needed.

### Work Mode

Give an agent an objective. It breaks the work into trackable issues, executes step by step -- parallel tasks, file operations, background processing.

### Sandbox

Agents execute code in an isolated Linux VM powered by Apple's [Containerization](https://developer.apple.com/documentation/containerization) framework. Full dev environment -- shell, Python, Node.js, compilers, package managers -- with zero risk to your Mac.

> Requires macOS 26+ (Tahoe). See the [Sandbox Guide](docs/SANDBOX.md).

### Memory

4-layer system: user profile, working memory, conversation summaries, and a knowledge graph. Extracts facts, detects contradictions, recalls relevant context -- all automatically.

### Identity

Every participant gets a secp256k1 cryptographic address. Authority flows from your master key (iCloud Keychain) down to each agent in a verifiable chain of trust. See [Identity docs](docs/IDENTITY.md).

## Models

The harness is model-agnostic. Swap freely -- your agents, memory, and tools stay intact.

### Local (VMLXRuntime)

Run models on Apple Silicon with optimized MLX inference via VMLXRuntime. Standard HuggingFace models and JANG quantized models supported. Models stored at `~/MLXModels` (or custom directories via Settings).

### Apple Foundation Models

On macOS 26+, use Apple's on-device model as a first-class provider. Pass `model: "foundation"` in API requests. Zero inference cost, fully private.

### Cloud & Remote

Connect to OpenAI, Anthropic, Gemini, xAI/Grok, Venice AI, OpenRouter, Ollama, LM Studio, or any custom endpoint. Discover other Osaurus instances on your network via Bonjour. Context and memory persist across all providers.

## MCP

Osaurus is a full MCP (Model Context Protocol) server. Give Cursor, Claude Desktop, or any MCP client access to your tools:

```json
{
  "mcpServers": {
    "osaurus": {
      "command": "osaurus",
      "args": ["mcp"]
    }
  }
}
```

Also an MCP client -- aggregate tools from remote MCP servers into Osaurus. See the [Remote MCP Providers Guide](docs/REMOTE_MCP_PROVIDERS.md).

## Tools & Plugins

20+ native plugins: Mail, Calendar, Vision, macOS Use, XLSX, PPTX, Browser, Music, Git, Filesystem, Search, Fetch, and more. Plugins support v1 (tools only) and v2 (full host API) ABIs. See the [Plugin Authoring Guide](docs/PLUGIN_AUTHORING.md).

## Compatible APIs

Drop-in endpoints for existing tools:

| API       | Endpoint                                      |
| --------- | --------------------------------------------- |
| OpenAI    | `http://127.0.0.1:1337/v1/chat/completions`   |
| Anthropic | `http://127.0.0.1:1337/anthropic/v1/messages` |
| Ollama    | `http://127.0.0.1:1337/api/chat`              |

All prefixes supported (`/v1`, `/api`, `/v1/api`). Full function calling with streaming tool call deltas. See [OpenAI API Guide](docs/OpenAI_API_GUIDE.md).

## Architecture

```
┌─────────────────────────────────────────────────────┐
│                   The Harness                       │
├──────────┬──────────┬───────────┬───────────────────┤
│ Agents   │ Memory   │ Work Mode │ Automation        │
├──────────┴──────────┴───────────┴───────────────────┤
│              MCP Server + Client                    │
├──────────┬──────────┬───────────┬───────────────────┤
│ VMLX     │ MLX-LM   │ Cloud     │ Foundation        │
│ Runtime  │ Fallback │ Providers │ Models            │
├──────────┴──────────┴───────────┴───────────────────┤
│      Plugin System (v1 / v2 ABI) · Native Plugins   │
├──────────┬──────────┬───────────┬───────────────────┤
│ Identity │ Relay    │ Tools     │ Skills · Methods  │
├──────────┴──────────┴───────────┴───────────────────┤
│  Sandbox VM (Alpine · Apple Containerization)       │
│  vsock bridge · VirtioFS · per-agent isolation      │
└─────────────────────────────────────────────────────┘
```

## Known Issues (Beta)

See [docs/integration/KNOWN-ISSUES.md](docs/integration/KNOWN-ISSUES.md) for the full list.

- Metal custom kernels temporarily disabled (ops-based fallback works, may be slower)
- `mlx-swift` package identity warning (two sources — builds fine, future SwiftPM concern)
- NemotronH and Mistral Small 4 still under broader validation
- Vision encoder inference and MiniMax tokenizer pending
- Continuous batching not active (one generation at a time)

## Documentation

- [Beta Testing Guide](docs/integration/BETA-TESTING.md)
- [Integration Architecture](docs/integration/ARCHITECTURE.md)
- [Integration Changelog](docs/integration/CHANGELOG.md)
- [Known Issues](docs/integration/KNOWN-ISSUES.md)
- [Feature Comparison (VMLXRuntime vs Python)](docs/FEATURE_COMPARISON.md)

## Community

- [Discord](https://discord.com/invite/dinoki) -- chat, feedback, show-and-tell
- [Twitter](https://x.com/OsaurusAI) -- updates and demos
- [Plugin Registry](https://github.com/osaurus-ai/osaurus-tools) -- browse and contribute tools

## License

[MIT](LICENSE)

---

<p align="center">
  Osaurus, Inc. · <a href="https://osaurus.ai">osaurus.ai</a>
</p>
