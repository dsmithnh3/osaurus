# Project Management for Projects Mode — Design Spec

**Date:** 2026-04-11
**Status:** Draft
**Author:** Daniel Smith + Codex

## Overview

Complete the missing project-management surface for Projects mode so users can reliably create, edit, archive, unarchive, and delete projects using a native macOS interaction model. The design preserves the current project inspector exactly as it is today, adds row-level context menus for project management, and promotes the existing `ProjectEditorSheet` into the canonical settings surface for both new and existing projects.

## Goals

- Keep the right project inspector unchanged
- Add native-feeling row-level project management via context menus
- Reuse `ProjectEditorSheet` as the single metadata and settings surface
- Make archive reversible and operationally meaningful
- Make delete safe by default and explicit about scope
- Keep the default quick-access surfaces focused on active projects
- Fit the current `ProjectManager` / `ProjectListView` / sidebar structure with minimal conceptual churn

## Non-Goals

- Changing the project inspector layout or responsibilities
- Adding a second toolbar or header management path
- Implementing project-memory deletion
- Implementing full project-data purge in the first pass
- Adding project templates, import/export, reorder controls, or bulk actions

## Current State

The current codebase has a partial foundation for project management but does not expose a complete user-facing workflow.

### What Already Exists

- `Project` model with `isActive` and `isArchived`
- `ProjectStore` JSON persistence under `~/.osaurus/projects/`
- `ProjectManager.createProject`, `updateProject`, `archiveProject`, and `deleteProject`
- `ProjectEditorSheet` that already supports both `new` and `existingProject` modes
- `ProjectInspectorPanel` with inline editing for `instructions`
- `ProjectListView` for project browsing and new-project creation

### What Is Missing or Incomplete

- No UI entry point for editing existing project metadata
- No UI entry point for archive / unarchive
- No UI entry point for delete
- No archived-project browsing flow
- No coordinated handling for what should happen in window state when an open project is archived or deleted
- Documentation/spec drift describing management affordances that are not actually implemented

## Design Decisions

### 1. Inspector Remains Unchanged

The right inspector panel stays exactly as it is. It continues to focus on:

- Instructions
- Scheduled
- Outputs
- Context
- Memory

No project archive, delete, or metadata-management controls are added to the inspector.

Rationale:

- The current inspector is already positioned as an in-project context surface
- Adding management controls there would mix context viewing with object administration
- The user explicitly wants to preserve the inspector as-is

### 2. Context Menus Are the Primary Management Entry Point

Project rows should gain native macOS-style context menus in both places where users already interact with projects:

- Sidebar active-project rows
- `ProjectListView` project rows

These context menus become the only management entry path from project rows. No duplicate toolbar or header action path is added.

#### Active Project Menu

- `Open`
- `Edit Settings…`
- separator
- `Archive`
- separator
- `Delete…`

#### Archived Project Menu

- `Open`
- `Edit Settings…`
- separator
- `Unarchive`
- separator
- `Delete…`

Normal click still opens the project. The context menu is for row-scoped object actions.

### 3. `ProjectEditorSheet` Becomes the Canonical Settings Surface

`ProjectEditorSheet` is reused rather than introducing a new settings UI.

#### New Project Mode

Continues to support:

- Name
- Description
- Folder selection
- Existing creation flow

#### Existing Project Mode

Becomes `Project Settings` and supports:

- Editing metadata
- Viewing current archive state
- Existing-project-only lifecycle actions

The sheet is opened from `Edit Settings…` in the project row context menu.

### 4. Archived Projects Are Hidden from Quick-Access Surfaces

Archived projects are removed from default active lists.

#### Sidebar

- Shows active projects only
- No archived section

#### `ProjectListView`

- Becomes the only browsing surface for archived projects
- Adds a simple `Active | Archived` filter or equivalent toggle

Rationale:

- The sidebar is optimized for current work, not storage browsing
- `ProjectManager.activeProjects` already matches this behavior
- This keeps archive semantically strong and reduces visual noise

### 5. Archive Semantics

Archive is reversible and non-destructive.

Archiving a project should:

- Mark the project as archived and inactive
- Remove it from active lists
- Move it into the archived view in `ProjectListView`
- Pause project-owned automations such as watchers and schedules
- Preserve chats, work tasks, artifacts, folder linkage, and project memory

Unarchive should:

- Return the project to active lists
- Clear its archived state
- Make it available for normal selection again

The implementation plan can decide whether paused automations are automatically resumed or restored in a disabled-but-restorable state, but archive must be operationally meaningful rather than cosmetic.

### 6. Delete Semantics

