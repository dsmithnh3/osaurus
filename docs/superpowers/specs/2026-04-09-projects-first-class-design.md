# Projects as a First-Class Concept — Design Spec

**Date:** 2026-04-09
**Status:** Approved
**Author:** Daniel Smith + Claude

## Overview

Add Projects as a first-class organizational concept to Osaurus, inspired by Claude Cowork's project model. A Project groups conversations, work tasks, schedules, watchers, and memory under a shared context with a linked folder, instructions, and scoped memory. Projects become a third mode alongside Chat and Work, accessible from the toolbar and sidebar.

## Goals

- Give users a dedicated home screen per project with outputs, recents, instructions, scheduled tasks, context files, and memory
- Scope conversations, work tasks, schedules, watchers, and memory to projects
- Preserve the full power of both Chat and Work modes — Projects is a launcher, not a replacement
- Follow native macOS UI conventions throughout (Apple HIG, NSToolbar, system typography, accessibility)
- Maximize reuse of existing components (FloatingInputCard, NativeArtifactCardView, SessionRow, TaskRow, SidebarRowBackground)

## Non-Goals

- Mobile companion / Dispatch (future feature)
- Cloud sync of projects (local only, like Cowork)
- Replacing or merging Chat and Work modes

---

## 1. Data Model & Storage

### Project Model

```swift
public struct Project: Identifiable, Codable, Sendable, Equatable {
    public let id: UUID
    public var name: String
    public var description: String?
    public var icon: String                 // SF Symbol name (default: "folder.fill")
    public var color: String?               // Hex accent color for UI

    // Folder
    public var folderPath: String?          // Resolved path
    public var folderBookmark: Data?        // Security-scoped bookmark for sandbox access

    // Instructions
    public var instructions: String?        // Project-level system prompt additions

    // State
    public var isActive: Bool
    public var isArchived: Bool

    // Timestamps
    public let createdAt: Date
    public var updatedAt: Date
}
```

**New file:** `Packages/OsaurusCore/Models/Project/Project.swift`

### Persistence

- **ProjectStore** — JSON file storage at `~/.osaurus/projects/*.json`, following the existing `AgentStore` pattern (file per project, UUID filename)
- **New file:** `Packages/OsaurusCore/Models/Project/ProjectStore.swift`

### Context File Discovery

- Scan the project folder recursively for **all `.md` files** (not just named ones)
- Osaurus has **full read/write access** to project folder files via the security-scoped bookmark
- Context files are injected into the system prompt and agents can update them (e.g., adding notes, updating status files)
- File tree displayed in the right inspector panel's Context section

### Security-Scoped Bookmark Lifecycle

The `folderBookmark` on `Project` is a security-scoped bookmark granting sandbox-safe access to the user-chosen folder. Lifecycle:

1. **Creation:** When user picks a folder via `NSOpenPanel`, call `url.bookmarkData(options: .withSecurityScope)` and store in `project.folderBookmark`
2. **Start access:** Call `url.startAccessingSecurityScopedResource()` when:
   - Entering a project (setting `activeProjectId`)
   - Building system prompt context (scanning `.md` files)
   - Agent writes to a context file
3. **Stop access:** Call `url.stopAccessingSecurityScopedResource()` when:
   - Leaving a project (clearing `activeProjectId` or switching to another project)
   - App enters background / window closes
4. **Staleness:** If `URL(resolvingBookmarkData:)` returns `isStale == true`, re-prompt user via `NSOpenPanel` to re-authorize, then update the bookmark
5. **Scope:** `ProjectManager` owns the start/stop lifecycle, ensuring balanced calls via a `Set<UUID>` of currently-accessed project IDs

### Database Changes

**WorkDatabase V5 migration** — relational tables for project associations. **Implementation note:** The source code constant `WorkDatabase.schemaVersion` is stale at `2`, but the migration ladder already runs to V4 (via `currentVersion < 4` branches). The new migration must add a `currentVersion < 5` branch AND update the constant to `5`:

```sql
-- Project-agent associations (many-to-many)
CREATE TABLE project_agents (
    project_id TEXT NOT NULL,
    agent_id TEXT NOT NULL,
    added_at TEXT NOT NULL DEFAULT (datetime('now')),
    PRIMARY KEY (project_id, agent_id)
);

CREATE INDEX idx_project_agents_agent ON project_agents(agent_id);
```

