# Developer map

Quick orientation for **where to edit** in this repo. **Canonical commands, layer rules, and architecture** live in **CLAUDE.md** at the repository root—open that file locally; it may not be present in every remote checkout.

## Workspace layout

| Path                          | Role                                              |
| ----------------------------- | ------------------------------------------------- |
| `App/`                        | macOS app target (SwiftUI, assets, entitlements)  |
| `Packages/OsaurusCore/`       | All core app logic (usual place for feature work) |
| `Packages/OsaurusCLI/`        | `osaurus` CLI — thin wrapper over OsaurusCore     |
| `Packages/OsaurusRepository/` | Plugin registry package                           |
| `osaurus.xcworkspace`         | Open this in Xcode 16.4+                          |

## If you change … start here

Use **directories** as anchors; open **CLAUDE.md** at the repository root for the full layer table (Models / Services / Managers / Views, etc.).

| Theme                      | Start in `Packages/OsaurusCore/`                                           | Deep doc                                           |
| -------------------------- | -------------------------------------------------------------------------- | -------------------------------------------------- |
| **Memory**                 | `Services/Memory/`, `Storage/` (`MemoryDatabase` and related)              | [MEMORY.md](MEMORY.md)                             |
| **Chat / inference**       | `Services/Chat/`                                                           | [OpenAI_API_GUIDE.md](OpenAI_API_GUIDE.md)         |
| **Tools / MCP**            | `Tools/`, `Managers/MCPProviderManager.swift`                              | [REMOTE_MCP_PROVIDERS.md](REMOTE_MCP_PROVIDERS.md) |
| **Work mode**              | `Services/WorkEngine.swift`, `Services/WorkExecutionEngine.swift`, `Work/` | [WORK.md](WORK.md)                                 |
| **Sandbox**                | `Services/Sandbox/`                                                        | [SANDBOX.md](SANDBOX.md)                           |
| **Identity**               | `Identity/`                                                                | [IDENTITY.md](IDENTITY.md)                         |
| **Plugins (native dylib)** | `Managers/Plugin/`, `Services/Plugin/`, `Models/Plugin/`                   | [PLUGIN_AUTHORING.md](PLUGIN_AUTHORING.md)         |

**HTTP / relay / local API:** `Networking/` (see **CLAUDE.md** at the repository root — Server & Networking).

## One-screen stubs (agents & humans)

Subsystem entry points with short **purpose, paths, invariants, see also**: [`agent-stubs/`](agent-stubs/) (e.g. [memory](agent-stubs/memory.md)).

## Docs table of contents

Grouped list of guides: [INDEX.md](INDEX.md).

## Personal fork / local setup

Fork workflow, `~/.osaurus`, Sparkle, and local install detail: [PERSONAL_FORK_AND_LOCAL_SETUP.md](personal_fork_local_documents/PERSONAL_FORK_AND_LOCAL_SETUP.md).