Delete is safe by default and split into two layers.

#### Context Menu Delete

Choosing `Delete…` from the project row context menu should open a native confirmation flow for a safe deletion path.

Safe deletion removes:

- The project record itself
- Active project selection / stale UI references tied to that project

Safe deletion does **not** touch:

- The linked folder on disk
- Project memory

#### Deeper Cleanup

If later desired, deeper project-data cleanup belongs in the settings sheet as a separate, more explicit destructive path. It is out of scope for this first pass.

### 7. Memory Is Left Alone

Project lifecycle actions do not modify memory in this scope.

#### Archive

- Leaves memory unchanged

#### Safe Delete

- Leaves memory unchanged

Rationale:

- Project-scoped memory exists across entries, summaries, conversations/chunks, and pending signals
- Retrieval uses project-plus-global union semantics
- The knowledge graph remains intentionally global
- A comprehensive “delete all project memory” feature would be only partial unless graph provenance and graph deletion are redesigned

This makes memory cleanup a separate future feature, not part of project management completion.

## UX Structure

### Sidebar

The sidebar remains a quick-access surface for active projects only.

Changes:

- Add project-row context menus
- Keep existing open-on-click behavior
- Do not add archived browsing here

### Project List

`ProjectListView` remains the broader management surface.

Changes:

- Add `Active | Archived` filter
- Show active projects by default
- Show archived projects only when explicitly filtered
- Add project-row context menus
- Continue to support `New Project`

### Project Settings Sheet

`ProjectEditorSheet` is the canonical editor for project metadata and settings.

Changes for existing-project mode:

- Rename title from generic edit wording to `Project Settings` if desired
- Show metadata fields for the existing project
- Show archive/unarchive state-aware action(s)
- Show delete affordance(s) in a clearly separated destructive section

### Inspector

No changes.

## Architecture

### `ProjectManager`

`ProjectManager` remains the lifecycle owner and should own the authoritative behaviors for:

- `archiveProject`
- `unarchiveProject`
- safe delete semantics
- possibly higher-level coordination helpers for active-project invalidation

Persistence stays in `ProjectStore`. UI policy does not move into the model layer.

### `ProjectEditorSheet`

`ProjectEditorSheet` should become a well-defined mode-driven sheet:

- `new`
- `existing`

The implementation can express this through `existingProject`, an explicit mode enum, or a small view model. The key requirement is that one sheet handles both creation and settings.

### `ProjectListView`

`ProjectListView` gains:

- archive-state filtering
- context menu hooks
- archived-project rendering

It should continue using `ProjectManager` data rather than taking on persistence logic.

### Sidebar Project Rows

The sidebar project rows should gain context menus but keep their current role:

- active projects only
- quick open
- no archived browsing

### `ChatWindowState`

Window state must handle lifecycle transitions safely.

Cases to handle:

- Active/open project is archived
- Active/open project is deleted
- A settings sheet is open while the project changes state

The expected behavior is graceful state reconciliation, not stale references.

## Edge Cases

### Archiving the Open Project

If the currently open project is archived:

- The app should not remain in a confusing “open but hidden from lists” state
- Window state should reconcile to a predictable non-active-project state or equivalent safe fallback

### Deleting the Open Project

If the currently open project is deleted:

- Clear active project state
- Dismiss settings UI tied to that project
- Avoid stale navigation/session references

### Archived Project Opening

Archived projects may still be opened intentionally from the archived list, but they should remain absent from active quick-access lists until unarchived.

### Linked Folder Safety

No delete flow in this scope should ever remove the linked folder or its contents from disk.

## Testing Strategy

### Manager-Level Tests

Add or extend tests for:

- archive transition
- unarchive transition
- safe delete behavior
- active-project reconciliation

### Window-State Tests

Verify behavior when:

- the currently open project is archived
- the currently open project is deleted

### View / UI Behavior Tests

Cover:

- `ProjectEditorSheet` in new-project mode
- `ProjectEditorSheet` in existing-project mode
- `ProjectListView` active/archived filtering
- context-menu action routing

### Safety Tests

Explicitly verify:

- safe delete does not touch the linked folder
- archive preserves project data and memory
- active lists exclude archived projects

## Documentation Follow-Up

After implementation, update the relevant project docs to match the real shipped behavior. The current docs/specs describe some project-management affordances that are not present in the implementation, so doc alignment should be part of the implementation plan.

## Recommendation

Implement project management using a context-menu-first macOS pattern, keep the inspector unchanged, reuse `ProjectEditorSheet` as the canonical settings surface, hide archived projects from quick-access surfaces, and leave memory untouched in this scope.
