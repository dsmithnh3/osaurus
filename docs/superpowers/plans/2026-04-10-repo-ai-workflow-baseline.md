# Repo AI Workflow Baseline — Implementation Plan

> **For agentic workers:** Implement task-by-task; use checkboxes (`- [ ]`) for tracking. Doc-only change: no new automated tests required. Verify internal links after edits.

**Goal:** Add developer map, docs index, agent stub entries, and short `AGENTS.md` / optional `CONTRIBUTING` / optional `README` pointers so humans and AI sessions reach the right `docs/*.md` and `Packages/OsaurusCore/` areas in one-to-two hops.

**Architecture:** Markdown-only navigation layer under `docs/`; **`CLAUDE.md` stays canonical** for build/test/architecture. Stubs in `docs/agent-stubs/` link to existing guides and directories; do not duplicate long sections from `CLAUDE.md`. **DocC is out of scope** (per spec).

**Tech Stack:** Markdown, relative links from `docs/`.

---

## File map (create / modify)

| Artifact                             | Action                                                 |
| ------------------------------------ | ------------------------------------------------------ |
| `docs/DEVELOPER_MAP.md`              | Create                                                 |
| `docs/INDEX.md`                      | Create                                                 |
| `docs/agent-stubs/memory.md`         | Create                                                 |
| `docs/agent-stubs/chat-inference.md` | Create                                                 |
| `docs/agent-stubs/tools-mcp.md`      | Create                                                 |
| `docs/agent-stubs/work-mode.md`      | Create                                                 |
| `docs/agent-stubs/sandbox.md`        | Create                                                 |
| `docs/agent-stubs/identity.md`       | Create                                                 |
| `docs/agent-stubs/plugins.md`        | Create                                                 |
| `AGENTS.md`                          | Modify (add navigation bullets + keep short)           |
| `docs/CONTRIBUTING.md`               | Modify (optional one paragraph)                        |
| `README.md`                          | Modify (optional one line after main intro—see Task 8) |

**Stub count:** 7 (within spec cap 5–8). Priority order preserved: memory, chat, tools/MCP, work, sandbox, then identity, plugins.

---

### Task 1: `docs/DEVELOPER_MAP.md`

**Files:**

- Create: `docs/DEVELOPER_MAP.md`

- [ ] **Step 1:** Add title and one sentence pointing to `CLAUDE.md` as canonical build/test/layers.
- [ ] **Step 2:** Document workspace top-level: `App/`, `Packages/OsaurusCore/`, `Packages/OsaurusCLI/`, `Packages/OsaurusRepository/`, `osaurus.xcworkspace` (single short section).
- [ ] **Step 3:** Add **“If you change … start here”** table or bullet list mapping themes to **directories** (primary) and deep docs:

  | Theme            | Start in                                                                               | Deep doc                                                                                             |
  | ---------------- | -------------------------------------------------------------------------------------- | ---------------------------------------------------------------------------------------------------- |
  | Memory           | `Packages/OsaurusCore/Services/Memory/`, `Storage/` (memory DB)                        | [MEMORY.md](../MEMORY.md)                                                                            |
  | Chat / inference | `Packages/OsaurusCore/Services/Chat/`                                                  | (link OpenAI guide if useful) [OpenAI_API_GUIDE.md](../OpenAI_API_GUIDE.md)                          |
  | Tools / MCP      | `Packages/OsaurusCore/Tools/`, `Managers/MCPProviderManager.swift`                     | [REMOTE_MCP_PROVIDERS.md](../REMOTE_MCP_PROVIDERS.md), [PLUGIN_AUTHORING.md](../PLUGIN_AUTHORING.md) |
  | Work mode        | `Packages/OsaurusCore/Services/WorkEngine.swift`, `WorkExecutionEngine.swift`, `Work/` | [WORK.md](../WORK.md)                                                                                |
  | Sandbox          | `Packages/OsaurusCore/Services/Sandbox/`                                               | [SANDBOX.md](../SANDBOX.md)                                                                          |
  | Identity         | `Packages/OsaurusCore/Identity/`                                                       | [IDENTITY.md](../IDENTITY.md)                                                                        |
  | Plugins (native) | `Managers/Plugin/`, `Services/Plugin/`                                                 | [PLUGIN_AUTHORING.md](../PLUGIN_AUTHORING.md)                                                        |

  Adjust paths if the tree differs; **prefer directories** over type lists.

