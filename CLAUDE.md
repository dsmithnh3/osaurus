# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What is Osaurus

A native macOS AI harness built in Swift for Apple Silicon. It sits between the user and any model (local MLX or cloud providers) and provides agents, memory, tools, identity, work mode, and projects. Ships as a macOS app with an embedded CLI. MIT licensed.

## Build & Run

```bash
open osaurus.xcworkspace        # Open in Xcode 16.4+, run the "osaurus" scheme
make cli                        # Build CLI only (xcodebuild, Release)
make app                        # Build app + embed CLI into Helpers/
make install-cli                # Build CLI + symlink to /usr/local/bin/osaurus
make serve                      # Build, install, and start the server (PORT=1337 EXPOSE=1)
```

Requires macOS 15.5+ and Apple Silicon. Sandbox features require macOS 26+ (Tahoe).

### Verifying Changes Without Full Build

The Xcode workspace has pre-existing build failures in external dependencies (mlx-swift-lm, IkigaJSON). To verify your Swift changes compile cleanly without hitting those, compile OsaurusCore sources only:

```bash
cd Packages/OsaurusCore && swift build 2>&1 | grep -E "error:" | grep -v "IkigaJSON"
```

If the filtered output is empty, your code compiles.

## Testing

```bash
make test                                    # Run all OsaurusCore tests
swift test --package-path Packages/OsaurusCore  # Same thing directly
swift test --package-path Packages/OsaurusCore --filter ChatEngineTests  # Single test class
```

Tests live in `Packages/OsaurusCore/Tests/` mirroring the source directory structure.

## Linting

Uses `swift-format`. A lefthook pre-push hook runs automatically if lefthook is installed.

```bash
swift-format lint --strict --recursive Packages App     # Check
swift-format format --in-place --recursive Packages App # Fix
```

## Architecture

Swift 6.2, swift-tools-version 6.2. Three SPM packages under an Xcode workspace:

