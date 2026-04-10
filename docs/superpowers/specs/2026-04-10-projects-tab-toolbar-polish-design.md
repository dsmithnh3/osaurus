# Projects Tab, Toolbar & Visual Polish — Design Spec

**Date:** 2026-04-10
**Status:** Draft
**Author:** Daniel Smith + Claude
**Branch:** `feat/projects-first-class`
**Parent spec:** `specs/2026-04-09-projects-first-class-design.md`

## Overview

A comprehensive polish pass for the Projects tab and app-wide toolbar. This spec addresses confirmed bugs (sidebar toggle, horizontal scroll, navigation), adds missing toolbar items (inspector toggle, `.principal` centering), redesigns the left sidebar for Projects mode, enables inline chat/work within projects (no tab switching), and unifies visual styling across all panels using the established `SharedSidebarComponents` design system.

## Goals

- Fix the broken sidebar toggle, horizontal scroll, and back/forward navigation in Projects mode
- Center the mode toggle in the toolbar using `.principal` (Apple-idiomatic)
- Add an inspector toggle button to the toolbar for Projects mode
- Redesign the left sidebar with a stacked project list + unified recents using real `SessionRow` / `TaskRow` components
- Enable inline chat and work within the Projects tab — no mode switching, no tab ejection
- Unify both panel backgrounds using `SidebarContainer` / `SidebarBackground` / `SidebarBorder`
- Apply `ThemedBackgroundLayer` to the Projects center panel to match Chat and Work
- Delete all replaced components — no dead code

## Non-Goals

- Vibrancy/material effects on panels (future polish)
- `NSSplitView` migration for resizable panels (future polish — noted in parent spec)
- Drag-and-drop reordering in project list
- Project export/import

---

## 1. Toolbar Changes

### 1a. Mode Toggle Centering

Move the mode toggle from a custom identifier with dual `.flexibleSpace` to `NSToolbarItem.Identifier.principal` for true window-centered placement.

**File:** `Packages/OsaurusCore/Managers/Chat/ChatWindowManager.swift`

**Changes to `ChatToolbarDelegate`:**

- Remove `static let modeToggleItem = NSToolbarItem.Identifier("ChatToolbar.modeToggle")`
- In `toolbarAllowedItemIdentifiers` and `toolbarDefaultItemIdentifiers`, replace `Self.modeToggleItem` with `.principal` and remove both `.flexibleSpace` entries
- In `toolbar(_:itemForItemIdentifier:willBeInsertedIntoToolbar:)`, handle `.principal` the same way `Self.modeToggleItem` is handled today — wrap `ChatToolbarModeToggleView` in `makeHostingItem`

```
Before: [sidebar] [back] [fwd] [flex] [modeToggle] [flex] [action] [pin]
After:  [sidebar] [back] [fwd]       [.principal]        [action] [inspector] [pin]
```

**Verification:** Build, then visually confirm on a wide window that the segmented control sits at the true horizontal midpoint. Check Accessibility Inspector for correct AX tree ordering.

### 1b. Inspector Toggle Button

New toolbar button for toggling the right inspector panel, visible in Projects mode.

**File:** `Packages/OsaurusCore/Managers/Chat/ChatWindowManager.swift`

**Changes:**

- Add `static let inspectorItem = NSToolbarItem.Identifier("ChatToolbar.inspector")`
- Add to `toolbarAllowedItemIdentifiers` and `toolbarDefaultItemIdentifiers` between `actionItem` and `pinItem`
- Create `ChatToolbarInspectorView` — renders `sidebar.right` SF Symbol, calls `windowState.showProjectInspector.toggle()`
- The button is always present in the toolbar but visually hidden/disabled when `windowState.mode != .project` to avoid toolbar items jumping on mode switch

### 1c. Back/Forward Navigation Fix

`restoreNavigationEntry` currently calls `switchMode(to:)` which resets `sidebarContentMode = .chat` and clears inline session state. Fix it to restore the full `ProjectSession` state.

**Dependency:** This fix requires the `NavigationEntry` extension from Section 3 (`workTaskId` field) and the `ProjectSession` extension from Section 3 (`inlineSessionId`, `inlineWorkTaskId` fields). Implement Section 3's model changes first.

**File:** `Packages/OsaurusCore/Managers/Chat/ChatWindowState.swift`

