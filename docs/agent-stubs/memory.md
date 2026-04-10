# Memory (agent stub)

## Purpose

Osaurus keeps **per-agent** memory: working facts, conversation summaries, chunks, and (where enabled) vector search. Code extracts and retrieves context for the system prompt. Runtime data lives under `~/.osaurus/memory/` (SQLite + Vectura index)—see **CLAUDE.md** at the repository root (section “Data locations”) and [MEMORY.md](../MEMORY.md) for behavior and configuration.

## Key paths (`Packages/OsaurusCore/`)

- `Services/Memory/` — orchestration, extraction, search, context assembly
- `Storage/MemoryDatabase.swift` — SQLite persistence (and related storage types)
- `Models/Memory/` — memory configuration and model types

## Invariants / don’t break

- Keep **Models** free of UI and singletons; heavy work belongs in **Services** (see **CLAUDE.md** at the repository root — OsaurusCore layers).
- Persisted paths and schema contracts are user-facing—coordinate changes with migration notes in code and [MEMORY.md](../MEMORY.md).

## See also

- [MEMORY.md](../MEMORY.md)
- [DEVELOPER_MAP.md](../DEVELOPER_MAP.md)