- **OsaurusCore** — All app logic (the only package you'll usually touch)
- **OsaurusCLI** — CLI binary (`osaurus` command), thin wrapper over OsaurusCore
- **OsaurusRepository** — Plugin registry and installation
- **App/** — macOS app target (SwiftUI entry point, assets, entitlements)

### OsaurusCore Layers

Strict layered architecture inside `Packages/OsaurusCore/`:

| Layer           | Role                                             | Rules                                                                                                                                           |
| --------------- | ------------------------------------------------ | ----------------------------------------------------------------------------------------------------------------------------------------------- |
| **Models/**     | Pure data types, DTOs, Codable structs           | No `@Published`, no `static let shared`                                                                                                         |
| **Services/**   | Business logic                                   | Swift `actor` for concurrent work, stateless `struct` for pure functions. Never `ObservableObject`/`@Observable`. Suffix: `Service` or `Engine` |
| **Managers/**   | UI state holders                                 | `@MainActor`, `@Observable`. Coordinate services. Suffix: `Manager`                                                                             |
| **Views/**      | SwiftUI views                                    | Organized by feature subfolder, not by type                                                                                                     |
| **Networking/** | HTTP server (SwiftNIO), routing, relay tunnels   |                                                                                                                                                 |
| **Storage/**    | SQLite databases                                 | Suffix: `Database`                                                                                                                              |
| **Tools/**      | MCP tool definitions, plugin ABI, tool registry  |                                                                                                                                                 |
| **Identity/**   | secp256k1 cryptographic identity and access keys |                                                                                                                                                 |
| **Work/**       | Work mode execution, file operations             |                                                                                                                                                 |
| **Utils/**      | Cross-cutting helpers                            |                                                                                                                                                 |

### Key Naming Conventions

- `FooManager` — observable UI state holder (`@MainActor`)
- `FooService` / `FooEngine` — business logic actor
- `FooStore` — JSON file persistence
- `FooDatabase` — SQLite persistence
- `FooView` — SwiftUI view
- `FooTests` — test file

### Key Dependencies

- **MLX** (mlx-swift, mlx-swift-lm) — local model inference on Apple Silicon
- **SwiftNIO** — HTTP server
- **MCP swift-sdk** — Model Context Protocol server/client
- **Apple Containerization** — sandbox VM
- **FluidAudio** — on-device voice transcription
- **VecturaKit** — vector search for RAG
- **swift-secp256k1** — cryptographic identity
- **Sparkle** — auto-updates
- **IkigaJSON** — fast JSON parsing
- **Highlightr** — syntax highlighting

### Artifacts System

Agents produce rich content via the `SharedArtifact` model (`Models/WorkModels.swift`). Artifacts render inline in chat as styled cards (`Views/Work/NativeArtifactCardView.swift`) and in a dedicated modal viewer in work mode (`Views/Work/WorkView.swift`).

- **Generation** — work mode agents create artifacts via `complete_task` and `share_artifact` tools in `WorkExecutionEngine.swift`. Chat messages include them as `.sharedArtifact` content blocks.
- **Persistence** — artifacts are written to disk at `OsaurusPaths.contextArtifactsDir()` and indexed via `IssueStore.createSharedArtifact()`.
- **Rendering** — type-specific native renderers: WKWebView (HTML), PDFView (PDF), AVPlayerView (video), Highlightr (code), SwiftMath (LaTeX), NSImageView (images), custom audio player, and AppKit markdown (`NativeMarkdownView`).

### Inference & Tool Calling

- OpenAI-compatible DTOs in `Models/OpenAIAPI.swift`
- Prompt templating handled by MLX `ChatSession` — Osaurus does not assemble prompts manually
- Tool calls surface via MLX `ToolCallProcessor` and event streaming, not text parsing
- Streaming tool call deltas emitted in `Networking/AsyncHTTPHandler.swift`

## Feature Architecture

### Agents

Each agent is a distinct persona with UUID, name, system prompt, theme, and cryptographic identity. Key files:

- **Model**: `Models/Agent/Agent.swift` — config fields include `defaultModel`, `temperature`, `toolSelectionMode` (Auto/Manual), `autonomousExec`, `chatQuickActions`
- **Persistence**: `Models/Agent/AgentStore.swift` — JSON files in `~/.osaurus/agents/`
- **Manager**: `Managers/AgentManager.swift` — CRUD, active agent tracking, effective settings resolution (agents inherit global `ChatConfiguration` unless overridden)
- **Default agent**: UUID `00000000-0000-0000-0000-000000000001`, immutable

**Execution flow**: user message → `SystemPromptComposer` builds prompt (base + memory + tools/skills) → `ChatEngine.streamChat()` routes to provider via `ModelServiceRouter` → response streamed → `MemoryService.recordConversationTurn()` extracts facts

### Memory (4-Layer System)

Memory is scoped **per-agent** and optionally **per-project**. Config in `Models/Voice/MemoryConfiguration.swift`. Persistence in `~/.osaurus/memory/memory.sqlite` (WAL mode, schema V5). Vector index in `~/.osaurus/memory/vectura/`.

| Layer                     | What                                       | Key Type                | Retention                                                   |
| ------------------------- | ------------------------------------------ | ----------------------- | ----------------------------------------------------------- |
| 1. User Profile           | Synthetic user model                       | `UserProfile`           | Permanent, regenerated after 10 new entries                 |
| 2. Working Memory         | Facts, preferences, decisions, corrections | `MemoryEntry` (7 types) | 500 max per agent, with confidence/status/temporal validity |
| 3. Conversation Summaries | Conversation digests                       | `ConversationSummary`   | 180 days                                                    |
| 4. Conversation Chunks    | Raw turn history                           | `ConversationChunk`     | Permanent                                                   |

- **MemoryService** (`Services/Memory/`) — orchestrates extraction after each turn: inserts chunks (L4), extracts facts (L2) via LLM, runs 3-layer verification (Jaccard dedup at 0.6, contradiction detection at 0.85, semantic dedup), debounces summary generation (60s)
- **MemorySearchService** — VecturaKit hybrid search (BM25 + vector embeddings), fallback to SQLite LIKE
- **MemoryContextAssembler** — builds context string for system prompt: profile → working memory → summaries → graph relationships. Query-aware retrieval expands chunk windows (±2 turns). Each section has a token budget (profile 2000, working memory 3000, summaries 3000, chunks 3000, graph 300). Cache key includes `projectId` to prevent cross-project stale hits.
- **Knowledge Graph** — `GraphEntity` and `GraphRelationship` types, extracted during memory insertion, depth-limited traversal (1-4 hops). Entities/relationships are **global** (not project-scoped) since they represent cross-project concepts.

**Project-scoped memory:** When a conversation belongs to a project, memory entries are tagged with `project_id`. Queries use union semantics: `WHERE agent_id = ? AND (project_id = ? OR project_id IS NULL)` — returns project-specific entries **plus** global entries. L1 (User Profile) stays global; L2–L4 support project scoping. See [MEMORY.md](docs/MEMORY.md#project-scoped-memory) for details.

### Plugins

Native dylib plugins with C ABI. Key files: `Models/Plugin/ExternalPlugin.swift`, `Managers/Plugin/PluginManager.swift`, `Services/Plugin/PluginHostAPI.swift`.

- **ABI v1** (legacy): single entry `osaurus_plugin_entry()`, tools only
- **ABI v2** (current): entry `osaurus_plugin_entry_v2()`, receives `osr_host_api` with 20 callbacks in 9 groups: config store, SQLite data store, logging, agent dispatch (with rate limiting 10/min), inference (streaming), model listing, HTTP client (SSRF-protected), file I/O
- **Lifecycle**: discovery (`~/osaurus/Tools/{pluginId}/{version}/`) → SHA256 + code signing verification → dlopen → init → register tools/routes/skills/web → runtime → teardown + dlclose
- **Security**: quarantine system (`.currently_loading` → `.quarantine` on crash), per-plugin SQLite at `~/osaurus/Plugins/{pluginId}/data.db`, keychain-backed secrets with per-agent scoping
- **Repository**: `OsaurusRepository` package, git-based registry, 4-hour background refresh, `PluginRepositoryService` handles install/upgrade/uninstall

### Tools

Central registry at `Tools/ToolRegistry.swift` (@MainActor singleton). Tools come from 4 sources tracked separately:

- **Built-in** (`builtInToolNames`) — native Osaurus tools
- **Plugin** (`pluginToolNames`) — from loaded plugins
- **MCP** (`mcpToolNames`) — from connected MCP servers
- **Sandbox** (`sandboxToolNames`) — sandbox VM tools

**Execution pipeline**: model requests tool → permission gating (system permissions + tool policy: ask/auto/deny) → argument validation against `inputSchema` → secret injection (`_secrets` key) → route to source (direct call / plugin invoke queue / MCP server / sandbox exec) → result handling (300s timeout)

**RAG selection**: `capabilities_search()` does keyword + semantic embedding match over tool descriptions. `PreflightCapabilitySearch` injects matched tools into system prompt when `toolSelectionMode == .auto`.

### Skills & Methods

- **Skills** (`Models/Agent/Skill.swift`, `Models/Agent/SkillStore.swift`) — markdown-based instructions (Agent Skills spec compatible). Stored in `~/.osaurus/skills/{skill-name}/` with `SKILL.md` + optional `references/` and `assets/`. 7 built-in skills. `SkillSearchService` indexes via VecturaKit hybrid search (BM25 weight 0.7 + vector).
- **Methods** (`Models/Method/Method.swift`, `Storage/MethodDatabase.swift`) — learned tool-call sequences saved by agents. Scored by `successRate × recencyWeight` (30-day half-life decay). SQLite with tables: methods, method_events, method_scores.

### Projects

Projects group conversations, work tasks, schedules, watchers, and memory under a shared context with a linked folder and instructions. Projects is the third mode alongside Chat and Work.

- **Model**: `Models/Project/Project.swift` — fields include `name`, `folderPath`, `folderBookmark` (security-scoped), `instructions`, `isActive`, `isArchived`
- **Persistence**: `Models/Project/ProjectStore.swift` — JSON files in `~/.osaurus/projects/`
- **Manager**: `Managers/ProjectManager.swift` — CRUD, active project tracking, context building, security-scoped bookmark lifecycle
- **Views**: `Views/Projects/` — `ProjectView` (3-panel coordinator), `ProjectHomeView` (center), `ProjectInspectorPanel` (right), `ProjectListView`, `ProjectEditorSheet`, `FolderTreeView`, `MemorySummaryView`
- **Navigation**: `ChatMode.project` case, `NavigationEntry` with `projectId`, back/forward toolbar items
- **System prompt**: `SystemPromptComposer.appendProjectContext()` injects project instructions and `.md` files from the project folder

**Scoping:** `ChatSessionData`, `Schedule`, `Watcher`, and `WorkTask` all have optional `projectId: UUID?`. Memory entries, summaries, and conversations have `project_id TEXT` columns (schema V4–V5). See Memory section above for query semantics.

### Work Mode

Agent-driven task execution with issue tracking. Key files: `Services/WorkEngine.swift` (43KB), `Services/WorkExecutionEngine.swift` (38KB).

- **Issue decomposition**: objectives → `Issue` (id `os-xxxxxxxx`, status: open/inProgress/blocked/closed, priority P0-P3, type: task/bug/discovery) with `IssueDependency` graph
- **Reasoning loop**: AI reasoning → tool calls → result evaluation → iterate (max 30 iterations, 300s timeout per tool)
- **Context management**: tool results truncated at 8000 chars (JSON field truncation or head¾/tail¼ split), stale results cleared after 8 iterations
- **File operations**: `WorkFolderTools` provides file_tree/read/write/edit/search/move/copy/delete, dir_create, git_status/diff/commit, shell_run. All paths validated within root. Operations logged per-issue in `WorkFileOperationLog` for undo.
- **Persistence**: `Storage/WorkDatabase.swift` (SQLite, `~/.osaurus/work/work.db`), `Storage/IssueStore.swift` (39KB)

### Sandbox

Isolated Linux VM via Apple Containerization. Key files: `Services/Sandbox/SandboxManager.swift` (1091 lines).

- **VM**: Alpine Linux, Kata Containers ARM64 kernel, 8 GiB ext4 initfs, configurable CPUs (1-8) and memory (1-8 GB)
- **Isolation**: VirtioFS mount (`~/.osaurus/container/workspace/` → `/workspace/`), per-agent Linux users at `/workspace/agents/{agentName}/`
- **Host bridge**: vsock → Unix socket (`~/.osaurus/container/bridge.sock`), NIO HTTP server (`HostAPIBridgeServer`) routing `/api/{service}/{remaining}` for secrets, config, inference, agent, events, plugin, log
- **Network**: VZNATNetworkDeviceAttachment (10.0.2.15/24), outbound only, allowlisted domains (Alpine CDN, PyPI, npm, GitHub, crates.io)
- **Security**: `SandboxSecurity` — rate limiting (60 inference/min, 120 http/min, 10 dispatch/min), path sanitization (no `..`, null bytes, shell metacharacters)
- **Plugins**: JSON recipe format for sandbox extensions (dependencies, setup script, file seeds, tool definitions, secrets). Managed by `SandboxPluginManager`.
- **Built-in tools**: file ops (read/list/search/find), write ops + exec (when autonomous), package install (pip/npm/apk), process management, artifact sharing

### Schedules

Recurring task automation. Key files: `Models/Schedule/Schedule.swift`, `Managers/ScheduleManager.swift`.

- **Frequencies**: once, everyNMinutes (5+ min), hourly, daily, weekly, monthly, yearly, cron expression
- **Execution**: single timer finds soonest next-run across all enabled schedules, `Task.sleep()` until then. Missed schedule detection on startup. Timezone-aware (`NSSystemTimeZoneDidChange`).
- **Config**: each schedule has instructions, agentId, mode (ChatMode), folderPath (security-scoped bookmark), parameters dict

### Watchers

Filesystem monitoring that triggers agents. Key files: `Models/Watcher/Watcher.swift`, `Managers/WatcherManager.swift`.

- **FSEvents**: single stream monitoring all enabled watcher paths, smart nested path exclusion
- **Responsiveness**: fast (~200ms), balanced (~1s, default), patient (~3s) debounce windows
- **State machine**: idle → debouncing → processing → settling (then recheck). Max 5 convergence iterations prevents infinite loops.
- **Change detection**: Merkle-style directory fingerprinting (path + size + mtime, never reads content)

### Voice

On-device transcription via FluidAudio (Parakeet TDT CoreML). Key files: `Managers/SpeechService.swift`, `Services/Voice/VADService.swift`, `Services/Voice/TranscriptionModeService.swift`.

- **SpeechService** — wraps FluidAudio, supports microphone and system audio input, streaming transcription
- **VAD mode** — always-on listening with wake-word detection, 3s cooldown, 5s accumulation windows, configurable sensitivity (low/medium/high maps to VAD thresholds 0.85/0.75/0.55)
- **Transcription mode** — global hotkey (Carbon HIToolbox, signature `0x4F544D53`), diff-based typing into any focused text field via accessibility, or clipboard paste. Monitors Esc for manual stop.

### Server & Networking

SwiftNIO HTTP server. Key files: `Networking/OsaurusServer.swift`, `Networking/HTTPHandler.swift`, `Networking/Router.swift`.

- **Server**: actor-owned, `MultiThreadedEventLoopGroup(numberOfThreads: activeProcessorCount)`, default `127.0.0.1:1337`
- **Endpoints**: `GET /health`, `GET /models`, `GET /tags` (Ollama-compat), `POST /chat/completions` (OpenAI-compat), `POST /anthropic/v1/messages` (Anthropic-compat), `POST /api/chat` (Ollama-compat)
- **Auth**: `APIKeyValidator` constructed from master key, validates `osk-v1` tokens via ecrecover
- **Relay**: `RelayTunnelManager` — WebSocket tunnel to `wss://agent.osaurus.ai/tunnel/connect`, frame-based protocol (request/response/stream frames), exponential backoff reconnect, biometric-signed challenges, per-agent unique URLs based on crypto address
- **MCP**: both server (exposes tools to Cursor/Claude Desktop) and client (aggregates remote MCP tools)

### Identity

Hierarchical cryptographic identity. All files in `Identity/`.

- **Master key** (`MasterKey.swift`) — 32 random bytes → secp256k1 → Keccak-256 → EIP-55 address. iCloud Keychain (fallback device-only). Biometric auth required. Memory zeroed after use.
- **Agent keys** (`AgentKey.swift`) — deterministic HMAC-SHA512 derivation from master key (`"osaurus-agent-v1" || bigEndian(index)`). Never persisted, re-derived on demand.
- **Device key** (`DeviceKey.swift`) — DCAppAttestService (P-256 Secure Enclave), software fallback with SecRandomCopyBytes
- **Access keys** (`APIKeyManager.swift`) — format `osk-v1.<base64url_payload>.<hex_signature>`. Agent-scoped or master-scoped. Counter-based anti-replay (`CounterStore`). Revocable individually or in bulk.
- **Request signing** (`OsaurusIdentity.swift`) — two-layer: `base64url(header).base64url(payload).hex(accountSig).base64url(deviceAssertion)` with Keccak-256 domain-separated signing
- **Validation** (`APIKeyValidator.swift`) — lock-free, immutable. Checks: ecrecover signer, issuer in whitelist, audience match, not revoked, not expired. `WhitelistStore` manages master-level and per-agent address sets. `RevocationStore` supports individual (address+nonce) and bulk (counter threshold) revocation.
- **Recovery** (`RecoveryManager.swift`) — one-time codes `OSAURUS-XXXX-XXXX-XXXX-XXXX` (64 bits entropy), shown once, never stored plaintext

## Data Locations

| Data                | Path                                    |
| ------------------- | --------------------------------------- |
| Agents              | `~/.osaurus/agents/*.json`              |
| Projects            | `~/.osaurus/projects/*.json`            |
| Memory DB           | `~/.osaurus/memory/memory.sqlite`       |
| Vector index        | `~/.osaurus/memory/vectura/`            |
| Skills              | `~/.osaurus/skills/{name}/SKILL.md`     |
| Methods DB          | `~/.osaurus/methods/methods.db`         |
| Work DB             | `~/.osaurus/work/work.db`               |
| Plugins (installed) | `~/osaurus/Tools/{pluginId}/{version}/` |
| Plugin data         | `~/osaurus/Plugins/{pluginId}/data.db`  |
| Sandbox config      | `~/.osaurus/config/sandbox.json`        |
| Sandbox workspace   | `~/.osaurus/container/workspace/`       |
| Sandbox bridge      | `~/.osaurus/container/bridge.sock`      |

## Dependencies

The workspace lockfile at `osaurus.xcworkspace/xcshareddata/swiftpm/Package.resolved` is the source of truth. CI uses `-disableAutomaticPackageResolution`. Always commit changes to `Package.resolved` alongside `Package.swift` changes.

## Personal fork and upstream (`osaurus-ai/osaurus`)

Longer guide (paths, Sparkle, `~/.osaurus`, verification): `docs/personal_fork_local_documents/PERSONAL_FORK_AND_LOCAL_SETUP.md`.

This checkout is a **personal fork**. Customizations live here and on `origin`; they are **not** upstream contributions unless explicitly requested.

**Remotes**

- `origin` — your GitHub fork (push target for your work).
- `upstream` — `https://github.com/osaurus-ai/osaurus.git` (fetch only; never push).

**Syncing chosen upstream changes** (local, after `git fetch upstream`):

```bash
git checkout main
git merge upstream/main    # resolve conflicts on your branch; test before push
git push origin main
```

For **selective** imports, cherry-pick specific commits from `upstream/main` instead of merging the whole branch.

Optional read-only tracker branch: `git branch -f upstream-tracker upstream/main` to diff anytime without merging.

**Agents:** Do not open pull requests or push to `osaurus-ai/osaurus` unless the user explicitly asks. Prefer merging **from** `upstream` into **this** repo’s branches.

**GitHub Actions:** Upstream’s workflows may run on this fork as well; you can limit or disable Actions in the fork’s repository settings if you want fewer automated runs. The `Upstream check` workflow (manual only) summarizes commits on `upstream/main` that are not yet in the checked-out ref.

## Branch & Commit Conventions

- Branch from `main` with prefixes: `feat/`, `fix/`, `docs/`
- Prefer Conventional Commits
- Keep PRs small and focused
