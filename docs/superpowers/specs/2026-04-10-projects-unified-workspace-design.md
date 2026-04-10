# Projects Unified Workspace — Design Spec

> **Status:** Approved  
> **Date:** 2026-04-10  
> **Supersedes:** The ProjectHomeView/inline-views approach from the `2026-04-09-projects-first-class-design.md` spec (Projects tab sections only — all other parts of that spec remain valid)

## Problem

The current Projects tab has a landing page (`ProjectHomeView`) that gates the user behind empty placeholder sections (Outputs, Recents) before they can do actual work. Starting a chat or work task requires sending from this landing page, which transitions to "inline" views (`ProjectInlineChatView`, `ProjectInlineWorkView`) that duplicate code from the real Chat and Work views. This creates:

- An extra click before the user can do anything
- Duplicated private views (`InlineWorkPulseModifier`, `WorkStatusButton`, `ClarificationOverlay`) that drift from their originals
- A fragile `inlineSessionId`/`inlineWorkTaskId` state machine in `ProjectSession`
- Visual inconsistency — the Projects tab doesn't match the full-bleed window chrome of Chat and Work tabs
- Empty placeholder sections that provide no value

## Solution

Projects mode becomes a **unified workspace**. Selecting a project immediately shows the chat or work content area — identical to the standalone Chat and Work tabs. A Chat/Work picker above the `FloatingInputCard` controls which engine is active. Both engines preserve their state independently; switching between them is instant.

The "dashboard" information (recents, outputs, folder tree, memory) lives in the sidebar and inspector — always accessible but never blocking the main content area.

## Architecture

### Mode and Sub-Mode

```
ChatMode.project
└── ProjectSession
    ├── activeProjectId: UUID?
    └── subMode: ProjectSubMode (.chat | .work)
```

`ProjectSubMode` replaces the `inlineSessionId`/`inlineWorkTaskId` state machine. The picker toggles `subMode`, which determines whether the center renders chat or work content.

### Layout (3-Panel)

```
┌─────────────────────────────────────────────────────────────┐
│  Toolbar: [sidebar] [back] [fwd]  [Chat|Work|Projects]  ...│
├────────┬──────────────────────────────────┬─────────────────┤
│        │     ThemedBackgroundLayer        │                 │
│  App   │                                  │   Inspector     │
│  Side  │  Chat content (sub-mode .chat)   │   (overlay)     │
│  bar   │       — OR —                     │                 │
│        │  Work content (sub-mode .work)   │  Instructions   │
│        │                                  │  Scheduled      │
│ ────── │  Same empty states, message      │  Outputs (NEW)  │
│Projects│  threads, input cards as the     │  Context        │
│ ────── │  standalone Chat/Work tabs       │  Memory         │
│Recents │                                  │                 │
│(unified│     [Chat] [Work] picker         │                 │
│ by date│     [FloatingInputCard]          │                 │
│        │                                  │                 │
└────────┴──────────────────────────────────┴─────────────────┘
```

### Window Chrome Parity

ProjectView MUST be visually indistinguishable from Chat/Work at the window chrome level:

- Full-bleed content extending behind the toolbar
- `ThemedBackgroundLayer` filling the entire content area
- Toolbar clearance spacer (~52px `Color.clear`) at top
- `clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))` at the outer level
- Same spring animations for sidebar and inspector transitions

ProjectView follows the exact same `GeometryReader` + `HStack` structure:

```swift
GeometryReader { proxy in
    let sidebarWidth: CGFloat = windowState.showSidebar ? SidebarStyle.width : 0
    HStack(alignment: .top, spacing: 0) {
        if windowState.showSidebar {
            AppSidebar(...)
                .transition(.move(edge: .leading).combined(with: .opacity))
        }
        ZStack(alignment: .trailing) {
            ThemedBackgroundLayer(...)
            centerContent  // chat or work, based on subMode
            if showProjectInspector { ProjectInspectorPanel(...) }
        }
        .frame(width: proxy.size.width - sidebarWidth)
    }
}
.clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
.animation(...)
```

### Center Content Routing

```swift
// Inside ProjectView
@ViewBuilder
private var centerContent: some View {
    if let projectId = session.activeProjectId {
        switch session.subMode {
        case .chat:
            projectChatContent  // exact same components as ChatView.chatModeContent
        case .work:
            projectWorkContent  // exact same components as WorkView center
        }
    } else {
        ProjectListView(windowState: windowState)
        // Chat/Work picker is hidden when no project is selected
    }
}
```

**Chat sub-mode:** Renders the same empty state (agent greeting + `chatQuickActions`) when no conversation is active, same `MessageThreadView` + `FloatingInputCard` when a conversation is active. Uses `windowState.session`.

**Work sub-mode:** Renders `WorkEmptyState` (agent greeting + `workQuickActions`) when no task is running, same task execution view + `FloatingInputCard` when a task is active. Uses `windowState.workSession`.

The Chat/Work picker (`ProjectSubMode` segmented control with `matchedGeometryEffect`) sits above the `FloatingInputCard`, centered, matching the existing design.

### Sub-Mode Switching Behavior

