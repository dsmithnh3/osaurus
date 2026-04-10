# Documentation links and CI (read this if `verify-docs` fails)

Several guides use **clickable Markdown links** to:

- **[`CLAUDE.md`](../CLAUDE.md)** at the repository root (canonical build, architecture, data paths)
- **Fork-local** pages under [`personal_fork_local_documents/`](personal_fork_local_documents/) (e.g. [Opal port roadmap](personal_fork_local_documents/OPAL_PORT_ROADMAP.md), [Xcode preview catalog](personal_fork_local_documents/xcode-preview-catalog.md))

`markdown-link-check` (see **`scripts/verify-docs.sh`** and the **Docs integrity** GitHub workflow) treats each relative link as **“this file must exist in the tree being checked.”**

- **Locally:** if `CLAUDE.md` or fork-local files exist on disk (even **untracked**), `bash scripts/verify-docs.sh` can still pass.
- **CI / clean clones:** if those files are **not committed**, link checks will report **dead links** until you add them to git.

**What to do:** commit `CLAUDE.md` and any fork-local `.md` files you want linked from [INDEX.md](INDEX.md) when you are ready; then push. Until then, expect CI to fail on **Docs integrity** if those targets are missing—a tradeoff for keeping navigation links in the docs.

See also: [DEVELOPER_MAP.md](DEVELOPER_MAP.md), [spec on doc automation](superpowers/specs/2026-04-11-doc-integrity-automation-design.md).
