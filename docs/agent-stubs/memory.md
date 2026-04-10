# Memory (agent stub)

## Purpose

Osaurus keeps **per-agent** (and optionally **per-project**) memory: working facts, conversation summaries, chunks, and (where enabled) vector search. Code extracts and retrieves context for the system prompt. Runtime data lives under `~/.osaurus/memory/` (SQLite schema V5 + Vectura index)—see [`CLAUDE.md` data locations](../../CLAUDE.md#data-locations) and [MEMORY.md](../MEMORY.md) for behavior and configuration.

## Key paths (`Packages/OsaurusCore/`)

- `Services/Memory/` — orchestration, extraction, search, context assembly
- `Storage/MemoryDatabase.swift` — SQLite persistence (and related storage types)
- `Models/Memory/` — memory configuration and model types

## Invariants / don’t break

- Keep **Models** free of UI and singletons; heavy work belongs in **Services** (see [`CLAUDE.md`](../../CLAUDE.md) OsaurusCore layers).
- Persisted paths and schema contracts are user-facing—coordinate changes with migration notes in code and [MEMORY.md](../MEMORY.md).
- **Project scoping:** Memory queries use union semantics (`project_id = ? OR project_id IS NULL`). Knowledge graph entities/relationships stay global. See [MEMORY.md#project-scoped-memory](../MEMORY.md#project-scoped-memory).

## See also

- [MEMORY.md](../MEMORY.md)
- [MEMORY.md#project-scoped-memory](../MEMORY.md#project-scoped-memory)
- [DEVELOPER_MAP.md](../DEVELOPER_MAP.md)