**Changes to `restoreNavigationEntry`:**

```swift
private func restoreNavigationEntry(_ entry: NavigationEntry) {
    // Set mode without resetting project session state
    if entry.mode != mode {
        mode = entry.mode
    }

    if entry.mode == .project {
        var session = ProjectSession(activeProjectId: entry.projectId)
        session.inlineSessionId = entry.sessionId
        session.inlineWorkTaskId = entry.workTaskId
        projectSession = session
        if let pid = entry.projectId {
            ProjectManager.shared.setActiveProject(pid)
        }
    } else if let projectId = entry.projectId {
        projectSession = ProjectSession(activeProjectId: projectId)
        ProjectManager.shared.setActiveProject(projectId)
    }
}
```

---

## 2. Left Sidebar Redesign

Replace the current `AppSidebar` layout (nav items + project chip + simplified recents) with a stacked design: project list section + unified recents section separated by a draggable divider.

### Layout

```
┌──────────────────────────┐
│  [+ New Chat]            │  project-aware (scopes to active project)
│  [⌕ Search convos...]   │  SidebarSearchField
├──────────────────────────┤
│  ▾ Projects              │  CollapsibleSection
│    📁 CIMCO Refriger…  ● │  active indicator dot (theme.accentColor)
│    📁 Hammond Overhaul   │  compact row: icon + name
│    📁 Denka Arena        │  uses SidebarRowBackground
│    📁 Project 4          │
│    📁 Project 5          │  ← max ~140pt, scrolls internally
│    ┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈  │
│    📋 All Projects →     │  opens ProjectListView grid in center
├─ ═══ draggable ═══ ─────┤  NSCursor.resizeUpDown, height persisted
│  ▾ Recents               │  CollapsibleSection
│    💬 [SessionRow]       │  real SessionRow (agent dot, rename, etc.)
│    ⚡ [TaskRow]          │  real TaskRow (morphing icon, animations)
│    💬 [SessionRow]       │  interleaved by updatedAt, descending
│    ...                   │
└──────────────────────────┘
```

### Project List Section

- Shows `ProjectManager.shared.activeProjects`
- Max height ~140pt (5 compact rows at ~28pt each), scrolls internally via `ScrollView(.vertical, showsIndicators: false)`
- Each row: `HStack` with project icon (`Image(systemName: project.icon)`) + name (`.system(size: 12)`, `theme.primaryText`, `.lineLimit(1)`) + active indicator dot (`theme.accentColor`, 6pt circle, visible when this is the selected project)
- Row background: `SidebarRowBackground(isSelected: isActiveProject, isHovered: isHovered)`
- Row corner radius: `SidebarStyle.rowCornerRadius`
- Clicking a row: sets `ProjectManager.shared.setActiveProject(project.id)`, navigates to project home (pushes `NavigationEntry(mode: .project, projectId: project.id)`)
- Context menu on active project row: "Deselect Project" to clear `activeProjectId`
- "All Projects" row: styled with `theme.secondaryText`, trailing `chevron.right`, sets `windowState.sidebarContentMode = .projects` to show full `ProjectListView` grid in center

### Draggable Divider

- Visual: 1pt `theme.primaryBorder.opacity(0.3)` line with a subtle drag handle (three small dots, `theme.tertiaryText`)
- Drag gesture adjusts max height of the project list section
- Persisted to `UserDefaults` key `sidebarProjectSectionHeight`
- Min height: ~56pt (2 rows). Max height: 50% of sidebar height
- Cursor: `NSCursor.resizeUpDown` on hover

### Recents Section

- Uses the real `SessionRow` from `ChatSessionSidebar.swift` and `TaskRow` from `WorkTaskSidebar.swift`
- When a project is selected: filtered to that project's conversations and work tasks (`WHERE projectId == activeProjectId`)
- When no project selected: shows all conversations and work tasks
- Interleaved by `updatedAt` descending
- Clicking a `SessionRow`: sets `projectSession.inlineSessionId`, pushes nav entry (stays in Projects tab)
- Clicking a `TaskRow`: sets `projectSession.inlineWorkTaskId`, pushes nav entry (stays in Projects tab)
- Both row types retain full functionality: rename, delete, context menus, agent color dots, morphing status icons, 60fps spinner animation

### New Chat Button

