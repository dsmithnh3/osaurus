# Personal fork and local Osaurus setup

This guide consolidates **git fork workflow**, **repository conventions** (for humans and coding agents), and **macOS install layout** so you can customize Osaurus locally without affecting the upstream project or other users’ machines.

**Freshness:** Git state and app versions change over time. Re-verify with the commands in [Verification commands](#15-verification-commands). Snapshot details below reflect a point-in-time survey (e.g. app **0.16.9**, data root **`~/.osaurus` ~1.1 GiB**).

---

## Table of contents

1. [Goals and boundaries](#1-goals-and-boundaries)
2. [Fork and Git remotes](#2-fork-and-git-remotes)
3. [Syncing upstream safely](#3-syncing-upstream-safely)
4. [What does not affect upstream or other users](#4-what-does-not-affect-upstream-or-other-users)
5. [Documentation and agent rules in this repo](#5-documentation-and-agent-rules-in-this-repo)
6. [Which AI tools see which files](#6-which-ai-tools-see-which-files)
7. [Official app bundle (release install)](#7-official-app-bundle-release-install)
8. [CLI (`osaurus`) and how it ties to the app](#8-cli-osaurus-and-how-it-ties-to-the-app)
9. [User data: `~/.osaurus/` reference](#9-user-data-osaurus-reference)
10. [Other paths: Xcode, repo, Library](#10-other-paths-xcode-repo-library)
11. [Strategies: keep official build, dev build, or both](#11-strategies-keep-official-build-dev-build-or-both)
12. [Sparkle (auto-updates) and custom builds](#12-sparkle-auto-updates-and-custom-builds)
13. [GitHub Actions on a fork](#13-github-actions-on-a-fork)
14. [Backups and recovery](#14-backups-and-recovery)
15. [Verification commands](#15-verification-commands)

---

## 1. Goals and boundaries

| Goal                                                                       | Approach                                                                              |
| -------------------------------------------------------------------------- | ------------------------------------------------------------------------------------- |
| Own a **long-lived customized** line of Osaurus                            | Work on **`origin`** (your fork). Merge **from** `upstream` when you choose.          |
| **No obligation** to contribute to `osaurus-ai/osaurus`                    | Do not open PRs there unless you intend to.                                           |
| **Pull selected improvements** from the parent project                     | `git fetch upstream` → merge `upstream/main` or cherry-pick commits.                  |
| **Run an official release** on your Mac while hacking in a **local clone** | Keep `/Applications/osaurus.app`; clone lives elsewhere (e.g. `~/Documents/osaurus`). |

Boundary: **Your pushes go only to remotes you configure.** The parent repository and strangers’ Macs do not receive your local commits, builds, or `~/.osaurus` data.

---

## 2. Fork and Git remotes

### Recommended layout

| Remote         | Typical URL / role                                                                                               |
| -------------- | ---------------------------------------------------------------------------------------------------------------- |
| **`origin`**   | Your fork on GitHub (`git@github.com:<you>/osaurus.git` or HTTPS equivalent). **Push** target for your branches. |
| **`upstream`** | `https://github.com/osaurus-ai/osaurus.git` (**fetch** only). Canonical source for upstream `main` and tags.     |

Add upstream once:

```bash
git remote add upstream https://github.com/osaurus-ai/osaurus.git
git fetch upstream
```

Never rely on pushing to `upstream` for day-to-day work; you will not have permission, and you should not need it for a personal fork.

### Useful local branches

- **`main` (or your default integration branch)** — Your product branch: upstream merges + your commits land here.
- **Optional read-only tracker** — Points at upstream’s `main` without merging:

  ```bash
  git fetch upstream
  git branch -f upstream-tracker upstream/main
  ```

  Use for diffs: `git log main..upstream-tracker` / `git diff main upstream-tracker`.

### Example fork state (illustrative)

At one point in time, a fork’s **`main`** was **aligned with `upstream/main` on the remote**, while **additional local-only commits** (e.g. docs) could exist **only on the laptop until pushed**. Feature work might live on **`feat/...`** branches with PRs **to your fork**, not to `osaurus-ai`. Exact counts change — use [Verification commands](#15-verification-commands).

---

## 3. Syncing upstream safely

### Full merge (most common)

After `git fetch upstream`:

```bash
git checkout main
git merge upstream/main
# Resolve conflicts on *your* branch; build and test
git push origin main
```

### Selective import

Cherry-pick specific commits from `upstream/main` when you do not want the entire branch:

```bash
git fetch upstream
git cherry-pick <commit-sha>
```

### Rebase (optional)

You may rebase your commits on top of `upstream/main` for a linear history. This **rewrites** your branch history — acceptable for a **personal** fork; coordinate if you share branches with others.

### Pull requests

- **To your fork:** Normal for organizing your own work.
- **To `osaurus-ai/osaurus`:** Only when you **choose** to contribute; that is the only path by which your changes enter the parent **repo** (after maintainers merge).

---

## 4. What does not affect upstream or other users

| Action                                         | Effect on upstream repo | Effect on others’ installed apps                     |
| ---------------------------------------------- | ----------------------- | ---------------------------------------------------- |
| `git push origin`                              | None on parent          | N/A                                                  |
| Local Xcode builds                             | None                    | None                                                 |
| Replacing **your** `/Applications/osaurus.app` | None                    | None                                                 |
| Contents of **`~/.osaurus`**                   | None                    | None; others use **their** disks and update channels |
| Running **Upstream check** workflow (see §13)  | None                    | None                                                 |

Others’ apps update only via **their** distribution channel (e.g. official **Sparkle** appcast and signed builds from the publisher).

---

## 5. Documentation and agent rules in this repo

This fork may include project-specific guidance:

| Artifact                                   | Purpose                                                                                                                                                                                                                                     |
| ------------------------------------------ | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| **`CLAUDE.md`** (repo root)                | Project instructions for **Claude Code** and humans: full **Personal fork and upstream** section with merge commands, cherry-pick note, optional tracker branch, Actions note, and agent guidance (do not target parent repo unless asked). |
| **`.cursor/rules/personal-fork.mdc`**      | **Cursor** rule (`alwaysApply: true`): reinforces fork policy and points to `CLAUDE.md` for detail.                                                                                                                                         |
| **`.github/workflows/upstream-check.yml`** | **Manual** GitHub Action: summarizes commits reachable from `upstream/main` but not current `HEAD` (no auto-merge).                                                                                                                         |

If you contribute a subset of files **upstream** later, consider trimming fork-only sections or rules so maintainers are not confused.

---

## 6. Which AI tools see which files

| Tool                            | Typical behavior                                                                                                                                                             |
| ------------------------------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| **Cursor**                      | Loads **`.cursor/rules/*.mdc`** per rule settings; may load workspace docs depending on configuration. **Does not** universally load `CLAUDE.md` unless included in context. |
| **Claude Code**                 | Commonly loads repo **`CLAUDE.md`** when working in the project.                                                                                                             |
| **Other assistants / web chat** | Only what you paste or attach; **no automatic** read of `CLAUDE.md` or `.cursor/rules`.                                                                                      |

**Implication:** Keep the **canonical narrative in `CLAUDE.md`**; use **`.cursor/rules`** for short, enforceable Cursor behavior. Neither file reaches “all LLMs everywhere.”

---

## 7. Official app bundle (release install)

Typical **release** layout on Apple Silicon (exact version changes with each release):

| Property                       | Typical / surveyed value                             |
| ------------------------------ | ---------------------------------------------------- |
| **Install location**           | `/Applications/osaurus.app`                          |
| **Bundle identifier**          | `com.dinoki.osaurus`                                 |
| **Sparkle feed (`SUFeedURL`)** | `https://osaurus-ai.github.io/osaurus/appcast.xml`   |
| **Executable**                 | `/Applications/osaurus.app/Contents/MacOS/osaurus`   |
| **Bundled CLI helper**         | `/Applications/osaurus.app/Contents/Helpers/osaurus` |

Read the installed metadata:

```bash
/usr/libexec/PlistBuddy -c 'Print CFBundleIdentifier' /Applications/osaurus.app/Contents/Info.plist
/usr/libexec/PlistBuddy -c 'Print CFBundleShortVersionString' /Applications/osaurus.app/Contents/Info.plist
/usr/libexec/PlistBuddy -c 'Print SUFeedURL' /Applications/osaurus.app/Contents/Info.plist
codesign -dv /Applications/osaurus.app
```

---

## 8. CLI (`osaurus`) and how it ties to the app

A common **Homebrew**-style setup:

```text
/opt/homebrew/bin/osaurus  →  symlink  →  /Applications/osaurus.app/Contents/Helpers/osaurus
```

So the CLI in your **`PATH`** runs the **helper inside whichever `.app` is currently in `/Applications`**. If you replace the app bundle, the same symlink usually remains valid.

Verify:

```bash
which osaurus
ls -la "$(which osaurus)"
```

---

## 9. User data: `~/.osaurus/` reference

Osaurus stores nearly all **persistent user and runtime state** under **`~/.osaurus/`** (see `Packages/OsaurusCore/Utils/OsaurusPaths.swift`). A **legacy** path was `~/Library/Application Support/com.dinoki.osaurus`; current code may **copy or merge** from there into `~/.osaurus` on first use if the legacy folder still exists.

### Top-level directories (typical roles)

| Path                                                                                         | Role                                                                                                   |
| -------------------------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------ |
| **`container/`**                                                                             | Sandbox VM / Linux container images and related assets (often the **largest** consumer of disk space). |
| **`Tools/`**                                                                                 | Installed **native plugin** binaries (by plugin id / version).                                         |
| **`PluginSpecs/`**                                                                           | Plugin specification / metadata.                                                                       |
| **`memory/`**                                                                                | Memory SQLite DB, vector index paths under configured subpaths.                                        |
| **`sessions/`**                                                                              | Chat session persistence.                                                                              |
| **`work/`**                                                                                  | Work-mode DB and related data.                                                                         |
| **`artifacts/`**                                                                             | Shared artifact storage.                                                                               |
| **`agents/`**, **`skills/`**, **`methods/`**, **`themes/`**, **`providers/`**, **`config/`** | Agent JSON, skills, methods DB, themes, provider configs, app config.                                  |
| **`projects/`**                                                                              | Project-scoped data when that feature is enabled.                                                      |
| **`cache/`**, **`tool-index/`**, **`runtime/`**                                              | Cache and ephemeral runtime state.                                                                     |
| **`schedules/`**, **`watchers/`**, **`slash-commands/`**, **`sandbox-plugins/`**             | Feature-specific dirs (may be empty until used).                                                       |

**Note:** Older documentation sometimes mentioned `~/osaurus/` for tools; current layout in code uses **`~/.osaurus/Tools/`**.

### Other macOS Library paths

| Path                                               | Role                                                       |
| -------------------------------------------------- | ---------------------------------------------------------- |
| **`~/Library/HTTPStorages/com.dinoki.osaurus`**    | URL session / HTTP cookie storage for the app’s bundle ID. |
| **`~/Library/Application Support/CrashReporter/`** | May contain crash reporter plists referencing the app.     |

---

## 10. Other paths: Xcode, repo, Library

| Path                                                  | Role                                                                                                                                |
| ----------------------------------------------------- | ----------------------------------------------------------------------------------------------------------------------------------- |
| **Git clone** (e.g. `~/Documents/osaurus`)            | **Source** — unrelated to the release app’s **binary**; this is where you branch, merge `upstream`, and build in Xcode.             |
| **`~/Library/Developer/Xcode/DerivedData/osaurus-*`** | **Local Debug/Release builds** from Xcode — **not** the same file as `/Applications/osaurus.app` until you copy or archive-install. |

Spotlight / `mdfind` may list the **repo**, **DerivedData**, **Applications** bundle, and **`~/.osaurus`** together; they serve different roles.

---

## 11. Strategies: keep official build, dev build, or both

### A. Keep official app + develop in repo (recommended baseline)

- **Use** `/Applications/osaurus.app` for daily **stable** runs and official Sparkle updates.
- **Use** Xcode (`osaurus.xcworkspace`) to **run Debug** builds when testing fork changes.
- **Data:** Both typically read **`~/.osaurus`**, so agents/memory/plugins stay consistent (back up before risky experiments).

### B. Replace `/Applications/osaurus.app` with your own Release build

- **Manual:** Archive in Xcode, export or copy **`Osaurus.app`** (or `osaurus.app` — match your scheme’s product name) into `/Applications`.
- **Effect:** **Local only**; same bundle ID continues to use **`~/.osaurus`**.
- **CLI:** Symlink under `/opt/homebrew/bin/osaurus` continues to target **`Contents/Helpers`** **inside the replaced bundle**.

### C. “Two apps” side by side

- Often done with a **different `CFBundleIdentifier` and display name** (e.g. “Osaurus Dev”) in a **custom** target or configuration.
- **Data caveat:** `OsaurusPaths` still defaults to **`~/.osaurus`** for the standard layout, so **two apps may still share the same data root** unless you introduce a dedicated override strategy (the codebase exposes test-oriented overrides; production isolation may require a deliberate fork change or separate OS user account).

---

## 12. Sparkle (auto-updates) and custom builds

- **Official** builds use **`https://osaurus-ai.github.io/osaurus/appcast.xml`** (verify in the installed `Info.plist`).
- Sparkle **only** offers updates the **publisher** signs and hosts; **your** fork does not change that feed for **other** users.
- If **your** locally built app still points at the **official** appcast and keys, Sparkle might offer to **replace** your custom build with an **official** one. For a personal dev build, teams often:
  - **Disable** automatic checks for dev schemes, or
  - Use a **private or dummy** feed URL + keys for dev-only builds, or
  - Rely on a **separate** bundle ID + app name to reduce confusion.

---

## 13. GitHub Actions on a fork

Forks often **inherit** workflows from the parent (e.g. CI on `push` / `pull_request`). You may:

- **Disable** or **limit** Actions under the fork’s GitHub **Settings → Actions** to save minutes or avoid noisy jobs.
- Use **`.github/workflows/upstream-check.yml`** (**workflow_dispatch**): run manually to list commits on **`upstream/main`** that are not in the checked-out ref; see the job summary in the Actions UI.

---

## 14. Backups and recovery

Before major merges, migrations, or experiments:

- Copy **`~/.osaurus`** (or at least `memory`, `agents`, `config`, `providers`, `sessions`) to an external drive or archive.
- Keep a copy of any **recovery / identity** material you rely on (e.g. screenshots or exports the app showed once).

Replacing the app bundle **does not** delete **`~/.osaurus`** by itself.

---

## 15. Verification commands

```bash
# Remotes
git remote -v

# Fork main vs upstream main (after: git fetch upstream)
git rev-list --left-right --count upstream/main...main
git log --oneline upstream/main..main   # yours not in upstream
git log --oneline main..upstream/main    # upstream not in yours

# Installed app
ls -la /Applications/osaurus.app
/usr/libexec/PlistBuddy -c 'Print CFBundleShortVersionString' /Applications/osaurus.app/Contents/Info.plist

# CLI
which osaurus
ls -la "$(which osaurus)"

# Data root size and top-level
du -sh ~/.osaurus
ls -1 ~/.osaurus
```

---

## Related documents

- **`CLAUDE.md`** — Build, test, architecture, and **Personal fork and upstream** (kept in sync with this guide at a high level).
- **`docs/CONTRIBUTING.md`** — Upstream contribution expectations (if you ever contribute back).
- **`Packages/OsaurusCore/Utils/OsaurusPaths.swift`** — Authoritative path constants for user data.

---

_This document is maintained for the **personal fork / local dev** workflow. Update it when remotes, bundle IDs, or data layout change materially._
