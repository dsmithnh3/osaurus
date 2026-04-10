# Repo AI Workflow Baseline — Design Spec

**Status:** Approved 2026-04-10  
**Scope:** Documentation and navigation improvements for AI-assisted and human development. **DocC is explicitly out of scope** and will not be introduced.

## Problem

The repository already has strong canonical guidance in `CLAUDE.md`, short preferences in `AGENTS.md`, and deep feature documentation under `docs/`. For AI tools and fast onboarding, two gaps remain:

1. **Orientation latency** — A new session must hunt through many files to answer “where do I change memory / tools / work mode / chat?”
2. **Uneven discovery** — Humans and agents lack a single **table of contents** and **thin entry stubs** that point at the right long-form guides and code paths.

## Goal

Establish a **balanced baseline** (option **D** in brainstorming): improve **AI-first entry** (primary slice **A**) while keeping **light** support for **human wayfinding** (**B**) and **existing verification habits** (**C**), without duplicating `CLAUDE.md` or adopting DocC.

## Principles

- **`CLAUDE.md` remains canonical** for build, test, lint, architecture table, and fork/upstream rules.
- **`AGENTS.md` stays short**: preferences, fork facts, and **links** to the new map and index—not long duplicated sections.
- Orientation uses **Markdown + code pointers** only; no generated Swift API reference.
- Existing feature guides are **linked**, not rewritten, unless a stub reveals a factual error (fix in follow-up).

## Deliverables

### 1. `docs/DEVELOPER_MAP.md`

Single file optimized for **skim and search**:

- Workspace layout (App, packages, where `OsaurusCore` lives).
- Layer table (or a concise pointer to the same rules in `CLAUDE.md` plus directory paths).
- “If you’re changing **X**, start here” pointers (memory, tools/work, chat/inference, sandbox, identity, etc.) with **directory paths** and links to deep docs.

**Soft budget:** prefer **under ~200 lines**; grow only if necessary.

### 2. `docs/INDEX.md`

Grouped **table of contents** for existing guides in `docs/` (Identity, Sandbox, Memory, Plugins, Work, etc.), **one line per doc** where practical.

Purpose: human and agent **wayfinding** without opening every file.

### 3. `docs/agent-stubs/` (or `docs/subsystems/`)

A **small capped set** of markdown stubs (target **5–8 files**). Each stub is **navigation**, not a second copy of `CLAUDE.md`:

- **Purpose** of the subsystem.
- **Key paths** (directories and, where helpful, representative type names).
- **Invariants / don’t-break-this** (short bullet list).
- **See also** links to existing `docs/*.md` and relevant `Packages/OsaurusCore/` subtrees.

Initial stub candidates (adjust during implementation to match actual edit frequency):

| Stub topic        | Likely deep links                          |
| ----------------- | ----------------------------------------- |
| Chat / inference  | Chat engine, providers, streaming         |
| Memory            | `MEMORY.md`, storage, services           |
| Tools / MCP       | Tool registry, MCP integration docs      |
| Work mode         | `WORK.md`, work engine                   |
| Sandbox           | `SANDBOX.md`, sandbox manager            |
| Identity / keys   | `IDENTITY.md`, Identity layer            |
| Plugins           | `PLUGIN_AUTHORING.md`, plugin manager    |

**Soft budget:** **~80 lines or fewer per stub**.

### 4. Update `AGENTS.md`

Add bullets that define the default path:

`AGENTS.md` → `docs/DEVELOPER_MAP.md` → relevant stub → existing feature doc → code.

Reiterate that verification commands live in **`CLAUDE.md`** / **`AGENTS.md`** (no new competing sources).

### 5. Optional: `docs/CONTRIBUTING.md`

Add a **short paragraph** in “Getting started” or “Architecture guide” that points contributors and agents to `docs/DEVELOPER_MAP.md` and `docs/INDEX.md`. Keep it **one paragraph** to avoid drift from `CLAUDE.md`.

## Workflows

### AI agents (primary)

1. Read `AGENTS.md`, then `docs/DEVELOPER_MAP.md`.
2. Open the matching stub under `docs/agent-stubs/` (or `docs/subsystems/`).
3. Follow links to full guides (`MEMORY.md`, etc.) and then the codebase.

### Humans (light)

1. Browse `docs/INDEX.md` for the right guide.
2. Use `DEVELOPER_MAP.md` when the task is “where does this live in code?”

### Verification (unchanged in v1)

- Before claiming a Swift change compiles or work is complete, use the **existing** commands documented in `CLAUDE.md` (e.g. `swift build` with the IkigaJSON noise filter, `make test`, `swift-format` as applicable).
- **No new CI gates** required by this spec unless added as a separate follow-up.

## Non-goals

- DocC, Swift-DocC catalogs, or hosted symbol reference.
- Rewriting long-form guides in bulk.
- Mandatory ADRs, PR template overhauls, or doc ownership rosters.
- New automation (linters for doc drift, etc.) in v1.

## Success criteria

- A new session can locate **where to edit** for memory, tools, work mode, and chat within **one or two hops** from repo root (`AGENTS.md` / `README` → map → stub → code).
- Combined **new** material (map + index + stubs + `AGENTS.md` delta + optional `CONTRIBUTING` paragraph) stays **lean**: stubs and map respect the soft line budgets above.
- **No contradiction** with `CLAUDE.md` or `.cursor/rules/personal-fork.mdc`; stubs **link** to canon instead of re-stating fork policy.

## Implementation note

Implementation tasks (file names finalization, exact stub list, line edits) belong in a separate **implementation plan** produced after this spec is reviewed in the repo.