- When `ProjectManager.shared.activeProjectId != nil`: creates `ChatSessionData(projectId: activeProjectId)`, sets `projectSession.inlineSessionId`, opens inline
- When no project active: creates a general chat as today

### Edge Cases

- **Empty project list:** When there are zero active projects, the "Projects" `CollapsibleSection` header still shows but the content area displays a single row: "Create a project to get started" with a `plus` icon, styled as a `SidebarRowBackground` hover row. Tapping it opens `ProjectEditorSheet`. The "All Projects" row is hidden when no projects exist.
- **Draggable divider at extremes:** At min height (~56pt), the project list shows 2 rows with internal scroll. At max height (50% sidebar), the recents section still has at least 50% of the sidebar for scrolling. Divider clamps to bounds — dragging past min/max has no effect.

### Removed Components

- `SidebarNavRow` — project list rows replace the "Projects" nav item, "All Projects" row replaces the grid navigation, "Scheduled" moves to inspector, "Customize" accessible from menu bar
- `ActiveProjectChipView` — project list with active indicator replaces it
- `RecentSessionRow` — real `SessionRow` + `TaskRow` replace it

**File:** `Packages/OsaurusCore/Views/Sidebar/AppSidebar.swift` (rewrite)

---

## 3. Inline Chat/Work in Projects

Projects becomes a container that hosts chat and work views inline — no mode switching, no tab ejection.

### ProjectSession Extension

**File:** `Packages/OsaurusCore/Managers/Chat/ChatWindowState.swift`

**Inspector state consolidation:** The current code has two properties controlling the inspector: `ChatWindowState.showProjectInspector` (line 94) and `ProjectSession.showInspector` (line 34). **Remove `ProjectSession.showInspector`** — `ChatWindowState.showProjectInspector` is the single source of truth. The toolbar button (Section 1b) and any in-view toggle both call `windowState.showProjectInspector.toggle()`. `ProjectSession` should only carry project identity and inline session state, not UI toggle state.

```swift
public struct ProjectSession: Equatable, Sendable {
    public var activeProjectId: UUID?

    // Inline session state — at most one is non-nil
    public var inlineSessionId: UUID?
    public var inlineWorkTaskId: UUID?

    public var hasInlineContent: Bool {
        inlineSessionId != nil || inlineWorkTaskId != nil
    }
}
```

### NavigationEntry Extension

**File:** `Packages/OsaurusCore/Managers/Chat/ChatWindowState.swift`

```swift
public struct NavigationEntry: Equatable, Sendable {
    public let mode: ChatMode
    public let projectId: UUID?
    public let sessionId: UUID?
    public let workTaskId: UUID?    // NEW
}
```

### ProjectView State Machine

**File:** `Packages/OsaurusCore/Views/Projects/ProjectView.swift`

`ProjectView` handles three center panel states:

| State                                         | Center panel             |
| --------------------------------------------- | ------------------------ |
| `activeProjectId == nil`                      | `ProjectListView` (grid) |
| `activeProjectId` set, no inline session      | `ProjectHomeView` (home) |
| `activeProjectId` set, `inlineSessionId` set  | Chat view (inline)       |
| `activeProjectId` set, `inlineWorkTaskId` set | Work view (inline)       |

```swift
var body: some View {
    ZStack(alignment: .trailing) {
        ThemedBackgroundLayer(
            cachedBackgroundImage: windowState.cachedBackgroundImage,
            showSidebar: windowState.showSidebar
        )

        // Center content
        if let projectId = session.activeProjectId {
            if let sessionId = session.inlineSessionId {
                inlineChatView(projectId: projectId, sessionId: sessionId)
            } else if let taskId = session.inlineWorkTaskId {
                inlineWorkView(projectId: projectId, taskId: taskId)
            } else if let project = projectFor(projectId) {
                ProjectHomeView(project: project, windowState: windowState, ...)
            }
        } else {
            ProjectListView(windowState: windowState)
        }

        // Right inspector overlay
        if windowState.showProjectInspector, ... {
            ProjectInspectorPanel(...)
        }
    }
    .clipShape(contentShape)
    .animation(.spring(response: 0.35, dampingFraction: 0.88), value: windowState.showProjectInspector)
}
```

The inline chat and work views are the same SwiftUI components used in Chat and Work modes. The differences:

