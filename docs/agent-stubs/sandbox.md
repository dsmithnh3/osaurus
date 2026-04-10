# Sandbox (agent stub)

## Purpose

The **Linux VM** sandbox runs untrusted code with VirtioFS, vsock bridge to the host, and rate-limited host APIs. Configuration, networking allowlists, and built-in tools are documented in [SANDBOX.md](../SANDBOX.md). Host paths include `~/.osaurus/container/` (see [`CLAUDE.md`](../../CLAUDE.md)).

## Key paths (`Packages/OsaurusCore/`)

- `Services/Sandbox/` — `SandboxManager.swift` and related bridge, security, VM lifecycle

## Invariants / don’t break

- **Never widen** network or filesystem exposure without an explicit security review path ([SANDBOX.md](../SANDBOX.md), [SECURITY.md](../SECURITY.md)).
- Bridge and API contracts between guest and host must stay backward-compatible or versioned—clients rely on stable behavior.

## See also

- [SANDBOX.md](../SANDBOX.md)
- [PLUGIN_AUTHORING.md](../PLUGIN_AUTHORING.md) (sandbox plugin recipes)
- [DEVELOPER_MAP.md](../DEVELOPER_MAP.md)