Toggling the Chat/Work picker:

1. Updates `projectSession.subMode`
2. `.chat → .work`: registers `WorkToolManager` tools, creates `WorkSession` if nil
3. `.work → .chat`: unregisters work tools, does NOT destroy `WorkSession` (preserves state)
4. Center content swaps with the themed background changing accordingly
5. Both engines preserve their state — switch to work, start a task, switch back to chat, ask a question, switch back to work, task is still there

## State Model

### ProjectSession (simplified)

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

**Deleted fields:** `inlineSessionId`, `inlineWorkTaskId`, `hasInlineContent`

### NavigationEntry (simplified)

```swift
public struct NavigationEntry: Equatable, Sendable {
    public let mode: ChatMode
    public let projectId: UUID?
    public let sessionId: UUID?
}
```

**Deleted fields:** `workTaskId`

### ChatWindowState changes

`switchMode(to: .project)`:

- Creates `ProjectSession` if nil
- If `subMode == .work`: registers work tools, creates `WorkSession` if nil
- If `subMode == .chat`: unregisters work tools

`restoreNavigationEntry` for `.project`:

- Restores `ProjectSession` with `activeProjectId` from entry
- Preserves current `subMode` (or defaults to `.chat`)
- Handles work tool registration based on `subMode`

## Left Sidebar (AppSidebar)

### Unchanged

- `SidebarContainer` wrapping with glass styling
- New Chat button
- `SidebarSearchField` with search filtering
- Projects section (collapsible) with `ProjectSidebarRow`, draggable divider
- `CollapsibleSection` usage

### Unified Recents (Projects tab only)

When `windowState.mode == .project` and a project is active, the Recents section shows both chat sessions and work tasks interleaved by date.

```swift
enum ProjectRecentItem: Identifiable {
    case session(ChatSessionData)
    case task(WorkTask)

    var id: String { ... }
    var date: Date { ... }  // updatedAt for sessions, updatedAt for tasks
}
```

- Query `ChatSessionsManager` for sessions where `projectId == activeProjectId`
- Query work tasks for this project (via `WorkDatabase` or `IssueStore`)
- Merge into `[ProjectRecentItem]`, sort by `date` descending
- Render using shared `SessionRow` (for `.session`) or `TaskRow` (for `.task`)
- Search filters both types by title

**Tap behavior:**

- `SessionRow` tap: loads session into `windowState.session`, sets `subMode = .chat`
- `TaskRow` tap: loads task into `windowState.workSession`, sets `subMode = .work`

**When NOT in project mode:** Recents section shows chat sessions only (current behavior for Chat/Work tabs). Standalone `ChatSessionSidebar` and `WorkTaskSidebar` are untouched.

## Right Inspector (ProjectInspectorPanel)

### Unchanged

- `SidebarContainer(attachedEdge: .trailing, width: SidebarStyle.inspectorWidth)`
- Instructions section (collapsible)
- Scheduled section (collapsible)
- Context section with `FolderTreeView` (collapsible)
- Memory section with `MemorySummaryView` (collapsible)
- Same theme, styling, glass background, gradient borders

### New: Outputs Section

Inserted above Context, below Scheduled.

- Collapsible, using `CollapsibleSection`
- Shows `SharedArtifact` items from work tasks belonging to this project
- Query: `IssueStore` for artifacts where parent work task has `projectId == activeProjectId`
- Each row: file icon (based on mime type), filename, file size — same style as other inspector rows
- Tap: opens existing `ArtifactViewerSheet`
- Empty state: icon + "No outputs yet", same pattern as other sections

**Section order:**

1. Instructions
2. Scheduled
3. Outputs (new)
4. Context
5. Memory

## Shared Component Extraction

### From `ChatSessionSidebar.swift`

- `SessionRow` → `Views/Sidebar/SessionRow.swift` (private → internal)
- All features preserved: agent dot/letter, inline rename TextField, hover actions (pencil + trash), context menu (rename, delete, open in new window)
- `ChatSessionSidebar` imports and uses the shared version

### From `WorkTaskSidebar.swift`

- `TaskRow` → `Views/Sidebar/TaskRow.swift` (private → internal)
- All features preserved: `MorphingStatusIcon`, hover trash, context menu (delete)
- `WorkTaskSidebar` imports and uses the shared version

### From `WorkView.swift`

- `WorkPulseModifier` → `Views/Common/WorkPulseModifier.swift` (private → internal)
- `WorkStatusButton` → `Views/Common/WorkStatusButton.swift` (private → internal)
- `ClarificationOverlay` → `Views/Common/ClarificationOverlay.swift` (private → internal)
- `WorkView` imports and uses the shared versions
- `ProjectView` uses the same shared versions (no duplication)

### ChatView.swift — NOT extracted

`ChatView` is ~1300 lines. Rather than extracting a `ChatContentArea` wrapper, `ProjectView` composes the same building blocks directly: `MessageThreadView`, `FloatingInputCard`, `ScrollToBottomButton`, empty state components. These are already standalone reusable views.