- They render inside `ProjectView`'s center panel
- `ThemedBackgroundLayer` wraps the entire `ProjectView` (not per-view)
- The right inspector stays visible alongside the content
- The toolbar stays on "Projects" — `windowState.mode` stays `.project`

### Engine Activation

Chat: `ChatEngine.streamChat()` works regardless of mode — no special activation needed.

Work: `WorkToolManager.shared.registerTools()` is currently called by `switchMode(to: .work)`. For inline work, `ProjectView` handles this:

```swift
.onChange(of: session.inlineWorkTaskId) { old, new in
    if new != nil { WorkToolManager.shared.registerTools() }
    if old != nil && new == nil { WorkToolManager.shared.unregisterTools() }
}
```

### Mode Picker on FloatingInputCard

The project home's `FloatingInputCard` gets a two-segment control for choosing chat vs work:

```swift
enum ProjectInputMode { case chat, work }

Picker("", selection: $projectInputMode) {
    Label("Chat", systemImage: "bubble.left").tag(ProjectInputMode.chat)
    Label("Work", systemImage: "bolt.circle").tag(ProjectInputMode.work)
}
.pickerStyle(.segmented)
.frame(width: 160)
```

Styled to match `ModeToggleButton`'s existing pill style: `theme.secondaryBackground.opacity(0.8)` for selected segment fill, `theme.accentColor` tint, `matchedGeometryEffect` for sliding animation.

On send:

- **Chat:** Create `ChatSessionData(projectId: project.id)`, set `session.inlineSessionId`, push nav entry
- **Work:** Create `WorkTask(projectId: project.id)`, set `session.inlineWorkTaskId`, push nav entry

### Memory Scoping

All memory recorded during inline sessions uses the project's ID. The existing `projectId` parameter on `MemoryService.recordConversationTurn()` handles this — no changes needed to the memory system.

### App Relaunch Behavior

`ProjectSession` is in-memory state on `ChatWindowState` — it is not persisted. On app quit or force-quit:

- `inlineSessionId` and `inlineWorkTaskId` are lost
- On relaunch, the user lands on the project home (or project list if no project was active)
- The chat session and work task themselves ARE persisted (in their respective stores), so they appear in the sidebar recents for re-entry
- This is intentional: restoring an inline mid-conversation state on relaunch would require re-hydrating engine state, which is fragile. Landing on project home is safe and predictable.

---

## 4. Visual Unification

### 4a. Inspector Adopts `SidebarContainer`

**File:** `Packages/OsaurusCore/Views/Projects/ProjectInspectorPanel.swift`

Wrap `ProjectInspectorPanel` in `SidebarContainer(attachedEdge: .trailing, width: SidebarStyle.inspectorWidth)`. This gives it:

- `SidebarBackground` — glass background with accent gradient (matching left sidebar)
- `SidebarBorder` — gradient border with accent edge highlight, trailing-edge corner radii
- Edge-aware `UnevenRoundedRectangle` clipping — trailing corners rounded at 14pt, leading corners 0pt (flush with content)

Delete the inspector's current manual background (`RoundedRectangle.fill(theme.secondaryBackground.opacity(0.5))`, lines 133-136) and manual border overlay (lines 137-142). `SidebarContainer` replaces both.

### 4b. `SidebarContainer` Width Parameterization

**File:** `Packages/OsaurusCore/Views/Management/SharedSidebarComponents.swift`

Add an optional `width` parameter to `SidebarContainer`:

```swift
struct SidebarContainer<Content: View>: View {
    let attachedEdge: Edge?
    let topPadding: CGFloat
    let width: CGFloat

    init(
        attachedEdge: Edge? = nil,
        topPadding: CGFloat = 0,
        width: CGFloat = SidebarStyle.width,
        @ViewBuilder content: @escaping () -> Content
    ) { ... }

    var body: some View {
        VStack(spacing: 0) {
            content()
        }
        .padding(.top, topPadding)
        .frame(width: width, alignment: .top)    // was: SidebarStyle.width (hardcoded)
        .frame(maxHeight: .infinity, alignment: .top)
        .background { SidebarBackground() }
        .clipShape(containerShape)
        .overlay(SidebarBorder(attachedEdge: attachedEdge))
    }
}
```

**Key change:** Line 65 of the current `SidebarContainer.body` hardcodes `.frame(width: SidebarStyle.width)`. The new `width` stored property replaces that constant so the inspector can pass `SidebarStyle.inspectorWidth`.

