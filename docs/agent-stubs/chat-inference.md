# Chat & inference (agent stub)

## Purpose

Chat flows through the **chat engine** and **model routing** (local MLX, cloud providers, streaming, tool calls). This is the main path from user messages to model responses. API surface for external clients is documented in [OpenAI_API_GUIDE.md](../OpenAI_API_GUIDE.md); server wiring is under `Networking/`.

## Key paths (`Packages/OsaurusCore/`)

- `Services/Chat/` — `ChatEngine.swift`, protocols, streaming and tool-call integration with providers
- `Networking/` — HTTP server, handlers, routing (`OsaurusServer`, `HTTPHandler`, `Router` per [`CLAUDE.md`](../../CLAUDE.md))
- `Managers/` — session/UI coordination (e.g. chat managers) as needed for UI-driven features

## Invariants / don’t break

- **Services** stay non-observable; **Managers** own UI-visible state ([`CLAUDE.md`](../../CLAUDE.md) layer rules).
- Provider and DTO shapes affect OpenAI/Anthropic compatibility—change request/response types carefully and align with [OpenAI_API_GUIDE.md](../OpenAI_API_GUIDE.md).

## See also

- [OpenAI_API_GUIDE.md](../OpenAI_API_GUIDE.md)
- [REMOTE_PROVIDERS.md](../REMOTE_PROVIDERS.md)
- [DEVELOPER_MAP.md](../DEVELOPER_MAP.md)
