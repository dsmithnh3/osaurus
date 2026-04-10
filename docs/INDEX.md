# Documentation index

Table of contents for Markdown guides in `docs/`. For **where code lives**, use [DEVELOPER_MAP.md](DEVELOPER_MAP.md) and [agent-stubs/](agent-stubs/).

## Core product & features

- [Accessibility](ACCESSIBILITY.md) — accessibility features and guidance
- [Features](FEATURES.md) — product / feature inventory
- [Memory](MEMORY.md) — memory system (layers, storage, retrieval)
- [Skills](SKILLS.md) — Agent Skills and methods
- [Themes](THEMES.md) — theming
- [Voice input](VOICE_INPUT.md) — transcription and voice UX
- [Watchers](WATCHERS.md) — filesystem watchers
- [Work mode](WORK.md) — issues, execution, artifacts

## Security & identity

- [Identity](IDENTITY.md) — keys, access tokens, cryptographic identity
- [Security](SECURITY.md) — security model and practices

## Sandbox & execution

- [Sandbox](SANDBOX.md) — VM, bridge, sandbox tools and config

## Providers & APIs

- [OpenAI API guide](OpenAI_API_GUIDE.md) — HTTP API, streaming, tool calling
- [Remote providers](REMOTE_PROVIDERS.md) — cloud provider configuration
- [Remote MCP providers](REMOTE_MCP_PROVIDERS.md) — MCP client integration

## Plugins & tools

- [Plugin authoring](PLUGIN_AUTHORING.md) — native plugins, ABI, registry
- [Developer tools](DEVELOPER_TOOLS.md) — in-app dev tooling

## Configuration & integration

- [Shared configuration](SHARED_CONFIGURATION_GUIDE.md) — shared config for apps connecting to Osaurus

## Project & community

- [Code of conduct](CODE_OF_CONDUCT.md)
- [Contributing](CONTRIBUTING.md)
- [Support](SUPPORT.md)

## Developer navigation

- [Developer map](DEVELOPER_MAP.md) — workspace layout and “start here” by theme
- [Agent stubs](agent-stubs/) — short per-subsystem entry pages (e.g. [memory](agent-stubs/memory.md))
- [Doc links & CI prerequisites](DOC_LINKS_AND_CI.md) — when `verify-docs` / **Docs integrity** fails on `CLAUDE.md` or fork-local paths

## Fork-local

Personal fork notes (paths may vary upstream):

- [Personal fork & local setup](personal_fork_local_documents/PERSONAL_FORK_AND_LOCAL_SETUP.md)
- [Opal port roadmap](personal_fork_local_documents/OPAL_PORT_ROADMAP.md)
- [Xcode preview catalog](personal_fork_local_documents/xcode-preview-catalog.md)

These fork-local links require the files to be **committed** for CI to pass—see [DOC_LINKS_AND_CI.md](DOC_LINKS_AND_CI.md).

## Specs & plans

Design specs and implementation plans for larger efforts:

- [superpowers/specs/](superpowers/specs/)
- [superpowers/plans/](superpowers/plans/)