Add to `SidebarStyle`:

```swift
static let inspectorWidth: CGFloat = 300
```

### 4c. Inspector Rows Adopt `SidebarRowBackground`

File tree items in `FolderTreeView`, memory entries in `MemorySummaryView`, and schedule rows use `SidebarRowBackground(isSelected:isHovered:)` instead of manual hover fills. Row corner radius: `SidebarStyle.rowCornerRadius`. Action buttons use `SidebarRowActionButton`.

### 4d. Section Header Typography

`CollapsibleSection` main headers (Instructions, Scheduled, Context, Memory) use `.system(size: 13, weight: .semibold)` with `theme.primaryText` — matching `ChatSessionSidebar`'s "History" header. Sub-headers like "On your computer" stay at `.system(size: 10, weight: .semibold)`, `.textCase(.uppercase)`, `theme.tertiaryText`.

### 4e. ThemedBackgroundLayer on ProjectView

**File:** `Packages/OsaurusCore/Views/Projects/ProjectView.swift`

Apply `ThemedBackgroundLayer` as the first layer in `ProjectView`'s `ZStack` (see Section 3 code). Apply the same `UnevenRoundedRectangle` clipping used by Chat/Work — top-leading/bottom-leading radii 0 when sidebar visible, 24 otherwise; trailing corners always 24.

### 4f. FloatingInputCard Width

**File:** `Packages/OsaurusCore/Views/Projects/ProjectHomeView.swift`

Change `.frame(maxWidth: 800)` to `.frame(maxWidth: 1100)` to match Chat mode.

### 4g. Inspector Horizontal Scroll Fix

**File:** `Packages/OsaurusCore/Views/Projects/FolderTreeView.swift`

- Add `.truncationMode(.middle)` to the filename `Text` view (line 62-63 — the `Text(item.name)` node, which already has `.lineLimit(1)` at line 65)
- Add `.frame(maxWidth: .infinity, alignment: .leading)` on the `Text` itself (not just the row HStack) — without a width constraint, `.truncationMode` won't trigger truncation
- Add `.frame(maxWidth: .infinity, alignment: .leading)` on the row `HStack` to prevent it from expanding beyond the inspector width
- Change `ProjectInspectorPanel`'s `ScrollView` to explicit `ScrollView(.vertical, showsIndicators: false)`

### 4h. Empty State Polish

**File:** `Packages/OsaurusCore/Views/Projects/ProjectHomeView.swift`

Replace the current plain empty states (outputs section, recents section) with the same pattern used by `ChatEmptyState` and `WorkEmptyState`:

- Themed icon at 88pt (or appropriately scaled for section context)
- `theme.font` with proper text hierarchy
- `QuickActionButton`-style background with gradient border
- Staggered fade-in animation on appear

### 4i. Remove Duplicate Inspector Border

**File:** `Packages/OsaurusCore/Views/Projects/ProjectView.swift`

Delete the manual border overlay on the inspector container (lines 41-44). `SidebarContainer` handles its own border via `SidebarBorder`.

---

## 5. Design Consistency Constraint

**Rule: Every new component and modification in this spec must use the existing design system from `SharedSidebarComponents.swift` and the established theme patterns. No new one-off styling.**

### Panels & Containers

- Any panel (sidebar, inspector, or future) → `SidebarContainer(attachedEdge:)`
- Background → `SidebarBackground` (glass + accent gradient)
- Border → `SidebarBorder` (gradient border + accent edge)
- Never manually set `theme.secondaryBackground.opacity(...)` as a panel background

### Rows & Interactive Items

- Any selectable/hoverable row → `SidebarRowBackground(isSelected:isHovered:)`
- Row corner radius → `SidebarStyle.rowCornerRadius` (8pt)
- Row action buttons → `SidebarRowActionButton`
- Never manually build hover/selection states with inline `.background(isHovered ? ... : ...)`

### Search & Filtering

- Search fields → `SidebarSearchField`
- No-results state → `SidebarNoResultsView`

### Typography

- Section headers (top-level): `.system(size: 13, weight: .semibold)`, `theme.primaryText`
- Sub-headers: `.system(size: 10, weight: .semibold)`, `.textCase(.uppercase)`, `theme.tertiaryText`
- Row titles: `.system(size: 12)`, `theme.primaryText`
- Row metadata: `.system(size: 11)`, `theme.secondaryText`
- Relative dates: `formatRelativeDate()` from `SharedSidebarComponents`

