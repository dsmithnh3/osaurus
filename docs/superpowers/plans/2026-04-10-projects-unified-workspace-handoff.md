# Projects Unified Workspace — Implementation Handoff

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking. Use the brainstorming skill first to create a detailed implementation plan from this handoff document.

## What You're Building

Rework the Osaurus Projects tab from a landing-page-with-inline-views approach to a **unified workspace** where selecting a project immediately shows chat or work content — identical to the standalone Chat and Work tabs. No gate, no landing page, no placeholders.

**Branch:** `feat/projects-first-class`
**Design spec:** `docs/superpowers/specs/2026-04-10-projects-unified-workspace-design.md` — READ THIS FIRST, it is the source of truth.

## Current State of the Branch

The branch has 34+ commits of prior work. Here's what exists and must be understood before you start:

### What Was Already Built (and will be partially reworked)

1. **Toolbar centering** — `toolbar.centeredItemIdentifiers` in `ChatWindowManager.swift` (~line 487). Working correctly. Do not touch.

2. **Inspector button** — rightmost toolbar item, gated by `.project` mode. Working correctly. Do not touch.

3. **AppSidebar** (`Views/Sidebar/AppSidebar.swift`) — unified sidebar with: `SidebarContainer` wrapping, New Chat button, `SidebarSearchField`, Projects section (collapsible with `ProjectSidebarRow`), draggable divider (persisted via `@AppStorage`), Recents section (collapsible). Has `visibleSessions` computed property (line 212) that filters by project + search. **NEEDS REWORK:** Replace `RecentRow` (line 304, simplified stub) with shared `SessionRow`/`TaskRow` via `ProjectRecentItem` enum. Add work task querying.

4. **ProjectView** (`Views/Projects/ProjectView.swift`) — 3-panel coordinator with embedded `AppSidebar`, `ThemedBackgroundLayer`, inspector overlay. Currently routes center content through `inlineSessionId`/`inlineWorkTaskId` state machine. **NEEDS REWRITE:** Remove inline routing, render chat or work content directly based on `projectSession.subMode`.

5. **ProjectHomeView** (`Views/Projects/ProjectHomeView.swift`) — landing page with empty Outputs/Recents, Chat/Work mode picker with `matchedGeometryEffect`, `FloatingInputCard`. **DELETE THIS FILE.** Move the Chat/Work picker concept to ProjectView.

6. **ProjectInlineChatView** (`Views/Projects/ProjectInlineChatView.swift`) — full chat content replicating ChatView. **DELETE THIS FILE.** ProjectView will compose the same building blocks directly.

7. **ProjectInlineWorkView** (`Views/Projects/ProjectInlineWorkView.swift`) — full work content replicating WorkView, with duplicated private views. **DELETE THIS FILE.** ProjectView will use shared extracted components.

8. **ProjectInspectorPanel** (`Views/Projects/ProjectInspectorPanel.swift`) — right panel with Instructions, Scheduled, Context (FolderTreeView), Memory sections. **NEEDS MODIFICATION:** Add Outputs section above Context.

9. **ChatSession.projectId** (`Views/Chat/ChatView.swift` line 46) — already wired into `toSessionData()`, `load(from:)`, `reset()`. Working correctly. Do not touch.

10. **Project-scoped memory** — fully implemented per `docs/superpowers/specs/2026-04-10-project-scoped-memory-design.md`. Do not touch.

### Key Architecture You Must Understand

**Routing:** `ChatView.body` (line 1298) routes by mode:
```
sidebarContentMode == .projects → ProjectListView
sidebarContentMode == .scheduled → Text("Scheduled tasks") [TODO]
mode == .project && projectSession != nil → ProjectView
mode == .work && workSession != nil → WorkView
else → chatModeContent
```
This routing is NOT changed — `ProjectView` remains the entry point for project mode.

**State:** `ChatWindowState` (line 32) has:
- `ProjectSession` struct — currently has `activeProjectId`, `inlineSessionId`, `inlineWorkTaskId`, `hasInlineContent`. **Simplify to:** `activeProjectId` + `subMode: ProjectSubMode`
- `NavigationEntry` struct (line 49) — currently has `mode`, `projectId`, `sessionId`, `workTaskId`. **Simplify to:** remove `workTaskId`
- `switchMode(to:)` (line 298) — handles tool registration/session creation per mode