- [ ] **Step 4:** Link **`docs/agent-stubs/`** (“one screen per subsystem”) and **`docs/INDEX.md`**.
- [ ] **Step 5:** Link fork-only deep setup: [PERSONAL_FORK_AND_LOCAL_SETUP.md](personal_fork_local_documents/PERSONAL_FORK_AND_LOCAL_SETUP.md) (under `personal_fork_local_documents/`).
- [ ] **Step 6:** Keep file within spec soft budget (~200 lines); split content only by moving detail into stubs, not by growing the map indefinitely.

---

### Task 2: `docs/INDEX.md`

**Files:**

- Create: `docs/INDEX.md`

- [ ] **Step 1:** Title + one line: purpose (table of contents for repo `docs/`).
- [ ] **Step 2:** Group **by theme**, **alphabetical within group**. Suggested groups (edit if needed):
  - **Core product & features:** ACCESSIBILITY.md, FEATURES.md, MEMORY.md, SKILLS.md, THEMES.md, VOICE_INPUT.md, WATCHERS.md, WORK.md
  - **Security & identity:** IDENTITY.md, SECURITY.md
  - **Sandbox & execution:** SANDBOX.md
  - **Providers & APIs:** OpenAI_API_GUIDE.md, REMOTE_PROVIDERS.md, REMOTE_MCP_PROVIDERS.md
  - **Plugins & tools:** PLUGIN_AUTHORING.md, DEVELOPER_TOOLS.md
  - **Configuration & integration:** SHARED_CONFIGURATION_GUIDE.md
  - **Project & community:** CODE_OF_CONDUCT.md, CONTRIBUTING.md, SUPPORT.md
  - **Developer navigation (this effort):** DEVELOPER_MAP.md — agent-stubs/ (link to folder or first stub)
  - **Fork-local** (short): PERSONAL_FORK_AND_LOCAL_SETUP.md, OPAL_PORT_ROADMAP.md, xcode-preview-catalog.md — all under `personal_fork_local_documents/`

- [ ] **Step 3:** One line per file (title or description). Use relative links, e.g. `[MEMORY](MEMORY.md)`.
- [ ] **Step 4:** Omit duplicating `superpowers/specs/` and `superpowers/plans/` from the main product index **or** add a final **Specs & plans** group with one line linking the `superpowers/` folder for maintainers.

---

### Task 3: Agent stubs (7 files)

**Files:**

- Create: `docs/agent-stubs/memory.md`
- Create: `docs/agent-stubs/chat-inference.md`
- Create: `docs/agent-stubs/tools-mcp.md`
- Create: `docs/agent-stubs/work-mode.md`
- Create: `docs/agent-stubs/sandbox.md`
- Create: `docs/agent-stubs/identity.md`
- Create: `docs/agent-stubs/plugins.md`

For **each** file, use the same skeleton (≤ ~80 lines per spec):

1. **Purpose** (2–4 sentences).
2. **Key paths** — bullet list of `Packages/OsaurusCore/...` directories (required); add at most 1–2 **stable** type/file names only if helpful.
3. **Invariants / don’t break** — 2–5 bullets (from `CLAUDE.md` layer rules where relevant; point to `CLAUDE.md` instead of copying tables).
4. **See also** — link to the deep `docs/*.md` and back to [DEVELOPER_MAP.md](../DEVELOPER_MAP.md).

**Content hints (do not invent behavior; align with existing docs):**