### Spacing & Layout

- Content horizontal padding: 12pt
- Section dividers: `Divider().opacity(0.3)` with 8pt vertical padding
- Row vertical padding: 4-6pt
- All measurements from `SidebarStyle` constants

### New Components Compliance

| New Component                    | Must Use                                                                                                 |
| -------------------------------- | -------------------------------------------------------------------------------------------------------- |
| Project list row (sidebar)       | `SidebarRowBackground`, `SidebarStyle.rowCornerRadius`, `SidebarRowActionButton`                         |
| "All Projects" row               | `SidebarRowBackground` hover state, same row padding                                                     |
| Draggable divider                | `theme.primaryBorder` color, `theme.tertiaryText` for drag handle                                        |
| Mode picker on FloatingInputCard | `ModeToggleButton` pill style: `theme.secondaryBackground`, `theme.accentColor`, `matchedGeometryEffect` |
| Inspector toggle toolbar button  | Same pattern as `ChatToolbarBackView` / `ChatToolbarForwardView`                                         |
| Inline chat/work in ProjectView  | Identical to standalone versions — no wrapper styling                                                    |
| Active project indicator dot     | `theme.accentColor`, 6pt, matching agent dot from `SessionRow`                                           |

---

## 6. Code Cleanup

Every component replaced by this spec gets deleted during implementation. No dead code.

### Files to Delete

| File                                | Reason                                                     |
| ----------------------------------- | ---------------------------------------------------------- |
| `Views/Sidebar/SidebarNavRow.swift` | Replaced by project list rows using `SidebarRowBackground` |

### Dead Code to Remove

| File                          | Remove                                                                                  | Replaced by                                 |
| ----------------------------- | --------------------------------------------------------------------------------------- | ------------------------------------------- |
| `AppSidebar.swift`            | `ActiveProjectChipView` struct (lines 137-179)                                          | Project list with active indicator dot      |
| `AppSidebar.swift`            | `RecentSessionRow` struct (lines 183-204)                                               | Real `SessionRow` + `TaskRow` components    |
| `AppSidebar.swift`            | `SidebarNavRow` usage and 3 nav items block (lines 44-69)                               | Project list section + "All Projects" row   |
| `ProjectInspectorPanel.swift` | Manual background `RoundedRectangle.fill(...)` (lines 133-136)                          | `SidebarContainer(attachedEdge: .trailing)` |
| `ProjectInspectorPanel.swift` | Manual border overlay (lines 137-142)                                                   | `SidebarBorder` via `SidebarContainer`      |
| `ProjectView.swift`           | Duplicate border overlay on inspector (lines 41-44)                                     | `SidebarContainer` handles own border       |
| `FolderTreeView.swift`        | Manual hover background fill (line 84)                                                  | `SidebarRowBackground`                      |
| `ProjectHomeView.swift`       | Manual inspector toggle button + hover state (lines 93-109, `isInspectorButtonHovered`) | Toolbar inspector button                    |
| `ChatWindowManager.swift`     | `modeToggleItem` static identifier                                                      | Replaced by `.principal`                    |
| `ChatWindowManager.swift`     | Both `.flexibleSpace` entries in toolbar identifiers                                    | Removed with `.principal` change            |

### Verification

After all deletions, verify no references to deleted types remain:

```bash
cd Packages/OsaurusCore && swift build 2>&1 | grep -E "error:" | grep -v "IkigaJSON"
grep -rn "ActiveProjectChipView\|RecentSessionRow\|SidebarNavRow\|modeToggleItem" Packages/OsaurusCore/
```

Both should return zero results.

---

## 7. File Map

### New Files

| File | Purpose                                                             |
| ---- | ------------------------------------------------------------------- |
| None | All changes modify existing files or replace components within them |

### Modified Files

