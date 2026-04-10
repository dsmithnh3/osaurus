# Work mode (agent stub)

## Purpose

**Work mode** runs agent-driven tasks with **issues**, **tool loops**, file operations, and **artifacts**. Core execution lives in large engine types under `Services/` plus `Work/` helpers. Product behavior and tooling are described in [WORK.md](../WORK.md).

## Key paths (`Packages/OsaurusCore/`)

- `Services/WorkEngine.swift` — issue/work orchestration
- `Services/WorkExecutionEngine.swift` — reasoning loop, tools, artifact-related paths
- `Work/` — work-mode file tools and related work utilities
- `Storage/` — work database / issue persistence (see [WORK.md](../WORK.md) and [`CLAUDE.md`](../../CLAUDE.md) data locations for `work.db`)

## Invariants / don’t break

- Path validation and sandboxing for file operations are security-sensitive—follow existing `Work/` and engine checks ([SECURITY.md](../SECURITY.md)).
- Engines are **Services**, not `ObservableObject`—keep UI in **Managers** / **Views** ([`CLAUDE.md`](../../CLAUDE.md)).

## See also

- [WORK.md](../WORK.md)
- [DEVELOPER_MAP.md](../DEVELOPER_MAP.md)
