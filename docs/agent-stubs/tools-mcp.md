# Tools & MCP (agent stub)

## Purpose

**Built-in tools**, **plugin tools**, **MCP tools**, and **sandbox tools** are registered and dispatched through the tool system. Osaurus is both an **MCP server** (expose tools to clients) and an **MCP client** (aggregate remote servers). Configuration and security expectations are in the remote MCP guide and **CLAUDE.md** at the repository root.

## Key paths (`Packages/OsaurusCore/`)

- `Tools/` — tool definitions, `ToolRegistry.swift`, built-in tool implementations
- `Managers/MCPProviderManager.swift` — MCP client/provider aggregation (entry point filename is stable; prefer this over listing every tool)

## Invariants / don’t break

- Tool **names**, **schemas**, and **permission** flows are part of the product contract—update docs when changing behavior ([REMOTE_MCP_PROVIDERS.md](../REMOTE_MCP_PROVIDERS.md), [PLUGIN_AUTHORING.md](../PLUGIN_AUTHORING.md)).
- Keep SSRF, secrets, and sandbox boundaries as documented in [SECURITY.md](../SECURITY.md) / sandbox docs—do not bypass validation in `Tools/` or MCP bridges.

## See also

- [REMOTE_MCP_PROVIDERS.md](../REMOTE_MCP_PROVIDERS.md)
- [PLUGIN_AUTHORING.md](../PLUGIN_AUTHORING.md)
- [DEVELOPER_TOOLS.md](../DEVELOPER_TOOLS.md)
- [DEVELOPER_MAP.md](../DEVELOPER_MAP.md)
