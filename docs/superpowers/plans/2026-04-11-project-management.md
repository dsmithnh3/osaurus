# Project Management Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Complete the missing project-management workflow so users can create, edit, archive, unarchive, and safely delete projects through native macOS context menus and the existing project sheet, without changing the inspector or touching memory.

**Architecture:** Reuse existing boundaries. `ProjectManager` owns lifecycle semantics, `ProjectEditorSheet` becomes the single metadata/settings surface, `ProjectListView` becomes the archived-project browsing surface, and sidebar/project-list rows gain native context menus as the only management entry point. Window-state reconciliation is handled in `ChatWindowState` so archiving or deleting an open project cannot leave stale UI state behind.

**Tech Stack:** Swift 6.2, SwiftUI, Observation, existing `Testing` package tests in `Packages/OsaurusCore/Tests/Project`, Osaurus JSON store patterns.

---

## File Map

### Existing files to modify

- `Packages/OsaurusCore/Managers/ProjectManager.swift`
  Responsibility: authoritative project lifecycle operations and active-project reconciliation.
- `Packages/OsaurusCore/Managers/WatcherManager.swift`
  Responsibility: disable project-owned watchers during archive through existing `setEnabled` support.
- `Packages/OsaurusCore/Managers/ScheduleManager.swift`
  Responsibility: disable project-owned schedules during archive through existing `setEnabled` support.
- `Packages/OsaurusCore/Managers/Chat/ChatWindowState.swift`
  Responsibility: window-level project/session state, behavior when a current project is archived or deleted.
- `Packages/OsaurusCore/Views/Projects/ProjectEditorSheet.swift`
  Responsibility: new-project form and existing-project settings sheet.
- `Packages/OsaurusCore/Views/Projects/ProjectListView.swift`
  Responsibility: browse active/archived projects, open projects, launch settings, row context menus.
- `Packages/OsaurusCore/Views/Sidebar/AppSidebar.swift`
  Responsibility: quick-access active project rows and their context menus.
- `Packages/OsaurusCore/Tests/Project/ProjectManagerTests.swift`
  Responsibility: manager semantics for create/archive/unarchive/delete.
- `Packages/OsaurusCore/Tests/Project/ProjectNavigationTests.swift`
  Responsibility: project navigation and window-state behavior.
- `docs/FEATURES.md`
  Responsibility: update shipped feature inventory after implementation.

### New files to create

- `Packages/OsaurusCore/Tests/Project/ProjectManagementViewTests.swift`
  Responsibility: UI-state and view-model-oriented tests for active/archived filtering and settings-sheet mode behavior.

---

### Task 1: Lock Down Lifecycle Semantics in `ProjectManager`

**Files:**
- Modify: `Packages/OsaurusCore/Managers/ProjectManager.swift`
- Modify: `Packages/OsaurusCore/Managers/WatcherManager.swift`
- Modify: `Packages/OsaurusCore/Managers/ScheduleManager.swift`
- Test: `Packages/OsaurusCore/Tests/Project/ProjectManagerTests.swift`

- [ ] **Step 1: Write failing manager tests for archive, unarchive, and safe delete**

Add tests covering:

```swift
@Test("Archive removes project from activeProjects but keeps it stored")
@MainActor
func archiveProjectRemovesFromActiveProjects() async throws {
    let manager = ProjectManager.shared
    let project = manager.createProject(name: "Archive \(UUID().uuidString.prefix(8))")
    defer { manager.deleteProject(id: project.id) }

    manager.archiveProject(id: project.id)

    #expect(manager.projects.contains(where: { $0.id == project.id }))
    #expect(!manager.activeProjects.contains(where: { $0.id == project.id }))
    #expect(manager.projects.first(where: { $0.id == project.id })?.isArchived == true)
}

@Test("Unarchive restores project to activeProjects")
@MainActor
func unarchiveProjectRestoresToActiveProjects() async throws {
    let manager = ProjectManager.shared
    let project = manager.createProject(name: "Restore \(UUID().uuidString.prefix(8))")
    defer { manager.deleteProject(id: project.id) }

    manager.archiveProject(id: project.id)
    manager.unarchiveProject(id: project.id)

    #expect(manager.activeProjects.contains(where: { $0.id == project.id }))
    #expect(manager.projects.first(where: { $0.id == project.id })?.isArchived == false)
}

@Test("Archive disables project-owned automations")
@MainActor
func archiveDisablesProjectOwnedAutomations() async throws {
    let manager = ProjectManager.shared
    let project = manager.createProject(name: "Ops \(UUID().uuidString.prefix(8))")
    defer { manager.deleteProject(id: project.id) }

    let watcher = WatcherManager.shared.create(
        name: "Watcher \(UUID().uuidString.prefix(8))",
        instructions: "Watch",
        isEnabled: true
    )
    var updatedWatcher = watcher
    updatedWatcher.projectId = project.id
    WatcherManager.shared.update(updatedWatcher)
    defer { _ = WatcherManager.shared.delete(id: watcher.id) }

    let schedule = ScheduleManager.shared.create(
        name: "Schedule \(UUID().uuidString.prefix(8))",
        instructions: "Run",
        frequency: .daily(hour: 9, minute: 0),
        isEnabled: true
    )
    var updatedSchedule = schedule
    updatedSchedule.projectId = project.id
    ScheduleManager.shared.update(updatedSchedule)
    defer { _ = ScheduleManager.shared.delete(id: schedule.id) }

    manager.archiveProject(id: project.id)

    #expect(WatcherManager.shared.watcher(for: watcher.id)?.isEnabled == false)
    #expect(ScheduleManager.shared.schedule(for: schedule.id)?.isEnabled == false)
}

@Test("Safe delete removes project record but not linked folder or memory")
@MainActor
func safeDeleteLeavesFolderAndMemoryUntouched() async throws {
    let manager = ProjectManager.shared
    let tmp = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: tmp) }

    let project = manager.createProject(
        name: "Delete \(UUID().uuidString.prefix(8))",
        folderPath: tmp.path
    )

    let beforeMemoryTotal = try? MemoryDatabase.shared.countEntriesByProject(projectId: project.id.uuidString).total
    manager.deleteProject(id: project.id)

    #expect(FileManager.default.fileExists(atPath: tmp.path))
    if let beforeMemoryTotal {
        let afterMemoryTotal = try? MemoryDatabase.shared.countEntriesByProject(projectId: project.id.uuidString).total
        #expect(afterMemoryTotal == beforeMemoryTotal)
    }
}
```

- [ ] **Step 2: Run only the manager tests to verify the new unarchive coverage fails**

Run: `swift test --package-path Packages/OsaurusCore --filter ProjectManagerTests`

Expected: FAIL because `unarchiveProject` does not exist yet and/or archive semantics are incomplete.

- [ ] **Step 3: Implement the minimal manager changes**

Modify `ProjectManager` to add:

- `archivedProjects` computed property:

```swift
public var archivedProjects: [Project] {
    projects.filter { $0.isArchived }
}
```

- `unarchiveProject(id:)`:

```swift
public func unarchiveProject(id: UUID) {
    guard var project = projects.first(where: { $0.id == id }) else { return }
    project.isArchived = false
    project.isActive = true
    updateProject(project)
}
```

- archive state handling:
  - clear `activeProjectId` if the affected project is currently active
  - disable project-owned watchers using `WatcherManager.shared.setEnabled(_, enabled: false)` for watchers whose `projectId == id`
  - disable project-owned schedules using `ScheduleManager.shared.setEnabled(_, enabled: false)` for schedules whose `projectId == id`
  - keep linked folder and memory untouched

- unarchive state handling:
  - restore `isArchived = false` and `isActive = true`
  - do **not** auto-resume watchers/schedules in this pass; leave them disabled so reactivation is explicit and safe

- safe delete semantics:
  - preserve existing bookmark cleanup on delete only
  - remove the project record and active-project state only
  - do not touch linked-folder contents
  - do not touch memory tables or memory graph state

- [ ] **Step 4: Run the manager tests again**