Similarly for Work content: `ProjectView` composes `WorkEmptyState`, `MessageThreadView`, `FloatingInputCard`, `IssueTrackerPanel`, `WorkStatusButton`, etc. directly.

## File Changes

### Files DELETED (3)

| File                                         | Reason                                                      |
| -------------------------------------------- | ----------------------------------------------------------- |
| `Views/Projects/ProjectHomeView.swift`       | Replaced by direct chat/work content rendering              |
| `Views/Projects/ProjectInlineChatView.swift` | Replaced by composing shared building blocks in ProjectView |
| `Views/Projects/ProjectInlineWorkView.swift` | Replaced by composing shared building blocks in ProjectView |

### Files CREATED (5)

| File                                      | Purpose                                                |
| ----------------------------------------- | ------------------------------------------------------ |
| `Views/Sidebar/SessionRow.swift`          | Shared session row (extracted from ChatSessionSidebar) |
| `Views/Sidebar/TaskRow.swift`             | Shared task row (extracted from WorkTaskSidebar)       |
| `Views/Common/WorkPulseModifier.swift`    | Shared pulse animation (extracted from WorkView)       |
| `Views/Common/WorkStatusButton.swift`     | Shared status button (extracted from WorkView)         |
| `Views/Common/ClarificationOverlay.swift` | Shared clarification UI (extracted from WorkView)      |

### Files MODIFIED (7)

| File                                         | Changes                                                                                                                                                         |
| -------------------------------------------- | --------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `Views/Projects/ProjectView.swift`           | Rewritten: center content renders chat or work based on `subMode`, Chat/Work picker, full-bleed layout matching Chat/Work tabs                                  |
| `Views/Projects/ProjectInspectorPanel.swift` | Add Outputs section above Context                                                                                                                               |
| `Views/Sidebar/AppSidebar.swift`             | Replace `RecentRow` with `ProjectRecentItem` using shared `SessionRow`/`TaskRow`, add work task querying                                                        |
| `Views/Chat/ChatSessionSidebar.swift`        | Remove private `SessionRow`, import shared version                                                                                                              |
| `Views/Work/WorkTaskSidebar.swift`           | Remove private `TaskRow`, import shared version                                                                                                                 |
| `Views/Work/WorkView.swift`                  | Remove private pulse/status/clarification views, import shared versions                                                                                         |
| `Managers/Chat/ChatWindowState.swift`        | Simplify `ProjectSession` (remove inline fields, add `subMode`), simplify `NavigationEntry` (remove `workTaskId`), update `switchMode`/`restoreNavigationEntry` |

### Tests

| File                                         | Changes                                                                                  |
| -------------------------------------------- | ---------------------------------------------------------------------------------------- |
| `Tests/Project/ProjectNavigationTests.swift` | Update for simplified `ProjectSession` and `NavigationEntry`, add `ProjectSubMode` tests |
| `Tests/Project/NavigationStackTests.swift`   | Update any references to `workTaskId` in `NavigationEntry` if present                    |

## Code Cleanup

### Dead Code Removal

- `ProjectInputMode` enum — deleted with `ProjectHomeView.swift`
- `RecentRow` struct — replaced in `AppSidebar.swift`
- `InlineWorkPulseModifier` — deleted with `ProjectInlineWorkView.swift`
- Duplicated `WorkStatusButton` and `ClarificationOverlay` — deleted with `ProjectInlineWorkView.swift`
- `formatRelativeDate` — verify sole usage; remove if orphaned

### Grep Sweep (zero references expected)

- `inlineSessionId`
- `inlineWorkTaskId`
- `hasInlineContent`
- `ProjectInputMode`
- `ProjectHomeView`
- `ProjectInlineChatView`
- `ProjectInlineWorkView`
- `InlineWorkPulseModifier`

### Reference Updates

- `ChatWindowState.restoreNavigationEntry` — remove `workTaskId` handling, simplify to sub-mode logic
- `ProjectView.onChange(of: session.inlineWorkTaskId)` — delete, replace with sub-mode-driven tool registration
- `AppSidebar` `RecentRow` tap handler — simplify, no "inline" branching

## Session Tagging (unchanged)

- `ChatSession.projectId` is set when creating a session from within a project
- `toSessionData()` includes `projectId: projectId ?? ProjectManager.shared.activeProjectId`
- Memory scoping uses `projectId` for union queries: `WHERE agent_id = ? AND (project_id = ? OR project_id IS NULL)`
- Knowledge graph entities/relationships remain globally unscoped

## What This Does NOT Change

- Chat tab — completely untouched (routing, sidebar, content, behavior)
- Work tab — completely untouched (routing, sidebar, content, behavior)
- Toolbar — same items, same centering, inspector button still gated by `.project` mode
- Project model (`Project.swift`) — no field changes
- `ProjectManager` — no changes
- `ProjectListView` — no changes
- `ProjectEditorSheet` — no changes
- `FloatingInputCard` — no changes
- `MessageThreadView` — no changes
- `SharedSidebarComponents` — no changes
- `CollapsibleSection` — no changes
- `FolderTreeView` — no changes
- Memory system — no changes (project scoping already implemented)
- Identity/auth — no changes
