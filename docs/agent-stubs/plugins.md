# Native plugins (agent stub)

## Purpose

**Native dylib plugins** (v1/v2 ABI) extend Osaurus with tools, routes, and host callbacks. Lifecycle covers discovery, signing, `dlopen`, and per-plugin data stores under `~/osaurus/`. [PLUGIN_AUTHORING.md](../PLUGIN_AUTHORING.md) is the main guide; registry installs flow through **OsaurusRepository**.

## Key paths (`Packages/OsaurusCore/`)

- `Managers/Plugin/` — `PluginManager.swift`, sandbox plugin library/manager
- `Services/Plugin/` — host API surface (`PluginHostAPI.swift`), repository service
- `Models/Plugin/` — plugin configuration and HTTP/plugin models

## Invariants / don’t break

- **ABI and security** (signing, quarantine, capability boundaries) must stay aligned with [PLUGIN_AUTHORING.md](../PLUGIN_AUTHORING.md) and [SECURITY.md](../SECURITY.md).
- Prefer **Models** for pure types; **Services** for plugin host logic; **Managers** for observable UI state ([`CLAUDE.md`](../../CLAUDE.md)).

## See also

- [PLUGIN_AUTHORING.md](../PLUGIN_AUTHORING.md)
- [DEVELOPER_TOOLS.md](../DEVELOPER_TOOLS.md)
- [DEVELOPER_MAP.md](../DEVELOPER_MAP.md)