Run: `swift test --package-path Packages/OsaurusCore --filter ProjectManagerTests`

Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add Packages/OsaurusCore/Managers/ProjectManager.swift Packages/OsaurusCore/Managers/WatcherManager.swift Packages/OsaurusCore/Managers/ScheduleManager.swift Packages/OsaurusCore/Tests/Project/ProjectManagerTests.swift
git commit -m "feat: add project archive lifecycle semantics"
```

---

### Task 2: Reconcile Open-Project State in `ChatWindowState`

**Files:**
- Modify: `Packages/OsaurusCore/Managers/Chat/ChatWindowState.swift`
- Test: `Packages/OsaurusCore/Tests/Project/ProjectNavigationTests.swift`

- [ ] **Step 1: Write failing navigation/window-state tests**

Add tests for helper behavior such as:

```swift
@Test("Clearing current project state leaves window in safe non-project state")
@MainActor
func clearCurrentProjectState() {
    let state = ChatWindowState(windowId: UUID(), agentId: Agent.defaultId)
    let projectId = UUID()
    state.projectSession = ProjectSession(activeProjectId: projectId)
    state.mode = .project

    state.handleDeletedOrArchivedProject(projectId)

    #expect(state.projectSession == nil || state.projectSession?.activeProjectId == nil)
    #expect(state.mode != .project || state.projectSession?.activeProjectId == nil)
}
```

- [ ] **Step 2: Run the targeted navigation tests to verify failure**

Run: `swift test --package-path Packages/OsaurusCore --filter ProjectNavigationTests`

Expected: FAIL because helper behavior does not exist yet.

- [ ] **Step 3: Implement minimal window-state reconciliation**

Add a focused helper in `ChatWindowState`, for example:

```swift
@MainActor
func handleDeletedOrArchivedProject(_ projectId: UUID) {
    guard projectSession?.activeProjectId == projectId else { return }
    ProjectManager.shared.setActiveProject(nil)
    projectSession = nil
    if mode == .project {
        mode = .chat
        sidebarContentMode = .chat
        WorkToolManager.shared.unregisterTools()
    }
}
```

Use this helper from UI action closures after archive/delete succeeds so open windows do not keep stale project state.

- [ ] **Step 4: Run navigation tests again**

Run: `swift test --package-path Packages/OsaurusCore --filter ProjectNavigationTests`

Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add Packages/OsaurusCore/Managers/Chat/ChatWindowState.swift Packages/OsaurusCore/Tests/Project/ProjectNavigationTests.swift
git commit -m "fix: reconcile open project state on archive or delete"
```

---

### Task 3: Turn `ProjectEditorSheet` Into the Canonical Settings Surface

**Files:**
- Modify: `Packages/OsaurusCore/Views/Projects/ProjectEditorSheet.swift`
- Test: `Packages/OsaurusCore/Tests/Project/ProjectManagementViewTests.swift`

- [ ] **Step 1: Create failing sheet-behavior tests**

Create `ProjectManagementViewTests.swift` with tests covering real sheet-mode behavior, not just helper functions:

```swift
@Test("Project editor sheet resolves new-project mode")
func newProjectModeUsesCreateTitle() {
    let config = ProjectEditorSheet.ModeConfiguration(project: nil)
    #expect(config.title == "New Project")
    #expect(config.showsArchiveAction == false)
    #expect(config.showsDeleteAction == false)
}

@Test("Project editor sheet resolves existing-project mode")
func existingProjectModeUsesSettingsTitle() {
    let project = Project(name: "Existing")
    let config = ProjectEditorSheet.ModeConfiguration(project: project)
    #expect(config.title == "Project Settings")
    #expect(config.showsDeleteAction == true)
}

@Test("Existing archived project shows unarchive action")
func archivedProjectShowsUnarchiveAction() {
    var project = Project(name: "Archived")
    project.isArchived = true
    project.isActive = false

    let config = ProjectEditorSheet.ModeConfiguration(project: project)
    #expect(config.primaryArchiveActionLabel == "Unarchive")
}
```

Implement these through an internal pure configuration type or equivalent testable API owned by `ProjectEditorSheet`, rather than relying on private view internals.

- [ ] **Step 2: Run the new targeted tests**

Run: `swift test --package-path Packages/OsaurusCore --filter ProjectManagementViewTests`

Expected: FAIL because helper/mode behavior is not implemented yet.

- [ ] **Step 3: Implement the minimal settings-sheet behavior**

Modify `ProjectEditorSheet` to:

- distinguish new vs existing project mode clearly
- show `Project Settings` for existing projects
- preserve existing metadata editing behavior
- add existing-project-only action area with **state-aware** archive behavior and delete entry points, with closures passed in from callers:

```swift
var onArchive: ((Project) -> Void)? = nil
var onUnarchive: ((Project) -> Void)? = nil
var onDelete: ((Project) -> Void)? = nil
```

