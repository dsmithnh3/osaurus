# Branch Review: `feat/projects-first-class` vs `main`

> **Date:** 2026-04-12
> **Branch:** `feat/projects-first-class` (80 commits, 159 files, +16,008 / -1,443 lines)
> **Scope:** Full deep analysis — backend logic, tool calling, agents, skills, algorithms, data layer, and recommendations

---

## Executive Summary

This branch introduces **Projects as a first-class entity** in Osaurus. Projects group conversations, work tasks, schedules, watchers, and memory under a shared context with a linked folder and custom instructions.

**The core engines — inference, tool calling, memory extraction, agent execution, skill matching — all run identically to `main`.** No algorithms were modified. The branch is additive infrastructure: a project-scoping layer built on top of existing systems. Changes fall into five categories:

1. **Data layer** — New `project_id` columns, migrations, indexes, query filtering
2. **Context layer** — Project instructions + folder files injected into system prompts
3. **Coordination layer** — ProjectManager orchestrates bookmarks, active project, archive cascading
4. **Navigation layer** — Back/forward stack, sidebar routing, sub-modes
5. **Glue code** — Passing `projectId` through existing method chains

---

## Table of Contents

- [What Changed (Backend Logic)](#what-changed-backend-logic)
  - [New Models & Data Structures](#1-new-models--data-structures)
  - [New Managers & Services](#2-new-managers--services)
  - [Storage & Database](#3-storage--database-changes)
  - [Networking](#4-networking)
  - [Utilities](#5-utilities)
  - [Formatting-Only Changes](#6-formatting-only-changes-no-behavioral-impact)
- [What Was NOT Changed](#what-was-not-changed)
- [Behavioral Flows](#behavioral-flows)
- [Test Coverage Analysis](#test-coverage-analysis)
- [Recommendations](#recommendations)
- [Files Changed (Backend Only)](#files-changed-backend-only)

---

## What Changed (Backend Logic)

### 1. New Models & Data Structures

#### Project Model (`Models/Project/Project.swift`) — NEW FILE

New `Project` struct representing a project container:

| Field | Type | Purpose |
|---|---|---|
| `id` | `UUID` | Unique identifier |
| `name` | `String` | Display name |
| `description` | `String?` | Optional description |
| `icon` | `String` | SF Symbol icon name |
| `color` | `String?` | Hex color string |
| `folderPath` | `String?` | Folder path on disk |
| `folderBookmark` | `Data?` | Security-scoped bookmark for macOS sandbox |
| `instructions` | `String?` | Custom instructions injected into system prompt |
| `contextEntries` | `[ProjectContextEntry]?` | Explicitly pinned files/folders |
| `isActive` | `Bool` | Currently being worked on |
| `isArchived` | `Bool` | Archived state |
| `createdAt` / `updatedAt` | `Date` | Timestamps |

`ProjectContextEntry` is a nested struct for pinned context (file path, bookmark, directory flag).

#### ProjectStore (`Models/Project/ProjectStore.swift`) — NEW FILE

Enum managing JSON file persistence at `~/.osaurus/projects/{uuid}.json`. Methods: `loadAll()`, `load(id:)`, `save()`, `delete(id:)`, `exists(id:)`. Sorted by name on load.

#### ChatMode Extension (`Models/Chat/ChatMode.swift`)

- **New case**: `.project` (display name: "Projects", icon: "folder.fill")
- This is the third mode alongside `.chat` and `.work`

#### ChatSessionData (`Models/Chat/ChatSessionData.swift`)

- **New field**: `projectId: UUID?` with backward-compatible `init(from:)` decoding
- Sessions can now be scoped to a project for per-project chat history

#### Memory Models (`Models/Memory/MemoryModels.swift`)

Three models gained `projectId: String?`:

| Model | Impact |
|---|---|
| `MemoryEntry` | Working memory entries can be project-scoped |
| `ConversationSummary` | Summaries can be project-scoped |
| `PendingSignal` | Extraction signals carry project context |

#### WorkTask (`Models/Work/WorkModels.swift`)

- **New field**: `projectId: UUID?`
- Work tasks are associable with projects for scoped task management

#### Schedule (`Models/Schedule/Schedule.swift`)

- **New field**: `projectId: UUID?` with backward-compatible decoding
- Schedules can be scoped to specific projects

#### Watcher (`Models/Watcher/Watcher.swift`)

- **New field**: `projectId: UUID?` with backward-compatible decoding
- File watchers can be scoped to specific projects

#### ChatWindowState Navigation Models (`Managers/Chat/ChatWindowState.swift`)

New supporting types:

| Type | Purpose |
|---|---|
| `SidebarContentMode` | Routes main content: `.chat`, `.projects`, `.scheduled` |
| `ProjectSubMode` | Sub-mode within projects: `.chat`, `.work` |
| `ProjectSession` | Lightweight project context (`activeProjectId`, `subMode`) |
| `NavigationEntry` | Stack entry for back/forward (mode, projectId, sessionId, subMode) |

---

### 2. New Managers & Services

#### ProjectManager (`Managers/ProjectManager.swift`) — NEW FILE (512 lines)

`@Observable @MainActor` singleton managing the full project lifecycle.

**CRUD Operations:**
- `createProject()`, `updateProject()`, `deleteProject()`, `archiveProject()`, `unarchiveProject()`, `reload()`
- Maintains `projects` array and `activeProjectId` published properties

**Project Context Engine** (system prompt injection):
- **Budget**: 32,000 characters (~8,000 tokens) per project
- **Method**: `projectContext(for projectId) async -> String?`
  - Reads project instructions first
  - Processes pinned context entries (Tier 0, always first)
  - Discovers `.md` and `.yaml` files from project folder
  - **6-tier priority system**:
    - Tier 1: Known root files (claude.md, agents.md, gemini.md)
    - Tier 2: tasks.md, readme.md (root only)
    - Tier 3: active-projects.md (root only)
    - Tier 4: YAML files (root or config/ subdirectory)
    - Tier 5: Other root .md files
    - Tier 6: Deeper .md files (depth 1-3)
  - Sorts files by tier, then by size within tier
  - Truncates files exceeding remaining budget with `[truncated]` footer
  - **Exclusion patterns**: `memory/`, `.build/`, `DerivedData/`, `node_modules/`, `docs/superpowers/`, `benchmarks/`, `results/`

**Security-Scoped Bookmark Management:**
- `startAccessingBookmark()` / `stopAccessingBookmark()` — macOS security scope lifecycle
- Also manages pinned context entry bookmarks
- `setActiveProject()` — atomic active project switching with bookmark lifecycle
- Tracks accessing bookmarks in `accessingBookmarks: Set<UUID>` to prevent counter leaks

**Archive Cascading:**
- Archiving a project disables all linked watchers and schedules (`disableProjectAutomations`)

**Last Active Project Persistence:**
- Stores/restores via UserDefaults, validates against existing non-archived projects

#### SystemPromptComposer (`Services/Chat/SystemPromptComposer.swift`)

**New method**: `appendProjectContext(projectId: UUID?) async` — injects project context wrapped in `<project-context>` tags.

**Modified `composeFullContext()` flow**:
1. Gets `ProjectManager.shared.activeProjectId`
2. Calls `appendProjectContext()` **before** memory injection
3. Passes `activeProjectId` to memory assembly functions

**Composition order is now**: base prompt → **project context** → memory context → tools

#### MemoryContextAssembler (`Services/Memory/MemoryContextAssembler.swift`)

Major changes (194 lines added/modified):

- **New overloads** accepting `projectId: String?` for scoped context assembly
- **Cache key changed** from `agentId` alone to `agentId:projectId` (or `agentId:global`)
- **New method**: `buildQueryRelevantSection(projectId:)` — searches memory with project scoping, deduplicates against existing context
- **Modified `buildContext()`** — filters entries/summaries by project
- **Modified `invalidateCache()`** — removes all cache entries for an agent across all projects (prefix match on `agentId:`)

#### MemorySearchService (`Services/Memory/MemorySearchService.swift`)

All search methods gained `projectId: String?` parameter:
- `searchMemoryEntries()`
- `searchConversations()`
- `searchSummaries()`

All pass projectId through to database layer for filtering.

#### MemoryService (`Services/Memory/MemoryService.swift`)

Tracks project context per conversation:

- **New field**: `conversationProjectIds: [String: String?]` — maps conversation ID to project ID
- Modified `recordConversationTurn()` — accepts `projectId: String?`, stores with pending signal, passes to entry creation
- Modified summary generation — tracks and uses projectId for async conversation handling
- Modified `flushSession()` — accepts `projectId: String?`, passes to summary generation
- All entry creation calls pass projectId to database

#### ChatWindowState (`Managers/Chat/ChatWindowState.swift`) — 281 lines modified

Massive refactor adding project-aware navigation:

**New @Published properties**: `projectSession`, `sidebarContentMode`, `showProjectInspector`

**Navigation stack**: `navigationStack: [NavigationEntry]`, `navigationIndex: Int`, `canGoBack`/`canGoForward` computed properties, `pushNavigation()`, `goBack()`, `goForward()`, `restoreNavigationEntry()`

**New methods**:
- `openProject(_ projectId: UUID)` — switches to project mode, manages bookmark lifecycle, pushes navigation
- `switchProjectSubMode(to:)` — toggles chat/work within project, manages work tool registration

**Modified `switchMode()` logic**: Cleaner tri-state switch for `.work`, `.project`, `.chat` with navigation tracking

**Modified `resetChat()`**: Restores `session.projectId` after reset if in project mode

#### WorkEngine (`Services/WorkEngine.swift`)

- `startTask()` now passes `ProjectManager.shared.activeProjectId` to task creation
- Work engine tasks automatically inherit active project scope

#### IssueManager (`Managers/IssueManager.swift`)

- `createTask()` and `createTaskSafe()` gain `projectId: UUID? = nil` parameter
- Both pass projectId to WorkTask initialization

#### Other Managers (exhaustive match fixes)

| File | Change |
|---|---|
| `BackgroundTaskManager.swift` | Added `case .project: break` — projects don't run headless |
| `ExecutionContext.swift` | Added `.project` cases for `isStreaming`, `start()`, `stop()` |
| `SlashCommandRegistry.swift` | Added `.project` case handling |
| `SpeechService.swift` | Minor API fix (unrelated to projects) |
| `TaskDispatcher.swift` | Added `.project` exhaustive match |

---

### 3. Storage & Database Changes

#### MemoryDatabase (`Storage/MemoryDatabase.swift`)

**Schema Migration V4**: Adds `project_id TEXT` column to 5 tables:
- `memory_entries`, `conversation_summaries`, `conversations`, `entities`, `relationships`
- Creates composite indexes: `idx_memory_entries_agent_project`, `idx_summaries_agent_project`, `idx_conversations_agent_project`

**Schema Migration V5**: Adds `project_id TEXT` to `pending_signals`

**Query method updates** — all gain `projectId: String?` parameter:
- `loadActiveEntries()` — filters with `WHERE (project_id = ? OR project_id IS NULL)` (union semantics)
- `loadEntriesByIds()` — same union filter
- `loadSummaries()` — project filtering
- `searchMemoryEntries()`, `searchChunks()`, `searchSummaries()` — pass projectId through
- `insertSummary()`, `insertSummaryAndMarkProcessed()` — insert with `project_id`

**Union query semantics**: Returns project-specific entries **plus** global (NULL project_id) entries. Knowledge graph entities intentionally remain global.

#### WorkDatabase (`Storage/WorkDatabase.swift`)

**Schema Migration V5**: Creates `project_agents` table (many-to-many project-agent associations)
**Schema Migration V6**: Adds `project_id TEXT` column to `tasks` table

#### IssueStore (`Storage/IssueStore.swift`)

- `createTask()` — binds `project_id` parameter
- `updateTask()` — includes `project_id` in SET clause
- `listTasks()` — new `projectId: UUID?` parameter, adds WHERE condition if provided
- Task parsing — reads `project_id` from column 7

---

### 4. Networking

#### HTTPHandler (`Networking/HTTPHandler.swift`)

- `MemoryIngestRequest` struct — new field: `var project_id: String?`
- Ingest processing passes `project_id` to `upsertConversation()` and `recordSignal()` during turn processing
- External memory ingestion (e.g., from plugins) can now tag memories with project ID

---

### 5. Utilities

#### OsaurusPaths (`Utils/OsaurusPaths.swift`)

New methods:
- `projects() -> URL` — returns `~/.osaurus/projects/`
- `projectFile(for id: UUID) -> URL` — returns `~/.osaurus/projects/{uuid}.json`

---

### 6. Formatting-Only Changes (No Behavioral Impact)

| File | What Changed |
|---|---|
| `PreflightCapabilitySearch.swift` | swift-format reformatting only (line wrapping, indentation). Zero logic change. |
| `ModelRuntime.swift` | Two `nonisolated(unsafe)` annotations for Swift 6 concurrency compliance. |
| `MLXGenerationEngine.swift` | Added explicit capture list `[existingCache, cachedTokens]` for Swift 6 sendability. |

---

## What Was NOT Changed

| System | Status | Notes |
|---|---|---|
| **Tool calling pipeline** | Untouched | ToolRegistry, invocation, permission gating, secret injection, timeouts |
| **Agent model & execution** | Untouched | Agent.swift, AgentStore, autonomous mode, agent dispatch |
| **Skill system** | Untouched | Skill.swift, SkillStore, SkillSearchService, skill matching |
| **Inference pipeline** | Untouched | ChatEngine, streaming, provider routing, ModelServiceRouter |
| **Memory extraction algorithm** | Untouched | NLP extraction, Jaccard dedup (0.6), contradiction detection (0.85), semantic dedup, 3-layer verification |
| **Plugin system** | Untouched | ABI v1/v2, lifecycle, quarantine, host API, plugin registry |
| **Sandbox** | Untouched | VM, bridge server, security, sandbox plugins |
| **Identity & crypto** | Untouched | Master key, agent keys, signing, API key validation, recovery |
| **MCP server/client** | Untouched | Tool exposure to Cursor/Claude Desktop, remote MCP aggregation |
| **Schedule/Watcher execution** | Untouched | Only gained `projectId` field; execution logic identical |
| **Knowledge graph extraction** | Untouched | Entities intentionally remain global (not project-scoped) |
| **Relay tunnels** | Untouched | WebSocket tunnel, frame protocol, biometric auth |
| **Voice/transcription** | Untouched | FluidAudio, VAD, hotkey transcription |
| **Methods (learned tool sequences)** | Untouched | Method.swift, MethodDatabase, scoring |
| **Onboarding** | Untouched | Only removed 2 unused lines |

---

## Behavioral Flows

### Opening a Project

```
User selects project from sidebar
  → ChatWindowState.openProject(projectId)
    → ProjectManager.setActiveProject(projectId)
      → stopAccessingBookmark(previous)
      → startAccessingBookmark(new) — folder + pinned entries
    → Mode switches to .project
    → NavigationEntry pushed to stack
    → System prompt recomposed:
      → appendProjectContext() injects folder files in <project-context> tags
      → Memory queries filter by projectId (union: project + global)
```

### Switching Project Sub-Mode (Chat ↔ Work)

```
User toggles chat/work within project
  → ChatWindowState.switchProjectSubMode(to: newSubMode)
    → projectSession.subMode updated
    → Work tools registered (if .work) or unregistered (if .chat)
    → NavigationEntry pushed to stack
    → Next inference uses updated context
```

### Creating a Task in Project Context

```
Work engine calls startTask()
  → IssueManager.createTaskSafe(projectId: ProjectManager.shared.activeProjectId)
    → WorkTask created with projectId
    → Stored in work.db with project_id column
    → Appears in project-scoped task list
```

### Memory Recording with Project Scope

```
User sends message in project context
  → MemoryService.recordConversationTurn(projectId: activeProjectId)
    → PendingSignal stored with project_id
    → LLM extraction runs (algorithm unchanged)
    → MemoryEntry created with projectId
    → 3-layer verification (unchanged algorithm)
    → Entry inserted with project_id in memory.sqlite
    → conversationProjectIds[conversationId] = projectId (tracked in-memory)
```

### Memory Retrieval with Project Scope

```
System prompt assembly
  → MemoryContextAssembler.assembleContext(agentId, config, projectId)
    → Cache key: "agentId:projectId" (or "agentId:global")
    → buildContext() calls db.loadActiveEntries(agentId, projectId)
      → SQL: WHERE agent_id = ? AND (project_id = ? OR project_id IS NULL)
      → Returns project-specific + global entries
    → Query-aware section also scoped by projectId
```

---

## Test Coverage Analysis

10 test files added/modified on this branch:

| Test File | Lines | What It Tests | Reveals Logic Changes? |
|---|---|---|---|
| `DatabaseMigrationTests.swift` | 185 | V4/V5 migrations add columns and indexes correctly | Yes — schema structure |
| `MemoryDatabaseProjectScopingTests.swift` | 244 | Union query semantics (project + global entries) | Yes — query behavior |
| `NavigationStackTests.swift` | 361 | NavigationEntry value semantics, stack push/back/forward | Yes — navigation algorithm |
| `ProjectContextBudgetTests.swift` | 348 | File discovery, priority tiering, budget truncation | Yes — context engine |
| `ProjectIdSerializationTests.swift` | 299 | JSON round-trip of `projectId: UUID?` on 4 model types | No — pure model field |
| `ProjectManagerTests.swift` | 102 | CRUD, archive cascading, safe deletion, context building | Yes — lifecycle behavior |
| `ProjectNavigationTests.swift` | 78 | ChatMode.project, SidebarContentMode, ProjectSession | Yes — navigation model |
| `ProjectStoreTests.swift` | 123 | Project model serialization, ProjectStore persistence | No — pure storage |
| `SystemPromptProjectTests.swift` | 90 | Project context injection into system prompts | Yes — prompt composition |
| `MemoryProjectScopingTests.swift` | 28 | assembleContext accepts projectId (smoke test) | Minimal |

### Coverage Gaps

1. **Pinned context entries** — `ProjectContextEntry` and the pinned context handling in `projectContext()` (lines 192-254) are not tested
2. **Archive cascading** — `disableProjectAutomations` is tested but `unarchiveProject` re-enabling is not verified end-to-end
3. **Memory search with projectId** — `MemorySearchService` project scoping is not directly tested (only database layer is)
4. **HTTP ingest with project_id** — The networking layer's `MemoryIngestRequest.project_id` field has no test coverage

---

## Recommendations

### High Priority

#### 1. `conversationProjectIds` — Unbounded In-Memory Growth

**File:** `MemoryService.swift:29`
**Issue:** `private var conversationProjectIds: [String: String?] = [:]` grows by one entry per conversation and is never cleaned up. Over long-running sessions (especially server mode), this dictionary grows indefinitely.

**Recommendation:** Evict entries when a conversation is flushed or summarized. The `flushSession` method (line 361) is the natural cleanup point:

```swift
public func flushSession(agentId: String, conversationId: String, projectId: String? = nil) {
    summaryTasks[conversationId]?.cancel()
    summaryTasks[conversationId] = Task {
        await self.generateConversationSummary(
            agentId: agentId,
            conversationId: conversationId,
            projectId: projectId
        )
        // Clean up after summary generation completes
        self.conversationProjectIds.removeValue(forKey: conversationId)
    }
}
```

Alternatively, cap with an LRU eviction strategy if conversations can be revisited after flush.

---

#### 2. Pinned Context Entry Bookmarks — No Tracking for `stopAccessing`

**File:** `ProjectManager.swift:412-426` and `449-461`
**Issue:** `startAccessingBookmark` iterates pinned `contextEntries` and calls `url.startAccessingSecurityScopedResource()` but discards the result (`_ =`). In `stopAccessingBookmark`, it calls `stopAccessingSecurityScopedResource()` on every entry regardless of whether `start` succeeded. Calling `stop` without a matched `start` can corrupt the macOS kernel reference count.

**Recommendation:** Track which pinned entry bookmarks actually started successfully. One approach:

```swift
// Add alongside accessingBookmarks
private var accessingEntryBookmarks: [UUID: Set<UUID>] = [:]  // projectId -> set of entry IDs
```

Then in `startAccessingBookmark`, only insert entries where `startAccessingSecurityScopedResource()` returned `true`. In `stopAccessingBookmark`, only stop entries in the tracked set.

---

### Medium Priority

#### 3. No Orphan Cleanup for Project-Scoped Memory

**File:** `ProjectManager.swift:86-92`
**Issue:** When a project is deleted, only the JSON file and bookmarks are cleaned up. Memory entries, conversation summaries, and pending signals tagged with that `project_id` remain in SQLite forever. The `safeDeleteLeavesFolderAndMemoryUntouched` test name suggests this is intentional, but there's no way for users to clean up if they want to.

**Recommendation:** Either:
- Add a `purgeProjectData(projectId:)` method that nullifies or deletes orphaned rows (with user confirmation)
- Or add a periodic maintenance task that identifies orphaned project_ids in memory tables

---

#### 4. Non-Project Query Retrieval May Leak Project Entries

**File:** `MemoryContextAssembler.swift:60-82`
**Issue:** The non-project overload of `assembleContextWithQuery` calls `buildQueryRelevantSection` without a `projectId`. If the search layer treats `nil` projectId as "return everything," non-project chats could surface project-specific memories, which may be surprising to users.

**Recommendation:** Verify the chain: `buildQueryRelevantSection(projectId: nil)` → `MemorySearchService.searchMemoryEntries(projectId: nil)` → `MemoryDatabase.searchMemoryEntries(projectId: nil)`. If the database returns all entries when `projectId` is nil (no WHERE clause added), consider whether this is the desired behavior. Options:
- **Keep as-is**: Non-project mode sees everything (global knowledge base) — document this
- **Filter to global-only**: Pass a sentinel like `"global"` to filter to `project_id IS NULL` entries only

---

#### 5. No Tests for Pinned Context Entries

**File:** `ProjectContextBudgetTests.swift` (coverage gap)
**Issue:** The `ProjectContextEntry` model and pinned context handling in `projectContext()` lines 192-254 are not exercised by any tests. This includes:
- Pinned file context injection
- Pinned directory discovery within context
- Bookmark resolution for pinned entries
- Budget interaction (pinned entries consume budget before discovered files)
- Edge cases: pinned entry with stale bookmark, pinned entry to nonexistent path

**Recommendation:** Add a `ProjectPinnedContextTests.swift` test class covering these paths.

---

### Low Priority

#### 6. Duplicate Bookmark Resolution in `projectContext()`

**File:** `ProjectManager.swift:192-284`
**Issue:** `projectContext()` resolves the folder bookmark again (lines 257-278) even though `startAccessingBookmark(for:)` already did this when the project was activated. The same bookmark data is resolved twice — once for the lifecycle, once for context building.

**Recommendation:** Cache the resolved URL from `startAccessingBookmark()` so `projectContext()` can reuse it:

```swift
private var resolvedBookmarkURLs: [UUID: URL] = [:]
```

This also avoids the edge case where `projectContext()` starts bookmark access (line 269-271) independently of the lifecycle tracking.

---

#### 7. File Discovery Exclusion Pattern Edge Case

**File:** `ProjectManager.swift:361-380`
**Issue:** The exclusion check uses `relativeComponents.contains(where:)`, which matches any path component — including a file's own name. A file literally named `memory.md` at root would not be excluded (it wouldn't match `"memory"` as a directory component since the filename is the last component and the check strips the `/` suffix). However, the `enumerator.skipDescendants()` call at line 372 fires for every matched item, including files — where it's a no-op.

Additionally, `FileManager.enumerator` doesn't strictly guarantee directory-before-contents ordering in all edge cases, though in practice Apple's implementation is depth-first.

**Recommendation:** Add a targeted unit test: enumerate a project folder containing `node_modules/` with nested files and verify none appear in results. The current implementation works in practice but documenting this with a test prevents regression.

---

#### 8. Char-vs-Token Budget Consistency

**File:** `ProjectManager.swift:126`
**Issue:** Budget is `32_000` characters with the comment `~8,000 tokens`, implying a 4:1 ratio. But the memory system uses `MemoryConfiguration.charsPerToken` for its budget calculations. Code-heavy files average ~3.5 chars/token while prose is closer to 4-5.

**Recommendation:** Use the shared constant for consistency:

```swift
nonisolated static let projectContextBudgetChars = 8_000 * MemoryConfiguration.charsPerToken
```

This ensures the project context budget and memory context budget use the same tokenization assumption.

---

### Future Enhancement

#### 9. Project-Aware Tool Selection

**File:** `PreflightCapabilitySearch.swift`
**Issue:** The tool selection system has no project awareness. If a project heavily uses certain tools (e.g., a project always needs `git_*` tools), the preflight search won't weight them differently.

**Recommendation:** Consider a per-project tool preference or bias in `PreflightCapabilitySearch`. This could be as simple as a `preferredTools: [String]?` field on `Project` that gets a search score boost. Not needed now, but worth tracking as projects accumulate usage data.

---

## Priority Summary

| Priority | # | Issue | Type |
|---|---|---|---|
| **High** | 1 | `conversationProjectIds` unbounded growth | Memory leak |
| **High** | 2 | Pinned bookmark tracking mismatch | macOS sandbox safety |
| **Medium** | 3 | Orphaned project memory rows after deletion | Data hygiene |
| **Medium** | 4 | Non-project query retrieval may leak project entries | Correctness |
| **Medium** | 5 | No tests for pinned context entries | Coverage gap |
| **Low** | 6 | Duplicate bookmark resolution | Performance |
| **Low** | 7 | File discovery exclusion edge case | Robustness |
| **Low** | 8 | Char-vs-token budget consistency | Consistency |
| **Future** | 9 | Project-aware tool selection | Enhancement |

---

## Files Changed (Backend Only)

### Models (10 files, 2 new)

| File | Change Type |
|---|---|
| `Models/Project/Project.swift` | **NEW** — Project + ProjectContextEntry structs |
| `Models/Project/ProjectStore.swift` | **NEW** — JSON file persistence |
| `Models/Chat/ChatMode.swift` | Modified — added `.project` case |
| `Models/Chat/ChatSessionData.swift` | Modified — added `projectId: UUID?` |
| `Models/Memory/MemoryModels.swift` | Modified — added `projectId` to 3 types |
| `Models/Work/WorkModels.swift` | Modified — added `projectId` to WorkTask |
| `Models/Schedule/Schedule.swift` | Modified — added `projectId: UUID?` |
| `Models/Watcher/Watcher.swift` | Modified — added `projectId: UUID?` |
| `Models/BackgroundTaskModels.swift` | Modified — exhaustive match |
| `Models/SlashCommand/SlashCommandStore.swift` | Modified — exhaustive match |

### Services (8 files)

| File | Change Type |
|---|---|
| `Services/Chat/SystemPromptComposer.swift` | Modified — project context injection |
| `Services/Memory/MemoryContextAssembler.swift` | Modified — project-scoped assembly + cache |
| `Services/Memory/MemorySearchService.swift` | Modified — project-scoped search |
| `Services/Memory/MemoryService.swift` | Modified — project tracking in pipeline |
| `Services/WorkEngine.swift` | Modified — passes activeProjectId to tasks |
| `Services/Context/PreflightCapabilitySearch.swift` | Formatting only |
| `Services/ModelRuntime.swift` | Swift 6 concurrency annotation only |
| `Services/ModelRuntime/MLXGenerationEngine.swift` | Swift 6 capture list only |

### Managers (8 files, 1 new)

| File | Change Type |
|---|---|
| `Managers/ProjectManager.swift` | **NEW** — 512 lines, full lifecycle manager |
| `Managers/Chat/ChatWindowState.swift` | Modified — 281 lines, navigation + project state |
| `Managers/Chat/ChatWindowManager.swift` | Modified — toolbar, mode toggle, back/forward |
| `Managers/IssueManager.swift` | Modified — projectId parameter on task creation |
| `Managers/BackgroundTaskManager.swift` | Modified — exhaustive match |
| `Managers/ExecutionContext.swift` | Modified — exhaustive match |
| `Managers/SlashCommandRegistry.swift` | Modified — exhaustive match |
| `Managers/SpeechService.swift` | Modified — minor API fix |

### Storage (3 files)

| File | Change Type |
|---|---|
| `Storage/MemoryDatabase.swift` | Modified — V4/V5 migrations, project-scoped queries |
| `Storage/WorkDatabase.swift` | Modified — V5/V6 migrations |
| `Storage/IssueStore.swift` | Modified — project-scoped task CRUD |

### Networking (1 file)

| File | Change Type |
|---|---|
| `Networking/HTTPHandler.swift` | Modified — `project_id` in memory ingest |

### Utils (1 file)

| File | Change Type |
|---|---|
| `Utils/OsaurusPaths.swift` | Modified — `projects()` and `projectFile(for:)` |

### Tests (10 files, all new)

| File | Lines | Focus |
|---|---|---|
| `DatabaseMigrationTests.swift` | 185 | Schema migrations |
| `MemoryDatabaseProjectScopingTests.swift` | 244 | Union query semantics |
| `NavigationStackTests.swift` | 361 | Navigation algorithm |
| `ProjectContextBudgetTests.swift` | 348 | File discovery + tiering |
| `ProjectIdSerializationTests.swift` | 299 | Model serialization |
| `ProjectManagerTests.swift` | 102 | CRUD + lifecycle |
| `ProjectNavigationTests.swift` | 78 | Navigation model |
| `ProjectStoreTests.swift` | 123 | Store persistence |
| `SystemPromptProjectTests.swift` | 90 | Prompt injection |
| `MemoryProjectScopingTests.swift` | 28 | Assembler smoke test |
