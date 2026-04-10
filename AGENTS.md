## Learned User Preferences

- Treat `CLAUDE.md` as the canonical project contract; update it when build steps, architecture, or verify commands change instead of scattering the same content in multiple places.
- Keep agent-facing notes here and in Cursor rules short; link to `CLAUDE.md` (and [`docs/personal_fork_local_documents/PERSONAL_FORK_AND_LOCAL_SETUP.md`](docs/personal_fork_local_documents/PERSONAL_FORK_AND_LOCAL_SETUP.md) for fork/local install) rather than duplicating long sections.
- Documentation stays Markdown, `docs/`, and code pointers; do not propose DocC or Swift-DocC unless the user explicitly asks.
- Before claiming a Swift change compiles or work is finished, run the repo’s OsaurusCore verification (`swift build` with the IkigaJSON noise filter per `CLAUDE.md`) or targeted tests—do not rely on assumptions.

## Repo orientation (navigation)

- **Default path:** `AGENTS.md` → [`docs/DEVELOPER_MAP.md`](docs/DEVELOPER_MAP.md) → [`docs/agent-stubs/<topic>.md`](docs/agent-stubs/) → feature doc under `docs/` → `Packages/OsaurusCore/` code.
- **Docs table of contents:** [`docs/INDEX.md`](docs/INDEX.md).
- Build, test, lint, and architecture rules: **[CLAUDE.md](CLAUDE.md)** only (do not duplicate long sections here). If that link breaks CI, see [docs/DOC_LINKS_AND_CI.md](docs/DOC_LINKS_AND_CI.md) until `CLAUDE.md` is committed.

## Learned Workspace Facts

- This checkout is a personal fork of `osaurus-ai/osaurus`: use `origin` for pushes and fork PRs; use `upstream` only to fetch and merge or cherry-pick into local branches.
- Do not suggest opening PRs to `osaurus-ai/osaurus`, pushing to that remote, or changing the parent repo unless the user explicitly asks; see `.cursor/rules/personal-fork.mdc` and `CLAUDE.md` (Personal fork and upstream).
- Longer fork workflow, Sparkle, `~/.osaurus` layout, and local install notes: [`docs/personal_fork_local_documents/PERSONAL_FORK_AND_LOCAL_SETUP.md`](docs/personal_fork_local_documents/PERSONAL_FORK_AND_LOCAL_SETUP.md).
