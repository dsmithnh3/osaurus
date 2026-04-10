# Future Enhancements

Tracking document for deferred improvements. Each item includes context on why it was deferred and what would trigger implementation.

---

## Project Context System

### Query-Aware File Indexing

**Current state:** Project context uses static priority tiers to select `.md` files within an 8,000-token budget. This works well for most projects but cannot adapt to conversation context (e.g., if a user is discussing a specific sub-project, only that sub-project's files are relevant).

**Enhancement:** Index project `.md` files via VecturaKit (same hybrid BM25 + vector search used by memory). At context assembly time, use the current conversation query to select the most relevant files instead of relying solely on filename priority.

**When to implement:** When users with large workspaces (1,000+ `.md` files) report that the static priority system misses relevant files. The 8,000-token budget is sufficient for most cases -- this becomes valuable only when the right files aren't in the top tiers.

**Complexity:** Medium-high. Requires file change detection (FSEvents or mtime checks), embedding generation for `.md` content, a per-project VecturaKit index, and integration with `MemoryContextAssembler` to coordinate token budgets between project context and memory context.

**Related spec:** `docs/superpowers/specs/2026-04-10-budget-aware-project-context-design.md`

---

### Configurable Project Context Budgets

**Current state:** Budget is hardcoded as `projectContextBudgetChars = 32_000` (~8,000 tokens) in `ProjectManager`.

**Enhancement:** Move budget constants to `MemoryConfiguration` so they can be tuned per-agent or per-project. Some agents may need more project context (e.g., a CIMCO-specialized agent) while others need less.

**When to implement:** When there's a concrete case where the default budget is wrong for a specific agent/project combination. Premature configurability adds complexity without value.

**Complexity:** Low. Move constants, add fields to `MemoryConfiguration`, wire through.

---

### ProjectContextBuilder Extraction

**Current state:** Budget-aware file selection logic lives directly in `ProjectManager.projectContext(for:)`.

**Enhancement:** Extract into a dedicated `ProjectContextBuilder` service if the logic grows beyond what fits cleanly in ProjectManager (e.g., if query-aware indexing is added, or if project context needs coordination with memory token budgets).

**When to implement:** When `projectContext(for:)` exceeds ~100 lines or when query-aware indexing is implemented. Don't extract prematurely.

**Complexity:** Low. Pure refactor, no behavior change.

---

## Memory System

### Token Budget Coordination

**Current state:** Project context (8,000 tokens) and memory context (profile 2,000 + working memory 3,000 + summaries 3,000 + chunks 3,000 + graph 300 = ~11,300 tokens) are independent budgets with no coordination.

**Enhancement:** Shared budget pool where project context and memory context negotiate allocation. If a project has minimal `.md` files, memory gets more budget and vice versa.

**When to implement:** When users report that system prompts are too long (hitting model context limits) or too short (wasting available context). Currently the combined ~19,300 tokens is well within limits.

**Complexity:** Medium. Requires `MemoryContextAssembler` to communicate remaining budget after project context, or a shared budget coordinator.