The sheet itself should not own destructive policy. It should present buttons only when `existingProject != nil`, and the button label must reflect current state:

- archived project: `Unarchive`
- active project: `Archive`

Also make the presentation state invalidatable from the parent view:

- `ProjectListView` and sidebar callers should drive settings presentation from an ID-driven source of truth such as `@State private var editingProjectId: UUID?`
- present settings with `sheet(item:)` or an equivalent item/ID-driven mechanism, not a simple boolean
- inside the sheet parent, resolve the project fresh from `ProjectManager.shared.projects` using `editingProjectId`
- if the project disappears or is no longer valid for editing, dismiss the sheet by clearing `editingProjectId`
- after archive/delete succeeds from the same sheet or row action, clear `editingProjectId`
- when changes happen elsewhere, add a refresh rule (`onChange`, manager observation, or equivalent) so the sheet dismisses or reloads when the backing project changes state in another window/code path

Do not move instructions editing here. Leave the inspector unchanged.

- [ ] **Step 4: Run the sheet tests**

Run: `swift test --package-path Packages/OsaurusCore --filter ProjectManagementViewTests`

Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add Packages/OsaurusCore/Views/Projects/ProjectEditorSheet.swift Packages/OsaurusCore/Tests/Project/ProjectManagementViewTests.swift
git commit -m "feat: reuse project editor sheet for project settings"
```

---

### Task 4: Add Archived Filtering and Context Menus to `ProjectListView`

**Files:**
- Modify: `Packages/OsaurusCore/Views/Projects/ProjectListView.swift`
- Modify: `Packages/OsaurusCore/Managers/Chat/ChatWindowState.swift`
- Test: `Packages/OsaurusCore/Tests/Project/ProjectManagementViewTests.swift`

- [ ] **Step 1: Extend tests for active/archived list behavior**

Add tests for list filtering plus action-routing behavior:

```swift
@Test("Project list filter returns archived projects when requested")
func archivedFilterReturnsArchivedProjects() {
    let active = Project(name: "Active")
    var archived = Project(name: "Archived")
    archived.isArchived = true
    archived.isActive = false

    let result = ProjectListFilter.archived.apply(to: [active, archived], searchText: "")
    #expect(result.map(\.name) == ["Archived"])
}

@Test("Project list action routing clears invalid settings sheet target on delete")
func deletingProjectClearsEditingProjectId() {
    let coordinator = ProjectManagementCoordinatorState()
    let projectId = UUID()
    coordinator.editingProjectId = projectId

    coordinator.handleProjectDeleted(projectId)

    #expect(coordinator.editingProjectId == nil)
}
```

Do **not** make `ProjectListFilter` private if tests depend on it. Keep it internal and testable, or move the filter logic to an internal helper type used by the view. If sheet/action coordination is factored out, prefer a small internal coordinator state type that is also directly testable.

- [ ] **Step 2: Run the project-management view tests to verify failure**

Run: `swift test --package-path Packages/OsaurusCore --filter ProjectManagementViewTests`

Expected: FAIL because list filtering helpers/mode do not exist yet.

- [ ] **Step 3: Implement list filtering and row management actions**

Modify `ProjectListView` to:

- add a small view state enum such as:

```swift
enum ProjectListFilter: String, CaseIterable {
    case active
    case archived
}
```

- render a simple `Picker` or segmented control for `Active | Archived`
- use `ProjectManager.shared.activeProjects` for active and `archivedProjects` for archived
- add context menus on project cards:
  - `Open`
  - `Edit Settings…`
  - `Archive` or `Unarchive`
  - `Delete…`

Route settings into `ProjectEditorSheet`, and route archive/delete through `ProjectManager` plus `windowState.handleDeletedOrArchivedProject(project.id)` as needed.

Drive settings presentation from a parent-owned optional project, for example:

```swift
@State private var editingProjectId: UUID?
```

Present the settings sheet with `sheet(item:)` or equivalent ID-driven presentation, resolving the current project from `ProjectManager` at presentation time.

When archive/delete succeeds from either the context menu or the sheet:

- clear `editingProjectId`
- clear any delete confirmation state tied to that project
- refresh the visible project list from `ProjectManager`

When the backing project changes elsewhere:

- if the project is deleted, dismiss the settings sheet
- if the project is archived and the sheet remains valid, reload the resolved project state so the primary action flips to `Unarchive`
- if the resolved project cannot be found, dismiss the sheet rather than leaving stale editable state on screen

Use a native confirmation for `Delete…`, but keep the deeper cleanup path out of scope.

- [ ] **Step 4: Run the tests**

Run: `swift test --package-path Packages/OsaurusCore --filter ProjectManagementViewTests`

Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add Packages/OsaurusCore/Views/Projects/ProjectListView.swift Packages/OsaurusCore/Managers/Chat/ChatWindowState.swift Packages/OsaurusCore/Tests/Project/ProjectManagementViewTests.swift
git commit -m "feat: add archived project browsing and project row menus"
```

