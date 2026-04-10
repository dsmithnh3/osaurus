# Documentation integrity automation — Design spec

**Status:** Approved (approach: **CI + matching local hook**)  
**Decision tier:** **B (mixed)** — block merge on **deterministic** failures; **AI** used for authoring/review **outside** the required merge gate (optional advisory GitHub job deferred).

## Problem

Navigation docs (`docs/DEVELOPER_MAP.md`, `docs/INDEX.md`, `docs/agent-stubs/*.md`, `AGENTS.md`, contributor links) can drift from the codebase after refactors or AI-assisted edits. **Subjective** “perfect accuracy” is not machine-verifiable; **objective** breakages (dead relative links, referenced repo paths that no longer exist) are.

## Goal

1. **Fail PRs** when **verifiable** doc integrity checks fail (mixed approach **B**, blocking layer).
2. Run the **same checks locally** before push via **lefthook**, mirroring CI (recommended **Approach 2**).
3. Keep **`CLAUDE.md`** as the single canonical contract for commands/architecture—automation validates links/paths, **not** full semantic correctness of prose.
4. Reserve **LLM-on-GitHub** merge gates for a **future optional** advisory workflow (out of scope for v1 required checks).

## Principles

- **Blocking:** relative link resolution under `docs/` (and scoped root files if included). Optional **narrow** path-existence validation for `Packages/OsaurusCore/...` references in controlled files.
- **Non-blocking:** second-pass **reviewer agent** in Cursor; optional `workflow_dispatch` comment job later.
- **Fork-local:** workflows are for **this fork**; upstream adoption is not assumed.
- **No DocC**; no CI job that rewrites stub **meaning**.

## Components

### 1. GitHub Actions — docs integrity workflow

- **Workflow file (suggested):** `.github/workflows/docs-integrity.yml` — enables a single discoverable name for branch protection.
- **Job id (suggested):** `verify-docs` — use this id when marking the check as **required** on the fork.
- **Trigger:** `pull_request` (and optionally `push` to `main` if desired for consistency).
- **Path filter (recommended):** run when PR changes `docs/**`, `AGENTS.md`, `README.md`, `scripts/verify-doc-paths.*`, or `.github/workflows/docs-integrity.yml`—or run on every PR if execution time stays low.
- **Steps (v1):**
  1. Checkout
  2. **Markdown link check — v1 scope:** **required** pass validates **relative** links for all `docs/**/*.md` (and `docs/index` if not only `.md`). **Optional v1 extension:** `AGENTS.md` relative links only; **exclude or soft-ignore** `README.md` in the blocking pass if it contains many `https://` targets that would flake—otherwise add a dedicated ignore config. Defer aggressive external URL enforcement until config is stable.
  3. **Path validator script** (committed to repo, e.g. `scripts/verify-doc-paths.py`): reads allowlisted files (`docs/DEVELOPER_MAP.md`, `docs/agent-stubs/*.md` in v1), extracts **constrained** patterns (e.g. backtick-wrapped segments starting with `Packages/OsaurusCore/`), resolves relative to repo root, fails if path missing. Document patterns and **intentional non-path** literals in the script header; edge cases (examples, placeholders) are handled in implementation with tests or allowlist—implementation plan owns detail.
- **Required check:** in fork **Settings → Branches**, require status check named per GitHub’s listing for this workflow/job (typically `verify-docs` or `docs-integrity / verify-docs`—confirm after first run).

### CI ↔ local parity

- One **script entrypoint** (e.g. `scripts/verify-docs.sh`) invoked by **both** GitHub Actions and **lefthook**, which in turn calls the link tool with a **committed config file** (e.g. `.markdown-link-check.json` or `lychee.toml`) and the path validator. **Pin tool versions** in workflow (and document `brew`/`npm` install for local). Avoid “similar” checks that diverge in ignores or base path.

### 2. Local hook — lefthook

- Add **`pre-push`** job invoking **`scripts/verify-docs.sh`** (same as CI).
- **When to run:** if the commits being pushed **touch any** of `docs/**`, `AGENTS.md`, `README.md`, `scripts/verify-doc-paths.*`, `scripts/verify-docs.sh`, or link-check config—**mirror the CI path filter** so hook and CI always run together on the same change set. If filtering is awkward in lefthook, running the script on every push is acceptable when total runtime stays **under ~30s**.
- **Failure message:** reference `.github/workflows/docs-integrity.yml` and the shared script path.

### 3. PR template

- Extend **`.github/pull_request_template.md`** with **Doc navigation** checkboxes:
  - Structural changes under `Packages/OsaurusCore/` → `DEVELOPER_MAP.md` + relevant `docs/agent-stubs/*.md` updated (**or N/A**).
  - New top-level `docs/*.md` → `docs/INDEX.md` updated (**or N/A**).
  - Command/architecture changes → `CLAUDE.md` updated (**or N/A**).
- Checkboxes are **human/AI discipline**, not enforced by CI.

### 4. Advisory — AI (Cursor)

- **Author agent:** same-PR updates when directories move.
- **Reviewer agent:** separate session; must cite **files and paths** for any inconsistency.
- **Not a v1 required check** on GitHub.

## Non-goals (v1)

- Required LLM GitHub Action merge gate
- Auto-fix of stub semantics in CI
- Full-repo link crawl of external documentation sites (unless explicitly configured later)
- Validating every English mention of a path—only **pattern-scoped** extraction

## Risks and mitigations

| Risk                            | Mitigation                                                                                    |
| ------------------------------- | --------------------------------------------------------------------------------------------- |
| False positives from path regex | Start narrow (backtick-wrapped `Packages/OsaurusCore/...` only); expand in follow-ups.        |
| Flaky external URL checks       | Restrict blocking pass to **relative** links under `docs/`; tune config for root `README.md`. |
| Drift between local hook and CI | Single shared script invoked by both; document in script + workflow.                          |
| Contributors without lefthook   | CI remains authoritative; local hook is best-effort.                                          |

## Success criteria

- A PR that **breaks a relative link** in `docs/` or **references a removed** `Packages/OsaurusCore/` path in allowlisted files **fails** the docs job.
- A PR that only changes unrelated Swift **does not** pay heavy doc tooling cost if **path filtering** is implemented.
- Running the **same** verifier locally (lefthook) reproduces CI failures before push for typical doc edits.
- **Interpretation:** green CI means **modeled mechanical consistency**, not that narrative docs are semantically perfect or that `CLAUDE.md` prose is fully audited—only what this spec’s checks encode.

## Implementation note

Follow-up **implementation plan** under `docs/superpowers/plans/` will specify exact tool versions, workflow file name, lefthook YAML, script location, and branch-protection notes—**not** part of this spec.
