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

### 1. GitHub Actions — `docs` integrity job

- **Trigger:** `pull_request` (and optionally `push` to `main` if desired for consistency).
- **Path filter (recommended):** run when PR changes `docs/**`, `AGENTS.md`, `README.md`, or `.github/workflows/*docs*` / scripts used by the job—or run on every PR if the job stays fast enough.
- **Steps (v1):**
  1. Checkout
  2. **Markdown relative link check** for `docs/` (implementation picks tool: e.g. `markdown-link-check`, `lychee`, or equivalent; prefer **configurable** ignores for flaky external URLs if any root README links are checked)
  3. **Path validator script** (small shell or Python committed to repo, e.g. `scripts/verify-doc-paths.sh` or `.py`): reads allowlisted files (`docs/DEVELOPER_MAP.md`, `docs/agent-stubs/*.md` initially), extracts **constrained** patterns (e.g. paths in backticks starting with `Packages/OsaurusCore/`), resolves relative to repo root, fails if file or directory missing. **Scope v1 narrowly** to reduce false positives; document allowed patterns in script header.
- **Required check:** enable in **fork** branch protection if merge-blocking behavior is desired.

### 2. Local hook — lefthook

- Add **`pre-push`** (or **`pre-commit`**) job that runs the **same** path validator and, where practical, the **same** link check as CI.
- **Condition:** when staged/changed files intersect `docs/**`, `AGENTS.md`, `README.md`, or always run if cheap—implementation chooses; spec prefers **intersection** with `docs/**` and map/stubs to keep pushes fast.
- **Failure message:** point to `CLAUDE.md` / `CONTRIBUTING.md` and the workflow name so developers know how to fix.

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

## Implementation note

Follow-up **implementation plan** under `docs/superpowers/plans/` will specify exact tool versions, workflow file name, lefthook YAML, script location, and branch-protection notes—**not** part of this spec.