**Note:** No `project_issues` join table — project association for issues/tasks/sessions is handled via the `projectId` field on each model (see below). This avoids a duplicated join mechanism. Agents are the exception because they have a many-to-many relationship with projects (an agent can belong to multiple projects).

**Optional `projectId` added to existing models** (backwards-compatible):

| Model             | File                                | Field Added            |
| ----------------- | ----------------------------------- | ---------------------- |
| `ChatSessionData` | `Models/Chat/ChatSessionData.swift` | `var projectId: UUID?` |
| `Schedule`        | `Models/Schedule/Schedule.swift`    | `var projectId: UUID?` |
| `Watcher`         | `Models/Watcher/Watcher.swift`      | `var projectId: UUID?` |
| `WorkTask`        | `Models/Work/WorkModels.swift`      | `var projectId: UUID?` |

All existing data retains `projectId = nil` (workspace-global). Fully backwards compatible.

### Memory Scoping

The memory system is agent-scoped today. Projects adds a second scoping dimension.

**MemoryDatabase V4 migration** (current schema is V3) — add `project_id` to memory tables:

```sql
ALTER TABLE memory_entries ADD COLUMN project_id TEXT;
ALTER TABLE conversation_summaries ADD COLUMN project_id TEXT;
ALTER TABLE conversations ADD COLUMN project_id TEXT;
ALTER TABLE entities ADD COLUMN project_id TEXT;
ALTER TABLE relationships ADD COLUMN project_id TEXT;

CREATE INDEX idx_memory_entries_agent_project ON memory_entries(agent_id, project_id);
CREATE INDEX idx_summaries_agent_project ON conversation_summaries(agent_id, project_id);
CREATE INDEX idx_conversations_agent_project ON conversations(agent_id, project_id);
```

**Layer-by-layer integration:**

| Layer                   | Change                                           | Rationale                                   |
| ----------------------- | ------------------------------------------------ | ------------------------------------------- |
| **L1 — User Profile**   | No change (stays global)                         | Profile describes the user, not a project   |
| **L2 — Working Memory** | Filter by `project_id`                           | Project-scoped facts + general facts        |
| **L3 — Summaries**      | Filter by `project_id`                           | Project conversations summarized separately |
| **L4 — Chunks**         | Filter via `conversations.project_id`            | Cascades through JOIN                       |
| **Knowledge Graph**     | Filter by `project_id` on entities/relationships | Project-scoped entities                     |

**Query pattern:** `WHERE agent_id = ? AND (project_id = ? OR project_id IS NULL)` — project-scoped entries PLUS workspace-global entries. Agents retain general knowledge while inside a project.

**Service changes:**

| Service                                     | Change                                                                                                               |
| ------------------------------------------- | -------------------------------------------------------------------------------------------------------------------- |
| `MemoryService.recordConversationTurn()`    | Add `projectId: String?` parameter                                                                                   |
| `MemorySearchService.searchMemoryEntries()` | Add `projectId: String?` filter                                                                                      |
| `MemorySearchService.searchConversations()` | Add `projectId: String?` filter                                                                                      |
| `MemorySearchService.searchSummaries()`     | Add `projectId: String?` filter                                                                                      |
| `MemoryContextAssembler.assembleContext()`  | Add `projectId: String?` parameter                                                                                   |
| `MemoryContextAssembler` cache key          | Update from `agentId` to composite `"\(agentId):\(projectId ?? "global")"` to prevent stale cross-project cache hits |
| `MemoryDatabase` load functions             | Add `AND (project_id = ? OR project_id IS NULL)`                                                                     |

**VecturaKit limitation:** The vector index has no `project_id` dimension — semantic search returns results across all projects. Project scoping is achieved by post-retrieval filtering: VecturaKit returns candidate IDs, then SQLite filters by `project_id`. This is acceptable at current scale (500 entries per agent cap) but may need a partitioned index if project counts grow significantly.

**No changes to:** token budgets (profile 2000, working memory 3000, summaries 3000, chunks 3000, graph 300), verification pipeline (3-layer dedup), profile regeneration (stays global, triggered after 10 contributions).