**Sidebar embedding pattern:** All three modes use the same `GeometryReader` + `HStack` pattern:
```swift
GeometryReader { proxy in
    HStack(alignment: .top, spacing: 0) {
        if showSidebar { sidebar }
        ZStack { background; content }
            .frame(width: proxy.size.width - sidebarWidth)
    }
}
```
ChatView uses this in `chatModeContent`. WorkView uses this in its `body`. ProjectView uses this in its `body`. The pattern must be preserved.

**Chat empty state:** `ChatView` shows an agent greeting (globe icon, "Good evening", "How can I help you today?", agent name, quick action chips). This is rendered by a component in the `chatModeContent` path. Study how ChatView renders this when `session.turns.isEmpty` and replicate the exact same empty state in ProjectView's chat sub-mode.

**Work empty state:** `WorkView` shows a `WorkEmptyState` view (globe icon, "Work", "Describe what you need.", agent name, work quick action chips). Study `WorkView`'s routing when `session.currentTask == nil` and replicate the exact same empty state in ProjectView's work sub-mode.

## Critical Gap: WorkDatabase Schema

**`IssueStore.listTasks`** (in `Storage/IssueStore.swift`, line 558) has NO `projectId` parameter. The `tasks` table in `WorkDatabase` has NO `project_id` column. `WorkTask` model has `projectId: UUID?` but it's never persisted to the database.

**You must add:**
1. A schema v6 migration adding `project_id TEXT` to the `tasks` table
2. Update `IssueStore.createTask` / `IssueStore.updateTask` to write `project_id`
3. Add `IssueStore.listTasks(projectId:)` parameter (or overload)
4. Update `WorkTask` serialization to/from the database to include `project_id`
5. When creating a work task from project mode, set `projectId = activeProjectId`

Without this, the unified recents sidebar cannot show work tasks filtered by project.

## Implementation Tasks

### Task 1: Simplify State Model

**Files:** `Managers/Chat/ChatWindowState.swift`

- Replace `ProjectSession` struct (line 32):
  ```swift
  public struct ProjectSession: Equatable, Sendable {
      public var activeProjectId: UUID?
      public var subMode: ProjectSubMode = .chat
  }
  public enum ProjectSubMode: String, Codable, Sendable {
      case chat
      case work
  }
  ```
- Remove `inlineSessionId`, `inlineWorkTaskId`, `hasInlineContent`
- Remove `workTaskId` from `NavigationEntry` (line 49)
- Update `switchMode(to: .project)` (line 298) to handle `subMode`:
  - If `.work`: register work tools, create `WorkSession` if nil
  - If `.chat`: unregister work tools (but preserve `WorkSession`)
- Update `restoreNavigationEntry` — remove `workTaskId` handling, simplify to sub-mode logic

### Task 2: WorkDatabase Schema Migration

**Files:** `Storage/WorkDatabase.swift`, `Storage/IssueStore.swift`

- Add v6 migration: `ALTER TABLE tasks ADD COLUMN project_id TEXT`
- Update `IssueStore.createTask` to write `project_id`
- Update `IssueStore.listTasks` to accept optional `projectId` parameter with filter
- Update `WorkTask` database read/write to include `project_id`
- Test: create a task with projectId, query by projectId, verify round-trip

### Task 3: Extract Shared Components

**From `ChatSessionSidebar.swift` (line 177):**
- Move `SessionRow` to `Views/Sidebar/SessionRow.swift`, change `private` to `internal`
- `SessionRow` init params: `session: ChatSessionData`, `agent: Agent?`, `isSelected: Bool`, `isEditing: Bool`, `editingTitle: Binding<String>`, `onSelect`, `onStartRename`, `onConfirmRename`, `onCancelRename`, `onDelete`, `onOpenInNewWindow: (() -> Void)?`
- Update `ChatSessionSidebar` to import and use the shared version
- Verify standalone Chat tab still works identically

**From `WorkTaskSidebar.swift` (line 139):**
- Move `TaskRow` to `Views/Sidebar/TaskRow.swift`, change `private` to `internal`
- `TaskRow` init params: `task: WorkTask`, `isSelected: Bool`, `isHovered: Bool`, `onSelect`, `onDelete`
- Update `WorkTaskSidebar` to import and use the shared version
- Verify standalone Work tab still works identically

