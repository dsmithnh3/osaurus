# Budget-Aware Project Context with Smart File Selection

> **Status:** Approved design
> **Date:** 2026-04-10
> **Scope:** `Packages/OsaurusCore/Managers/ProjectManager.swift` + new test file

## Problem

`ProjectManager.projectContext(for:)` reads ALL `.md` files recursively from a project folder with no budget, no exclusions, and no prioritization. For code repos this is manageable, but for AI workspace folders (e.g., CIMCO Refrigeration with 1,786 `.md` files across 22 sub-projects) it produces unbounded context that overwhelms the system prompt.

Additionally, the method uses a plain `folderPath` string instead of the security-scoped bookmark URL, which silently fails in sandboxed macOS builds.

## Design

### Budget-Aware File Selection

A 32,000-character budget (~8,000 tokens) caps total project context. Files are discovered, sorted by priority tier, and read in order until the budget is exhausted.

#### Priority Tiers

| Priority    | Files                                                   | Rationale                                          |
| ----------- | ------------------------------------------------------- | -------------------------------------------------- |
| 1 (highest) | `CLAUDE.md`, `AGENTS.md`, `GEMINI.md`                   | AI agent instructions                              |
| 2           | `TASKS.md`, `README.md`                                 | Active work tracking + project overview            |
| 3           | `active-projects.md`                                    | Multi-project workspace index                      |
| 4           | `*.yaml` in project root or direct `config/` child only | Structured metadata (workspace.yaml, project.yaml) |
| 5           | Other root-level `.md` files                            | Remaining top-level docs                           |
| 6           | Deeper `.md` files (depth <= 3)                         | Sub-project docs, capped by depth                  |

All tier 1-3 matching is **case-insensitive** (e.g., `tasks.md` matches tier 2 just like `TASKS.md`). No fuzzy/similarity matching is used -- the tiered catch-all design (tiers 5-6) naturally handles naming variations.

Within each tier, files are sorted by size ascending (smaller files first to maximize the number of files included).

#### Exclusion Patterns

Directories excluded from discovery entirely:

- `memory/` -- Claude's own work product, not project instructions
- `.build/`, `DerivedData/`, `node_modules/` -- build artifacts
- `docs/superpowers/` -- spec/plan files (referenced by path when needed)
- `benchmarks/`, `results/` -- generated output

#### Budget Behavior

1. Files are read in priority order, accumulating characters
2. If a file fits within remaining budget, include it in full
3. If a file exceeds remaining budget but budget > 500 chars: include first 500 characters + `\n[truncated -- full file at {path}]`
4. If remaining budget <= 500 chars: stop (no more files)

#### Discovery Depth Limit

`FileManager.enumerator` has no built-in depth parameter. Depth is computed as the number of path components relative to the project root URL. For example, if the project root is `/Users/dan/CIMCO/`, then `README.md` is depth 0, `sub/notes.md` is depth 1, and `sub/deep/nested/file.md` is depth 3.

Maximum discovery depth is 3. Files at depth 4+ are excluded. This prevents crawling deeply nested sub-project template folders. Implementation: compare `fileURL.pathComponents.count - rootURL.pathComponents.count` against `maxDiscoveryDepth`.

### Security-Scoped Bookmark Fix

`ProjectManager` already calls `startAccessingBookmark(for:)` when a project becomes active, which internally calls `url.startAccessingSecurityScopedResource()` and tracks the URL in `accessingBookmarks`. Calling it again would leak the access counter.

`projectContext(for:)` will:

1. Check if the project's bookmark URL is already in `accessingBookmarks` (it should be if the project is active)
2. If not yet accessing (e.g., called before project activation), call `startAccessingBookmark(for:)` and track that we need to stop
3. Use the resolved bookmark URL for file enumeration instead of the plain `folderPath` string
4. Only call `stopAccessingSecurityScopedResource()` if we started access in step 2 (via `defer`)
5. Fall back to `folderPath` string only if no bookmark exists (non-sandboxed builds)

### Constants

```swift
private static let projectContextBudgetChars = 32_000  // ~8,000 tokens
private static let truncatedPreviewChars = 500
private static let maxDiscoveryDepth = 3

private static let excludePatterns = [
    "memory/", ".build/", "DerivedData/", "node_modules/",
    "docs/superpowers/", "benchmarks/", "results/"
]

private static let priorityFileNames: [(tier: Int, names: [String])] = [
    (1, ["claude.md", "agents.md", "gemini.md"]),
    (2, ["tasks.md", "readme.md"]),
    (3, ["active-projects.md"]),
]
// Tier 4: *.yaml in project root or direct config/ child -- matched by pattern
// Tier 5: other root-level .md (depth 0)
// Tier 6: deeper .md files (depth 1-3)
```

### Implementation Scope

**Files modified:**

- `Packages/OsaurusCore/Managers/ProjectManager.swift` -- rewrite `projectContext(for:)` internals, update `discoverMarkdownFiles(in:)` to `discoverProjectFiles(in:excludePatterns:maxDepth:)`

**Files created:**

- `Packages/OsaurusCore/Tests/Project/ProjectContextBudgetTests.swift`

**No changes to:**

- `SystemPromptComposer` (still calls `projectContext(for:)` returning `String`)
- Memory system, models, database, or any other files
- Public API surface

### Tests

Using temp directories with mock `.md`/`.yaml` files:

1. Priority ordering -- tier 1 files appear before tier 6
2. Budget truncation -- files beyond budget get 500-char preview with exact format `\n[truncated -- full file at {path}]`
3. Budget exhaustion -- total output stays under 32,000 chars
4. Exclusion patterns -- `memory/*.md` files not included
5. Case-insensitive matching -- `claude.md` gets tier 1 priority
6. Depth limit -- files at depth 4+ excluded
7. Empty folder -- returns empty string gracefully
8. Single CLAUDE.md -- reads it in full, no truncation

## Future Enhancements

Tracked in `docs/FUTURE_ENHANCEMENTS.md`:

- **Query-aware file indexing** -- VecturaKit-powered selection based on conversation context, not just static priority tiers. Would enable truly relevant file selection for large workspaces.
- **Configurable budgets** -- Move budget constants to `MemoryConfiguration` for per-agent or per-project tuning.
- **`ProjectContextBuilder` extraction** -- Factor budget logic into a dedicated service if complexity grows beyond what fits in ProjectManager.