---

## 2. Navigation & Toolbar

### ChatMode Extension

```swift
public enum ChatMode: String, Codable, Sendable {
    case chat
    case work = "agent"
    case project          // NEW

    var displayName: String {
        switch self {
        case .chat: "Chat"
        case .work: "Work"
        case .project: "Projects"
        }
    }

    var icon: String {
        switch self {
        case .chat: "bubble.left.and.bubble.right"
        case .work: "bolt.circle"
        case .project: "folder.fill"
        }
    }
}
```

**File:** `Packages/OsaurusCore/Models/Chat/ChatMode.swift`

### Toolbar Layout

Extend the existing `ChatToolbarDelegate` (4 items → 6 items):

```
[●●●]  [⊞]  [←] [→]       [ 💬 Chat | ⚡ Work | 📁 Projects ]       [⚙]  [📌]
        │     │    │                      │                              │     │
   sidebar  back  fwd          ModeToggleButton (3 segments)         action   pin
   (exists) (NEW) (NEW)            (extend existing)               (exists) (exists)
```

**New toolbar items in `ChatToolbarDelegate`:**

- **backItem** (`"ChatToolbar.back"`) — positioned after sidebar toggle
- **forwardItem** (`"ChatToolbar.forward"`) — positioned after back

**Extended:** `ModeToggleButton` in `SharedHeaderComponents.swift` — add third segment for Projects. This is a breaking change:

1. `ModeToggleButton` has a **private** `enum Mode { case chat, work }` — must add `.project` case
2. Callback signature is binary (`onChat`/`onWork` closures) — must change to a single `onChange: (ChatMode) -> Void` callback
3. **3 call sites** reference the current binary callback — all must be updated to the new signature
4. **Visible UI change:** The Work segment icon changes from `bolt.fill` (currently hardcoded in `ModeToggleButton.segment()`) to `bolt.circle` (from `ChatMode.icon`). This aligns the toggle with the canonical `ChatMode` enum.

**Files:** `Packages/OsaurusCore/Managers/Chat/ChatWindowManager.swift` (toolbar delegate), `Packages/OsaurusCore/Views/Common/SharedHeaderComponents.swift` (mode toggle)

### Navigation Stack

Add to `ChatWindowState`:

```swift
struct NavigationEntry: Equatable {
    let mode: ChatMode
    let projectId: UUID?        // nil = general / project list
    let sessionId: UUID?        // nil = project home (not in a conversation)
}

private var navigationStack: [NavigationEntry] = []
private var navigationIndex: Int = -1

var canGoBack: Bool { navigationIndex > 0 }
var canGoForward: Bool { navigationIndex < navigationStack.count - 1 }
```

Navigation entries pushed when: user switches modes, selects a project, opens a conversation from project recents, or creates a new chat/task from project home. Back/forward traverse the stack.

**File:** `Packages/OsaurusCore/Managers/Chat/ChatWindowState.swift`

### Mode Switching

Extend `ChatWindowState.switchMode(to:)` with `.project` case:

```swift
case .project:
    if mode == .chat && !session.turns.isEmpty { session.save() }
    if mode == .work { WorkToolManager.shared.unregisterTools() }
    mode = .project
    if projectSession == nil {
        projectSession = ProjectSession()
    }
```

**`ProjectSession` observability:** `ChatWindowState` is `ObservableObject` (NOT `@Observable`). `ProjectSession` must be a **plain struct** stored as `@Published var projectSession: ProjectSession?` on `ChatWindowState`. It must NOT be `@Observable`. This follows the same pattern as other state on `ChatWindowState`.

```swift
// On ChatWindowState:
@Published public var projectSession: ProjectSession?
@Published public var sidebarContentMode: SidebarContentMode = .chat

// ProjectSession is a plain struct:
public struct ProjectSession: Equatable {
    public var activeProjectId: UUID?
    public var showInspector: Bool = true
}
```

**File:** `Packages/OsaurusCore/Managers/Chat/ChatWindowState.swift` (ProjectSession defined here alongside the class that owns it, or in `Models/Project/ProjectSession.swift`)

### Chat vs Work Routing from Project Input