**From `WorkView.swift`:**
- `ClarificationOverlay` (line 313, 24 lines) → `Views/Common/ClarificationOverlay.swift`
- `WorkStatusButton` (line 340, 102 lines) → `Views/Common/WorkStatusButton.swift`
- `WorkPulseModifier` (line 1825, 16 lines) → `Views/Common/WorkPulseModifier.swift`
- All change from `private` to `internal`
- Update `WorkView` to import and use the shared versions
- Verify standalone Work tab still works identically

### Task 4: Rewrite ProjectView

**File:** `Views/Projects/ProjectView.swift`

Rewrite the center content routing:
- Remove all `inlineSessionId`/`inlineWorkTaskId` references
- Route based on `session.subMode` (.chat or .work)
- Chat sub-mode: compose `MessageThreadView`, `FloatingInputCard`, `ScrollToBottomButton`, chat empty state — using `windowState.session`
- Work sub-mode: compose `WorkEmptyState`, `MessageThreadView`, `FloatingInputCard`, `IssueTrackerPanel`, `WorkStatusButton`, `ClarificationOverlay` — using `windowState.workSession`
- Add the Chat/Work picker (segmented control with `matchedGeometryEffect`) above `FloatingInputCard` — port from `ProjectHomeView`
- Hide the picker when no project is selected (`ProjectListView` shown instead)
- Ensure full-bleed layout: `ThemedBackgroundLayer`, toolbar clearance spacer (52px), `clipShape`, spring animations — MUST match Chat and Work tabs exactly
- Study the screenshots to understand the visual parity requirement:
  - Chat tab: full-bleed background, sidebar extends to top, content behind toolbar
  - Work tab: same
  - Projects tab: MUST look identical

**Key references to study:**
- `ChatView.chatModeContent` (around line 1357) — how chat renders its content area with sidebar
- Chat empty state — how it renders when `session.turns.isEmpty` (agent greeting, quick actions)
- `WorkView.body` (line 29-52) — how work renders its content area with sidebar
- `WorkView` empty state — how it renders `WorkEmptyState` when `session.currentTask == nil`

### Task 5: Update AppSidebar Unified Recents

**File:** `Views/Sidebar/AppSidebar.swift`

- Delete `RecentRow` struct (line 304)
- Create `ProjectRecentItem` enum:
  ```swift
  enum ProjectRecentItem: Identifiable {
      case session(ChatSessionData)
      case task(WorkTask)
      var id: String { ... }
      var date: Date { ... }
  }
  ```
- Update `visibleSessions` (line 212) → rename to something like `projectRecentItems` that merges chat sessions + work tasks:
  - Query `ChatSessionsManager` for sessions where `projectId == activeProjectId`
  - Query `IssueStore.listTasks(projectId: activeProjectId)` for work tasks
  - Merge, sort by date descending
- Render using shared `SessionRow` (for `.session` case) and `TaskRow` (for `.task` case)
- Wire `SessionRow` callbacks: onSelect loads session + sets `subMode = .chat`, onDelete, onStartRename, etc.
- Wire `TaskRow` callbacks: onSelect loads task + sets `subMode = .work`, onDelete
- Keep search filtering working across both types
- When NOT in project mode: keep showing chat sessions only (current behavior)

### Task 6: Add Outputs to Inspector

**File:** `Views/Projects/ProjectInspectorPanel.swift`