- **memory.md** — `Services/Memory/`, memory storage paths per [MEMORY.md](../MEMORY.md) / `CLAUDE.md` data locations table.
- **chat-inference.md** — `Services/Chat/` (`ChatEngine.swift`, etc.), routing/providers per codebase; link [OpenAI_API_GUIDE.md](../OpenAI_API_GUIDE.md).
- **tools-mcp.md** — `Tools/ToolRegistry.swift`, MCP manager; [REMOTE_MCP_PROVIDERS.md](../REMOTE_MCP_PROVIDERS.md).
- **work-mode.md** — `Services/WorkEngine.swift`, `WorkExecutionEngine.swift`, `Work/`; [WORK.md](../WORK.md).
- **sandbox.md** — `Services/Sandbox/`; [SANDBOX.md](../SANDBOX.md).
- **identity.md** — `Identity/`; [IDENTITY.md](../IDENTITY.md).
- **plugins.md** — plugin managers / `Services/Plugin/`; [PLUGIN_AUTHORING.md](../PLUGIN_AUTHORING.md).

- [ ] **Step 1:** Create directory `docs/agent-stubs/`.
- [ ] **Step 2:** Write `memory.md` … through `plugins.md` using skeleton above.
- [ ] **Step 3:** Spot-check all relative links from `docs/agent-stubs/` (../ to sibling docs).

---

### Task 4: `AGENTS.md`

**Files:**

- Modify: `AGENTS.md`

- [ ] **Step 1:** After “Learned User Preferences”, add a **Navigation** (or **Repo orientation**) bullet block:
  - Default path: `AGENTS.md` → `docs/DEVELOPER_MAP.md` → `docs/agent-stubs/<topic>.md` → feature doc → code.
  - Table of contents: `docs/INDEX.md`.
- [ ] **Step 2:** Keep total file short; no pasted architecture tables.
- [ ] **Step 3:** Confirm verification bullets still point only to `CLAUDE.md` for commands.

---

### Task 5: `docs/CONTRIBUTING.md` (optional)

**Files:**

- Modify: `docs/CONTRIBUTING.md`

- [ ] **Step 1:** In “Getting started” or “Architecture guide”, add **one paragraph** only: point to `docs/DEVELOPER_MAP.md` and `docs/INDEX.md` for orientation and AI-assisted navigation.
- [ ] **Step 2:** Do not duplicate `CLAUDE.md` build instructions.

---

### Task 6: Optional `README.md` one-liner

**Files:**

- Modify: `README.md`

- [ ] **Step 1:** After the first substantive heading/introduction block (e.g. after the “Inference is all you need” section or near “Development”), add **one line**: link to `docs/DEVELOPER_MAP.md` for contributors navigating the repo. Keep HTML + Markdown mix consistent with existing README style.
- [ ] **Step 2:** If a README edit is too noisy, **skip** this task (spec: optional).

---

### Task 7: Link audit and format

**Files:**

- All of the above

- [ ] **Step 1:** From repo root, open `docs/DEVELOPER_MAP.md` and click/preview every internal link.
- [ ] **Step 2:** From `docs/INDEX.md`, verify each linked file exists (paths correct for `personal_fork_local_documents/`).
- [ ] **Step 3:** No `swift-format` requirement for Markdown; if any Swift is touched (should not be), run `swift-format` per `CLAUDE.md`.

---

### Task 8: Commit

- [ ] **Step 1:** `git add` new/modified doc files (and `AGENTS.md`, optional README/CONTRIBUTING).
- [ ] **Step 2:** Commit with Conventional Commits, e.g. `docs: add developer map, index, and agent stubs`.

---

## References

- Spec: [2026-04-10-repo-ai-workflow-baseline-design.md](../specs/2026-04-10-repo-ai-workflow-baseline-design.md)
- Canon: [`CLAUDE.md`](../../../CLAUDE.md)