When the user sends a message from `ProjectHomeView`'s `FloatingInputCard`, the system must decide whether to create a Chat session or Work task:

- **Default:** Create a new Chat session (`ChatSessionData` with `projectId` set)
- **Explicit Work trigger:** If the message matches Work-mode intent signals (e.g., user selects "Work" from a mode picker on the input card, or the message begins with a recognized command prefix), create a Work task instead
- **v1 simplification:** Always create a Chat session. Add a small mode picker (segmented control) to the `FloatingInputCard` in project home to let users explicitly choose Work mode. This avoids ambiguous AI-based routing.

### View Routing

Extend `ChatView.body`:

```swift
var body: some View {
    Group {
        if windowState.mode == .project, let projectSession = windowState.projectSession {
            ProjectView(windowState: windowState, session: projectSession)
        } else if windowState.mode == .work, let workSession = windowState.workSession {
            WorkView(windowState: windowState, session: workSession)
        } else {
            chatModeContent
        }
    }
}
```

**File:** `Packages/OsaurusCore/Views/Chat/ChatView.swift`

---

## 3. Sidebar Redesign

### Layout Structure

Replace the separate `ChatSessionSidebar` and `WorkTaskSidebar` with a unified `AppSidebar` that renders consistently across all three modes:

```
┌──────────────────────────┐
│  [+ New Chat]            │  existing button
│  [⌕ Search convos...]    │  existing search field
├──────────────────────────┤
│  ▣ Projects         (3)  │  nav item → sets sidebarContentMode = .projects
│  ⏱ Scheduled        (2)  │  nav item → sets sidebarContentMode = .scheduled
│  ⎕ Customize             │  nav item → opens Management window
├──────────────────────────┤
│  ┌────────────────────┐  │
│  │ 📁 CIMCO Refriger… ✕│  │  active project chip (only when project selected)
│  └────────────────────┘  │
├──────────────────────────┤
│  ▾ Recents               │  collapsible header (state persisted to UserDefaults)
│    💬 [SessionRow]       │  existing chat row (agent indicator, rename, etc.)
│    ⚡ [TaskRow]          │  existing work row (spinning animation, status, etc.)
│    💬 [SessionRow]       │  both types interleaved by date
│    ...                   │
└──────────────────────────┘
```

### Behavior

**New Chat button:** When a project is active, creates a conversation with `projectId` set. When no project active, creates a general conversation (`projectId: nil`).

**Search field:** When a project is active, searches within that project's conversations. When no project, searches all.

**Nav items:**

- **Projects** — sets `sidebarContentMode = .projects`, main content shows project list
- **Scheduled** — sets `sidebarContentMode = .scheduled`, main content shows schedules (filtered to active project if set)
- **Customize** — calls `AppDelegate.shared?.showManagementWindow()`, no mode change

**Active project chip:** Visible when `projectManager.activeProjectId != nil`. Shows project icon + name. X button clears `activeProjectId` and returns to unfiltered view.

**Recents (collapsible):**

- Toggle state persisted to UserDefaults (`isRecentsExpanded`)
- When no project active: all conversations and work tasks, interleaved by date
- When project active: only that project's conversations and work tasks
- Both row types keep their existing components with full animation fidelity

### Row Types Preserved

Chat `SessionRow` and Work `TaskRow` are **fundamentally different components** and remain separate:

| Aspect         | SessionRow (Chat)                  | TaskRow (Work)                                                   |
| -------------- | ---------------------------------- | ---------------------------------------------------------------- |
| Left icon      | Agent indicator (color-coded)      | Morphing status icon (4 animated states including 60fps spinner) |
| Actions        | 2 hover buttons (rename + delete)  | 1 hover button (delete)                                          |
| Context menu   | Open in New Window, Rename, Delete | Delete only                                                      |
| Inline editing | Full rename mode with TextField    | None                                                             |

Both use the shared `SidebarRowBackground` for selection/hover styling.

### SidebarContentMode

New enum on `ChatWindowState`:

```swift
public enum SidebarContentMode {
    case chat           // Normal conversation view
    case projects       // Project list in main content
    case scheduled      // Schedule management in main content
}
```