- Add `CollapsibleSection("Outputs", ...)` between Scheduled (line 72) and Context (line 98)
- Query `IssueStore` for `SharedArtifact` items belonging to work tasks with `projectId == activeProjectId`
- Each row: file type icon, filename, file size — same styling as other inspector rows
- Tap: open `ArtifactViewerSheet` (already exists in ProjectView's sheet handler)
- Empty state: icon + "No outputs yet", same pattern as Scheduled section's empty state
- Same `CollapsibleSection` component, same theme

### Task 7: Delete Old Files

- Delete `Views/Projects/ProjectHomeView.swift`
- Delete `Views/Projects/ProjectInlineChatView.swift`
- Delete `Views/Projects/ProjectInlineWorkView.swift`
- Verify zero compile errors after deletion

### Task 8: Code Cleanup and Grep Sweep

Run grep sweep — ALL of these must return zero results:
- `inlineSessionId`
- `inlineWorkTaskId`
- `hasInlineContent`
- `ProjectInputMode`
- `ProjectHomeView`
- `ProjectInlineChatView`
- `ProjectInlineWorkView`
- `InlineWorkPulseModifier`

Additional cleanup:
- Remove `formatRelativeDate` if orphaned (verify it's still used by shared `SessionRow`/`TaskRow` or elsewhere)
- Remove `onChange(of: session.inlineWorkTaskId)` from ProjectView — replace with sub-mode-driven tool registration

### Task 9: Update Tests

**File:** `Tests/Project/ProjectNavigationTests.swift`
- Remove tests for `hasInlineContent`, `inlineSessionId`
- Add tests for `ProjectSubMode` enum
- Add tests for `ProjectSession` with `subMode`
- Update `NavigationEntry` tests (no `workTaskId`)

**File:** `Tests/Project/NavigationStackTests.swift`
- Update any references to `workTaskId` in `NavigationEntry`

### Task 10: Final Verification

- Run `cd Packages/OsaurusCore && swift build 2>&1 | grep -E "error:" | grep -v "IkigaJSON"` — must be empty
- Run `swift test --package-path Packages/OsaurusCore --filter ProjectNavigationTests` — all tests pass
- Run the app and verify:
  - Chat tab looks and works exactly as before (no regressions)
  - Work tab looks and works exactly as before (no regressions)
  - Projects tab: selecting a project immediately shows chat content with agent greeting
  - Projects tab: Chat/Work picker switches center content with correct backgrounds
  - Projects tab: sending a chat message starts a real conversation with streaming
  - Projects tab: switching to work and sending a task starts real execution
  - Projects tab: sidebar shows unified recents (sessions + tasks interleaved by date)
  - Projects tab: sidebar search filters both types
  - Projects tab: inspector shows Outputs section
  - Projects tab: window chrome matches Chat/Work (full-bleed, no layout gap at top)
  - Projects tab: back/forward navigation works
  - Projects tab: toolbar is centered, inspector button is rightmost

## Compile Verification

```bash
cd Packages/OsaurusCore && swift build 2>&1 | grep -E "error:" | grep -v "IkigaJSON"
```
Empty output = clean compile. Pre-existing build failures in mlx-swift-lm and IkigaJSON are expected and unrelated.

## Test Commands

```bash
swift test --package-path Packages/OsaurusCore --filter ProjectNavigationTests
swift test --package-path Packages/OsaurusCore  # full test suite
```

Pre-existing failures in `WorkEngineResumeTests` (database not open in test env) and MLX metallib errors are unrelated to this work.

## Key File Reference

| File | Line | What's There |
|------|------|-------------|
| `ChatView.swift` | 1298 | Mode routing (`mode == .project` → ProjectView) |
| `ChatView.swift` | ~1357 | `chatModeContent` — chat content area with sidebar |
| `ChatView.swift` | 46 | `ChatSession.projectId` property |
| `ChatWindowState.swift` | 32 | `ProjectSession` struct (to be simplified) |
| `ChatWindowState.swift` | 49 | `NavigationEntry` struct (to be simplified) |
| `ChatWindowState.swift` | 298 | `switchMode(to:)` |
| `WorkView.swift` | 29–52 | HStack sidebar embedding pattern |
| `WorkView.swift` | 313 | `ClarificationOverlay` (to extract) |
| `WorkView.swift` | 340 | `WorkStatusButton` (to extract) |
| `WorkView.swift` | 1825 | `WorkPulseModifier` (to extract) |
| `ChatSessionSidebar.swift` | 177 | `SessionRow` (to extract) |
| `WorkTaskSidebar.swift` | 139 | `TaskRow` (to extract) |
| `AppSidebar.swift` | 212 | `visibleSessions` computed property |
| `AppSidebar.swift` | 304 | `RecentRow` (to delete/replace) |
| `ProjectInspectorPanel.swift` | 72 | Scheduled section (Outputs goes after this) |
| `ProjectInspectorPanel.swift` | 98 | Context section (Outputs goes before this) |
| `IssueStore.swift` | 558 | `listTasks` — no projectId param (gap) |

## Non-Goals (Do Not Do These)

- Do not change the Chat tab in any way
- Do not change the Work tab behavior (only extract private views to shared)
- Do not add a `defaultAgentId` to the Project model
- Do not change the toolbar layout
- Do not change `SharedSidebarComponents`, `CollapsibleSection`, `FolderTreeView`, `FloatingInputCard`, `MessageThreadView`
- Do not change the memory system
- Do not change the Project model or ProjectManager
- Do not change ProjectListView or ProjectEditorSheet