---

### Task 5: Add Native Context Menus to Sidebar Project Rows

**Files:**
- Modify: `Packages/OsaurusCore/Views/Sidebar/AppSidebar.swift`
- Modify: `Packages/OsaurusCore/Views/Projects/ProjectEditorSheet.swift`
- Modify: `Packages/OsaurusCore/Managers/Chat/ChatWindowState.swift`
- Test: `Packages/OsaurusCore/Tests/Project/ProjectManagementViewTests.swift`

- [ ] **Step 1: Add a failing test or helper-level assertion for sidebar menu support**

If direct SwiftUI context-menu testing is awkward, add a pure helper for menu item availability, for example:

```swift
@Test("Active project sidebar menu includes archive")
func activeProjectMenuIncludesArchive() {
    let labels = SidebarProjectMenuItems.labels(isArchived: false, isActive: true)
    #expect(labels.contains("Archive"))
    #expect(labels.contains("Edit Settings…"))
}
```

- [ ] **Step 2: Run tests to verify failure**

Run: `swift test --package-path Packages/OsaurusCore --filter ProjectManagementViewTests`

Expected: FAIL because helper/menu definition does not exist yet.

- [ ] **Step 3: Implement sidebar context menus**

Modify `ProjectSidebarRow` in `AppSidebar.swift` to:

- keep current click-to-open behavior
- replace the current minimal `Deselect Project` menu with the canonical management menu for active projects:
  - `Open`
  - `Edit Settings…`
  - `Archive`
  - `Delete…`
- keep sidebar limited to active projects only

Use sheet presentation from the sidebar owner rather than embedding management UI in the row itself if needed. Keep the inspector unchanged.

- [ ] **Step 4: Run the tests**

Run: `swift test --package-path Packages/OsaurusCore --filter ProjectManagementViewTests`

Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add Packages/OsaurusCore/Views/Sidebar/AppSidebar.swift Packages/OsaurusCore/Views/Projects/ProjectEditorSheet.swift Packages/OsaurusCore/Managers/Chat/ChatWindowState.swift Packages/OsaurusCore/Tests/Project/ProjectManagementViewTests.swift
git commit -m "feat: add sidebar project management context menus"
```

---

### Task 6: Documentation and Verification

**Files:**
- Modify: `docs/FEATURES.md`

- [ ] **Step 1: Update feature docs to match shipped behavior**

Update the Projects section to state:

- inspector remains unchanged
- management is available through project-row context menus
- `ProjectEditorSheet` is used for both new projects and project settings
- archived projects are browsed in `ProjectListView`
- archive/delete do not touch memory

- [ ] **Step 2: Run targeted tests**

Run:

```bash
swift test --package-path Packages/OsaurusCore --filter ProjectManagerTests
swift test --package-path Packages/OsaurusCore --filter ProjectNavigationTests
swift test --package-path Packages/OsaurusCore --filter ProjectManagementViewTests
```

Expected: all PASS

- [ ] **Step 3: Run repo-required compile verification**

Run:

```bash
cd Packages/OsaurusCore && swift build 2>&1 | grep -E "error:" | grep -v "IkigaJSON"
```

Expected: no output

- [ ] **Step 4: Commit**

```bash
git add docs/FEATURES.md
git commit -m "docs: align projects feature docs with management flow"
```

---

## Notes for the Implementer

- Do not change `ProjectInspectorPanel` layout or responsibilities.
- Do not add a toolbar or header duplicate management path.
- Do not touch memory deletion in this feature.
- Do not delete the linked folder on disk.
- Prefer small internal helpers for testable UI-state logic when direct SwiftUI interaction is awkward.
- Follow the existing `Testing` style used in `Packages/OsaurusCore/Tests/Project`.
- Keep commits focused and task-scoped.