**Relationship to `ChatMode`:** `SidebarContentMode` controls what the **main content area** shows when the user clicks a sidebar nav item. It is orthogonal to `ChatMode` — `ChatMode` drives which engine is active (Chat/Work/Project), while `SidebarContentMode` drives the content panel routing. State machine:

- Clicking "Projects" nav → `sidebarContentMode = .projects`, `mode` unchanged until user selects a project
- Selecting a project → `mode = .project`, `sidebarContentMode = .chat` (returns to normal)
- Clicking "Scheduled" nav → `sidebarContentMode = .scheduled`, `mode` unchanged
- Clicking a conversation in Recents → `sidebarContentMode = .chat`, `mode = .chat` or `.work` based on row type

`SidebarContentMode` resets to `.chat` whenever `ChatMode` changes via `switchMode(to:)`.

Nav items change the **main content area**, not the sidebar itself. The sidebar always shows the same structure.

**New file:** `Packages/OsaurusCore/Views/Sidebar/AppSidebar.swift`

---

## 4. Project View (3-Panel Layout)

### Panel Structure

When inside a project, the main content becomes a 3-panel layout:

```
┌─────────────┬──────────────────────────────────┬────────────────────┐
│  AppSidebar │       Center Content             │  Right Inspector   │
│  (240pt)    │       (Project Home)             │  (300pt, overlay)  │
│             │       (flexible width)           │                    │
│  Nav items  │  Project name (.title font)      │  ▾ Instructions    │
│  ─────────  │  "What would you like to         │    (editable text) │
│  Project    │   work on in this project?"      │                    │
│  chip       │  [📁 folder path]  [⚙] [+]      │  ▾ Scheduled       │
│  ─────────  │                                  │    (project tasks) │
│  ▾ Recents  │  FloatingInputCard               │                    │
│    Chat 1   │                                  │  ▾ Context         │
│    Task 1   │  Outputs (horizontal card grid)  │    📁 folder tree  │
│    Chat 2   │  ┌────┐ ┌────┐ ┌────┐ ┌────┐    │    (all .md files) │
│    ...      │  │ 📄 │ │ 📊 │ │ 📋 │ │ 📄 │    │                    │
│             │  └────┘ └────┘ └────┘ └────┘    │  ▾ Memory          │
│             │                                  │    🧠 entries list  │
│             │  Recents (expanded list)         │    📊 graph entities│
│             │  ┌─ Chat: Denka Hammond ov...    │                    │
│             │  ├─ Task: Create transmit...     │                    │
│             │  └─ ...                          │                    │
└─────────────┴──────────────────────────────────┴────────────────────┘
```

### Center Panel — Project Home

**Header area:**

- Project name as `.title` font (20pt), matching Finder window titles
- Subtitle: "What would you like to work on in this project?"
- Folder path chip (clickable — reveals in Finder)
- Action buttons: settings gear, new conversation (+)

**Chat input:**