| File                                             | Change                                                                                                                    |
| ------------------------------------------------ | ------------------------------------------------------------------------------------------------------------------------- |
| `Managers/Chat/ChatWindowManager.swift`          | `.principal` centering, inspector toolbar button, remove `modeToggleItem` + flexibleSpaces                                |
| `Managers/Chat/ChatWindowState.swift`            | `ProjectSession` extension (inline IDs), `NavigationEntry` extension (`workTaskId`), `restoreNavigationEntry` fix         |
| `Views/Sidebar/AppSidebar.swift`                 | Full rewrite: stacked project list + draggable divider + unified recents with real `SessionRow`/`TaskRow`                 |
| `Views/Projects/ProjectView.swift`               | 3-state center panel routing, `ThemedBackgroundLayer`, clip shape, inline chat/work hosting, `WorkToolManager` activation |
| `Views/Projects/ProjectHomeView.swift`           | Mode picker on `FloatingInputCard`, remove manual inspector toggle, `maxWidth: 1100`, empty state polish                  |
| `Views/Projects/ProjectInspectorPanel.swift`     | Wrap in `SidebarContainer(attachedEdge: .trailing)`, remove manual background/border, section header typography           |
| `Views/Projects/FolderTreeView.swift`            | `.truncationMode(.middle)`, `SidebarRowBackground` for rows, constrain row width                                          |
| `Views/Projects/MemorySummaryView.swift`         | `SidebarRowBackground` for rows                                                                                           |
| `Views/Management/SharedSidebarComponents.swift` | `SidebarContainer` width parameter, `SidebarStyle.inspectorWidth` constant                                                |
| `Views/Common/CollapsibleSection.swift`          | Header typography update to 13pt for main sections                                                                        |

### Deleted Files

| File                                | Reason                        |
| ----------------------------------- | ----------------------------- |
| `Views/Sidebar/SidebarNavRow.swift` | Replaced by project list rows |

---

## 8. Interaction Flows

### Starting a Chat from Project Home

1. User is on project home, mode picker set to "Chat" (default)
2. User types message in `FloatingInputCard`, sends
3. `ChatSessionData` created with `projectId` set
4. `projectSession.inlineSessionId` set to new session ID
5. Nav entry pushed: `NavigationEntry(mode: .project, projectId: pid, sessionId: sid)`
6. `ProjectView` center panel transitions to inline chat view
7. Toolbar stays on "Projects", sidebar highlights the new session in recents
8. All memory recorded with `projectId`

### Starting a Work Task from Project Home

1. User switches mode picker to "Work"
2. User types task description, sends
3. `WorkTask` created with `projectId` set
4. `WorkToolManager.shared.registerTools()` called
5. `projectSession.inlineWorkTaskId` set to new task ID
6. Nav entry pushed: `NavigationEntry(mode: .project, projectId: pid, workTaskId: tid)`
7. `ProjectView` center panel transitions to inline work view
8. `TaskRow` appears in sidebar recents with morphing status icon

### Navigating Back to Project Home

1. User clicks back button in toolbar
2. `goBack()` decrements `navigationIndex`, calls `restoreNavigationEntry`
3. Entry has `projectId` set but no `sessionId` or `workTaskId`
4. `projectSession.inlineSessionId` and `inlineWorkTaskId` cleared
5. If work was active: `WorkToolManager.shared.unregisterTools()` via `.onChange`
6. Center panel transitions back to `ProjectHomeView`
7. Previous chat/task remains in sidebar recents for re-entry

### Switching Projects via Sidebar

1. User clicks a different project in the sidebar project list
2. `ProjectManager.shared.setActiveProject(newProjectId)` called
3. `projectSession` reset: new `activeProjectId`, inline IDs cleared
4. Nav entry pushed
5. Sidebar recents re-filter to new project's conversations/tasks
6. Center panel shows new project's home

### Clicking a Recent in Sidebar

1. User clicks a `SessionRow` → `projectSession.inlineSessionId` set, opens inline chat
2. User clicks a `TaskRow` → `projectSession.inlineWorkTaskId` set, opens inline work
3. Both push nav entries, both stay in Projects tab

---

## 9. Future Polish

Items explicitly deferred from this spec:

- **Vibrancy/material effects:** If `theme.glassEnabled`, panels could use `NSVisualEffectView` materials. Deferred to avoid complexity.
- **`NSSplitView` migration:** Replace overlay panels with `HSplitView` for native resizable dividers and autosave. Noted in parent spec.
- **Project list drag-and-drop reordering**
- **"New Task" button in sidebar:** Currently only "New Chat". Could add a `+` menu with Chat/Work options. The mode picker on project home is sufficient for v1.
- **Inspector width persistence:** Allow user to resize inspector, persist width to UserDefaults