- Reuses existing `FloatingInputCard` — must pass all current init params including slash-command support (`onClearChat`, `onSkillSelected`, `pendingSkillId`) added in v0.16.9 (#822)
- Slash commands work naturally in the project input (skills, templates, and actions all apply)
- Sending a message creates a new Chat session or Work task scoped to the project, then navigates into it (pushes to navigation stack, switches mode)

**Outputs section:**

- Horizontal scrolling card grid of `SharedArtifact`s from this project's conversations and work tasks
- Reuses existing `NativeArtifactCardView` rendering
- Query: artifacts from project-scoped sessions/issues, ordered by `created_at DESC`, limit 8
- Clicking an output opens it or navigates to the source conversation

**Recents section:**

- Interleaved `SessionRow` / `TaskRow` list (same components as sidebar)
- More horizontal room allows richer row content (preview text, artifact count)
- Clicking navigates into the conversation/task (pushes to nav stack, switches to Chat or Work mode)

### Right Inspector Panel

Follows the **overlay pattern** from Work mode's `IssueTrackerPanel` (280-300pt, slides in from right). v1 uses overlay; future polish may migrate to `NSSplitView` for resizable dividers (see Future Polish section).

All sections use a reusable `CollapsibleSection` component with chevron toggle:

**Instructions section:**

- Edit icon (pencil) in header
- Shows `project.instructions` as markdown
- Inline text editor on edit tap
- Agents can update during execution via tool calls

**Scheduled section:**

- \+ button in header
- Lists schedules where `schedule.projectId == project.id`
- \+ creates a new schedule pre-scoped to this project
- Each row: name, frequency, next run time

**Context section:**

- \+ button in header (opens NSOpenPanel for additional folders)
- "On your computer" header
- Folder tree browser (`FolderTreeView`) showing project directory contents
- All `.md` files indicated as context-injected
- Full read/write access via security-scoped bookmark

**Memory section:**

- Project-scoped Layer 2 entries (working memory) with type/count
- Knowledge graph entities related to this project
- Tapping an entry shows content, confidence, source conversation

**Inspector toggle:**

- Visible by default when entering a project
- Toggle button in project header area
- State persisted per-window: `@Published var showProjectInspector: Bool` on `ChatWindowState`
- Spring animation in/out

### New Components

| Component               | Purpose                                                                            | File                                                                                    |
| ----------------------- | ---------------------------------------------------------------------------------- | --------------------------------------------------------------------------------------- |
| `ProjectView`           | 3-panel coordinator                                                                | `Views/Projects/ProjectView.swift`                                                      |
| `ProjectHomeView`       | Center panel content                                                               | `Views/Projects/ProjectHomeView.swift`                                                  |
| `ProjectInspectorPanel` | Right panel with collapsible sections                                              | `Views/Projects/ProjectInspectorPanel.swift`                                            |
| `ProjectListView`       | Project grid with search + "New project" button                                    | `Views/Projects/ProjectListView.swift`                                                  |
| `ProjectEditorSheet`    | Sheet for creating/editing project metadata                                        | `Views/Projects/ProjectEditorSheet.swift`                                               |
| `ProjectSession`        | Plain struct for active project state (owned by `ChatWindowState` as `@Published`) | `Managers/Chat/ChatWindowState.swift` (inline) or `Models/Project/ProjectSession.swift` |
| `FolderTreeView`        | Recursive directory tree browser                                                   | `Views/Projects/FolderTreeView.swift`                                                   |
| `MemorySummaryView`     | Compact memory entry list                                                          | `Views/Projects/MemorySummaryView.swift`                                                |
| `CollapsibleSection`    | Reusable collapsible header + content                                              | `Views/Common/CollapsibleSection.swift`                                                 |
| `SidebarNavRow`         | Reusable sidebar navigation item                                                   | `Views/Sidebar/SidebarNavRow.swift`                                                     |
| `AppSidebar`            | Unified sidebar replacing Chat/Work sidebars                                       | `Views/Sidebar/AppSidebar.swift`                                                        |

### Existing Components Reused

| Component                | Where Reused                                                          |
| ------------------------ | --------------------------------------------------------------------- |
| `FloatingInputCard`      | Project home input                                                    |
| `NativeArtifactCardView` | Outputs card grid                                                     |
| `SessionRow`             | Sidebar recents + center recents                                      |
| `TaskRow`                | Sidebar recents + center recents (full spinning animations preserved) |
| `SidebarRowBackground`   | All row backgrounds                                                   |
| `SidebarSearchField`     | Project list search, sidebar search                                   |

---

## 5. System Prompt Integration

When a project is active, inject project context into the system prompt via `SystemPromptComposer`:

```swift
// After agent prompt, before memory context:
if let projectId = activeProjectId,
   let projectContext = await ProjectManager.shared.projectContext(for: projectId) {
    sections.append("""
    <project-context>
    \(projectContext)
    </project-context>
    """)
}
```

`ProjectManager.projectContext(for:)` builds the context string from:

1. `project.instructions` (if set)
2. All `.md` files discovered in the project folder (recursive scan)

**File:** `Packages/OsaurusCore/Services/SystemPromptComposer.swift`

---

## 6. ProjectManager

```swift
@Observable
@MainActor
public final class ProjectManager {
    public static let shared = ProjectManager()

    public private(set) var projects: [Project] = []
    public var activeProjectId: UUID?

    public var activeProject: Project? {
        projects.first { $0.id == activeProjectId }
    }

    public var activeProjects: [Project] {
        projects.filter { $0.isActive && !$0.isArchived }
    }

    // CRUD: create, update, archive, delete
    // Context: contextFiles(for:), projectContext(for:)
    // Associations: assignAgents, agentsInProject, issuesInProject
}
```

**New file:** `Packages/OsaurusCore/Managers/ProjectManager.swift`

---

## 7. Native macOS UI Conventions

### Layout Framework

- Right inspector uses **overlay pattern** (v1) matching Work mode's `IssueTrackerPanel`
- Left sidebar uses existing 240pt fixed-width pattern with spring animation toggle

### Spacing & Margins (Apple HIG)

- Content margins: 20pt standard, 16pt in compact areas
- Section spacing: 12pt between related items, 20pt between sections
- Row padding: 8-10pt vertical, 12-16pt horizontal
- Corner radii: 8pt for cards/rows, 12pt for larger containers
- Icon sizes: 13pt sidebar nav, 16pt toolbar, 24pt row indicators

### Native Components

| UI Element                 | Implementation                                                         |
| -------------------------- | ---------------------------------------------------------------------- |
| Collapsible sections       | `DisclosureGroup` with custom styling (System Settings pattern)        |
| Folder tree                | `OutlineGroup` or `List` with `DisclosureGroup` (Finder/Xcode pattern) |
| Project list               | `List` with `.inset(alternatesRowBackgrounds: false)`                  |
| Inspector toggle           | `NSToolbarItem` (Xcode inspector pattern)                              |
| Project creation           | `.sheet` modifier (system standard modal)                              |
| Inline instructions editor | `TextEditor` with `.scrollContentBackground(.hidden)`                  |
| Folder picker              | `NSOpenPanel` with `canChooseDirectories: true`                        |

### Typography (macOS type scale)

- Project name: `.title` (20pt)
- Section headers: `.headline` (13pt semibold)
- Row titles: 12pt medium (matching existing sidebar)
- Secondary text: `.subheadline` (11pt)
- Badges: `.caption2` (10pt)

### Accessibility

- All interactive elements: `.accessibilityLabel` and `.accessibilityHint`
- Keyboard navigation: Tab through nav items, arrow keys in lists
- VoiceOver: `.accessibilityAddTraits(.isButton)` on collapsible sections
- `reduceMotion`: respect for spinning/morphing animations
- Dynamic Type support

---

## 8. Interaction Flows

### Creating a Project

1. User clicks "Projects" in sidebar nav
2. Main content shows `ProjectListView` with "New project" button
3. User clicks "New project" → `ProjectEditorSheet` appears as sheet
4. User enters: name, description, icon, color, folder (via NSOpenPanel)
5. Save creates `Project` in `ProjectStore`, creates security-scoped bookmark
6. Project appears in list

### Entering a Project

1. User clicks a project in `ProjectListView`
2. `projectManager.activeProjectId` set
3. Sidebar shows project chip + filtered Recents
4. Main content shows `ProjectHomeView` (3-panel with inspector)
5. Navigation stack pushes entry

### Working in a Project

1. User types in `FloatingInputCard` on project home
2. Message creates a new `ChatSessionData` with `projectId` set (or `WorkTask` with `projectId`)
3. App switches to Chat or Work mode (navigation stack push)
4. All memory recorded with `projectId`
5. User clicks back (toolbar) → returns to project home

### Leaving a Project

1. User clicks X on project chip in sidebar → clears `activeProjectId`
2. OR user clicks "Projects" nav item → returns to project list
3. OR user clicks back until reaching project list
4. Sidebar Recents returns to showing all conversations

---

## 9. Future Polish

> **Note:** v1 uses the overlay approach for the right inspector panel (matching Work mode's `IssueTrackerPanel` pattern). This is less invasive and consistent with existing code. A future polish pass should evaluate migrating the 3-panel layout to `NSSplitView` (or SwiftUI `HSplitView`) for native resizable dividers, autosave of panel widths, and full-screen / Stage Manager support — matching the pattern used by Mail, Notes, and Xcode.

Other future considerations:

- Project export/import (JSON bundle with folder reference)
- Project templates (pre-configured instructions + schedules)
- Project sharing (if multi-user support is added)
- Drag-and-drop reordering in project list
