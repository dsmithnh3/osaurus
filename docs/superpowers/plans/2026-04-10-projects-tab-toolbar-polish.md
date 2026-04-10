# Projects Tab, Toolbar & Visual Polish — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Fix Projects tab bugs, center the toolbar mode toggle, enable inline chat/work within projects, redesign the sidebar with stacked projects + unified recents, and unify all panel styling using the established `SharedSidebarComponents` design system.

**Architecture:** Layer 1 updates data models (`ProjectSession`, `NavigationEntry`, `SidebarStyle`). Layer 2 fixes the toolbar (`.principal` centering, inspector toggle, back/forward). Layer 3 redesigns the sidebar (stacked project list + unified recents). Layer 4 enables inline chat/work in `ProjectView`. Layer 5 unifies visual styling (`SidebarContainer` on inspector, `ThemedBackgroundLayer` on projects, empty state polish). Layer 6 cleans up all dead code. Each layer produces testable, committable increments.

**Tech Stack:** Swift 6.2, SwiftUI + AppKit hybrid (NSToolbar, NSHostingView), `SharedSidebarComponents` design system, `SidebarContainer`/`SidebarBackground`/`SidebarBorder`/`SidebarRowBackground`

**Spec:** `docs/superpowers/specs/2026-04-10-projects-tab-toolbar-polish-design.md`

---

## File Map

### Modified Files

| File | Change |
|---|---|
| `Managers/Chat/ChatWindowState.swift:32-53` | Remove `ProjectSession.showInspector`, add `inlineSessionId`/`inlineWorkTaskId`; add `NavigationEntry.workTaskId`; fix `restoreNavigationEntry` |
| `Managers/Chat/ChatWindowManager.swift:620-714` | `.principal` centering, add inspector toolbar item, remove `modeToggleItem` + flexibleSpaces |
| `Views/Management/SharedSidebarComponents.swift:45-65` | Add `width` parameter to `SidebarContainer`; add `SidebarStyle.inspectorWidth` |
| `Views/Common/CollapsibleSection.swift:41-42` | Update header font from `.headline` to `.system(size: 13, weight: .semibold)` |
| `Views/Sidebar/AppSidebar.swift` | Full rewrite: stacked project list + draggable divider + unified recents |
| `Views/Projects/ProjectView.swift` | 3-state routing (list/home/inline), `ThemedBackgroundLayer`, clip shape, `WorkToolManager` activation |
| `Views/Projects/ProjectHomeView.swift` | Mode picker on input, remove manual inspector toggle, `maxWidth: 1100`, empty state polish |
| `Views/Projects/ProjectInspectorPanel.swift` | Wrap in `SidebarContainer(attachedEdge: .trailing)`, remove manual bg/border |
| `Views/Projects/FolderTreeView.swift` | `.truncationMode(.middle)`, `SidebarRowBackground` for rows, width constraint |
| `Views/Projects/MemorySummaryView.swift` | `SidebarRowBackground` for rows |
| `Views/Chat/ChatView.swift:1293-1307` | No change needed — routing already delegates to `ProjectView` |

### Deleted Files

| File | Reason |
|---|---|
| `Views/Sidebar/SidebarNavRow.swift` | Only used by `AppSidebar.swift` nav items, which are removed |

---

## Task 1: Data Model Updates

**Files:**
- Modify: `Packages/OsaurusCore/Managers/Chat/ChatWindowState.swift:32-53`

- [ ] **Step 1: Update `ProjectSession` — remove `showInspector`, add inline fields**

In `ChatWindowState.swift`, replace lines 32-40:

```swift
/// Lightweight state for the active project context. Plain struct stored as
/// @Published on ChatWindowState (which is ObservableObject, not @Observable).
public struct ProjectSession: Equatable, Sendable {
    public var activeProjectId: UUID?

    // Inline session state — at most one is non-nil
    public var inlineSessionId: UUID?
    public var inlineWorkTaskId: UUID?

    public var hasInlineContent: Bool {
        inlineSessionId != nil || inlineWorkTaskId != nil
    }

    public init(activeProjectId: UUID? = nil) {
        self.activeProjectId = activeProjectId
    }
}
```

- [ ] **Step 2: Update `NavigationEntry` — add `workTaskId`**

In `ChatWindowState.swift`, replace lines 42-53:

```swift
/// Entry in the navigation stack for back/forward support.
public struct NavigationEntry: Equatable, Sendable {
    public let mode: ChatMode
    public let projectId: UUID?
    public let sessionId: UUID?
    public let workTaskId: UUID?

    public init(mode: ChatMode, projectId: UUID? = nil, sessionId: UUID? = nil, workTaskId: UUID? = nil) {
        self.mode = mode
        self.projectId = projectId
        self.sessionId = sessionId
        self.workTaskId = workTaskId
    }
}
```

- [ ] **Step 3: Fix all callers of `ProjectSession.init` that pass `showInspector`**

Search for `showInspector` references in `ProjectSession` init calls and remove the parameter:

```bash
cd Packages/OsaurusCore && grep -rn "showInspector" Sources/ | grep -v "showProjectInspector"
```

Fix any call sites that pass `showInspector:` — they should use the new single-argument init.

- [ ] **Step 4: Fix `restoreNavigationEntry`**

In `ChatWindowState.swift`, replace lines 127-133:

```swift
private func restoreNavigationEntry(_ entry: NavigationEntry) {
    if entry.mode != mode {
        // Set mode directly to avoid resetting project session state
        mode = entry.mode
        sidebarContentMode = .chat
        switch entry.mode {
        case .work:
            WorkToolManager.shared.registerTools()
            if workSession == nil {
                workSession = WorkSession(agentId: agentId, windowState: self)
            }
            refreshWorkTasks()
        case .project:
            WorkToolManager.shared.unregisterTools()
        case .chat:
            WorkToolManager.shared.unregisterTools()
        }
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

- [ ] **Step 5: Compile check**

```bash
cd Packages/OsaurusCore && swift build 2>&1 | grep -E "error:" | grep -v "IkigaJSON"
```

Expected: no errors (or only pre-existing external dependency errors).

- [ ] **Step 6: Commit**

```bash
git add Packages/OsaurusCore/Managers/Chat/ChatWindowState.swift
git commit -m "feat: extend ProjectSession with inline session/task IDs and fix navigation restore"
```

---

## Task 2: Toolbar — `.principal` Centering + Inspector Toggle

**Files:**
- Modify: `Packages/OsaurusCore/Managers/Chat/ChatWindowManager.swift:620-714`

- [ ] **Step 1: Update toolbar identifiers**

In `ChatWindowManager.swift`, replace the static identifiers block (lines 621-626):

```swift
private static let sidebarItem = NSToolbarItem.Identifier("ChatToolbar.sidebar")
private static let actionItem = NSToolbarItem.Identifier("ChatToolbar.action")
private static let pinItem = NSToolbarItem.Identifier("ChatToolbar.pin")
private static let backItem = NSToolbarItem.Identifier("ChatToolbar.back")
private static let forwardItem = NSToolbarItem.Identifier("ChatToolbar.forward")
private static let inspectorItem = NSToolbarItem.Identifier("ChatToolbar.inspector")
```

Note: `modeToggleItem` is removed — replaced by `.principal`.

- [ ] **Step 2: Update `toolbarAllowedItemIdentifiers` and `toolbarDefaultItemIdentifiers`**

Replace lines 637-649:

```swift
func toolbarAllowedItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
    [
        Self.sidebarItem, Self.backItem, Self.forwardItem,
        .principal,
        Self.actionItem, Self.inspectorItem, Self.pinItem,
    ]
}

func toolbarDefaultItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
    [
        Self.sidebarItem, Self.backItem, Self.forwardItem,
        .principal,
        Self.actionItem, Self.inspectorItem, Self.pinItem,
    ]
}
```

- [ ] **Step 3: Update the item factory method**

In the `switch itemIdentifier` block (lines 658-701), replace the `Self.modeToggleItem` case with `.principal` and add `Self.inspectorItem`:

```swift
case .principal:
    return makeHostingItem(
        identifier: .principal,
        rootView:
            ChatToolbarModeToggleView(windowState: windowState, session: session)
    )
```

Add before the `default:` case:

```swift
case Self.inspectorItem:
    return makeHostingItem(
        identifier: itemIdentifier,
        rootView:
            ChatToolbarInspectorView(windowState: windowState)
    )
```

- [ ] **Step 4: Create `ChatToolbarInspectorView`**

Add after the existing `ChatToolbarForwardView` (after line ~810):

```swift
/// Inspector toggle button (visible in Projects mode only).
private struct ChatToolbarInspectorView: View {
    @ObservedObject var windowState: ChatWindowState

    var body: some View {
        HeaderActionButton(
            icon: "sidebar.right",
            help: windowState.showProjectInspector ? "Hide inspector" : "Show inspector",
            action: {
                withAnimation(windowState.theme.springAnimation()) {
                    windowState.showProjectInspector.toggle()
                }
            }
        )
        .opacity(windowState.mode == .project ? 1.0 : 0.0)
        .disabled(windowState.mode != .project)
        .environment(\.theme, windowState.theme)
    }
}
```

- [ ] **Step 5: Compile check**

```bash
cd Packages/OsaurusCore && swift build 2>&1 | grep -E "error:" | grep -v "IkigaJSON"
```

- [ ] **Step 6: Commit**

```bash
git add Packages/OsaurusCore/Managers/Chat/ChatWindowManager.swift
git commit -m "feat: center mode toggle with .principal and add inspector toolbar button"
```

---

## Task 3: `SidebarContainer` Width Parameterization + `SidebarStyle` Constant

**Files:**
- Modify: `Packages/OsaurusCore/Views/Management/SharedSidebarComponents.swift:13-65`

- [ ] **Step 1: Add `inspectorWidth` to `SidebarStyle`**

In `SharedSidebarComponents.swift`, add to `SidebarStyle` (after line 19):

```swift
static let inspectorWidth: CGFloat = 300
```

- [ ] **Step 2: Add `width` parameter to `SidebarContainer`**

Replace the `SidebarContainer` struct (lines 45-104) — add a `width` stored property with default `SidebarStyle.width`, and use it in `body`:

```swift
/// Container with consistent sidebar styling and glass background support.
/// Supports edge-attached mode for seamless integration with parent views.
struct SidebarContainer<Content: View>: View {
    /// The edge this sidebar is attached to (affects corner radius)
    let attachedEdge: Edge?
    /// Top padding for the content (useful for window control clearance)
    let topPadding: CGFloat
    /// Panel width (default: SidebarStyle.width for left sidebar)
    let width: CGFloat

    @ViewBuilder let content: () -> Content
    @Environment(\.theme) private var theme

    init(
        attachedEdge: Edge? = nil,
        topPadding: CGFloat = 0,
        width: CGFloat = SidebarStyle.width,
        @ViewBuilder content: @escaping () -> Content
    ) {
        self.attachedEdge = attachedEdge
        self.topPadding = topPadding
        self.width = width
        self.content = content
    }

    var body: some View {
        VStack(spacing: 0) {
            content()
        }
        .padding(.top, topPadding)
        .frame(width: width, alignment: .top)
        .frame(maxHeight: .infinity, alignment: .top)
        .background { SidebarBackground() }
        .clipShape(containerShape)
        .overlay(SidebarBorder(attachedEdge: attachedEdge))
    }

    private var containerShape: UnevenRoundedRectangle {
        let radius = SidebarStyle.cornerRadius
        switch attachedEdge {
        case .leading:
            return UnevenRoundedRectangle(
                topLeadingRadius: radius,
                bottomLeadingRadius: radius,
                bottomTrailingRadius: 0,
                topTrailingRadius: 0,
                style: .continuous
            )
        case .trailing:
            return UnevenRoundedRectangle(
                topLeadingRadius: 0,
                bottomLeadingRadius: 0,
                bottomTrailingRadius: radius,
                topTrailingRadius: radius,
                style: .continuous
            )
        case .top, .bottom, .none:
            return UnevenRoundedRectangle(
                topLeadingRadius: radius,
                bottomLeadingRadius: radius,
                bottomTrailingRadius: radius,
                topTrailingRadius: radius,
                style: .continuous
            )
        }
    }
}
```

- [ ] **Step 3: Compile check**

```bash
cd Packages/OsaurusCore && swift build 2>&1 | grep -E "error:" | grep -v "IkigaJSON"
```

- [ ] **Step 4: Commit**

```bash
git add Packages/OsaurusCore/Views/Management/SharedSidebarComponents.swift
git commit -m "feat: add width parameter to SidebarContainer and inspectorWidth constant"
```

---

## Task 4: Inspector Panel — Adopt `SidebarContainer`

**Files:**
- Modify: `Packages/OsaurusCore/Views/Projects/ProjectInspectorPanel.swift`
- Modify: `Packages/OsaurusCore/Views/Projects/ProjectView.swift:39-46`

- [ ] **Step 1: Wrap `ProjectInspectorPanel` in `SidebarContainer`**

In `ProjectInspectorPanel.swift`, replace the `body` (lines 24-147). Remove the manual background and border — `SidebarContainer` handles both:

```swift
var body: some View {
    SidebarContainer(attachedEdge: .trailing, width: SidebarStyle.inspectorWidth) {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: 0) {
                CollapsibleSection("Instructions", isExpanded: $instructionsExpanded) {
                    Button(action: { isEditingInstructions.toggle() }) {
                        Image(systemName: "pencil")
                            .font(.system(size: 11))
                            .foregroundColor(theme.tertiaryText)
                    }
                    .buttonStyle(.plain)
                } content: {
                    if isEditingInstructions {
                        TextEditor(text: $instructionsText)
                            .font(.system(size: 12))
                            .scrollContentBackground(.hidden)
                            .frame(minHeight: 80)
                            .padding(.horizontal, 12)
                            .onChange(of: instructionsText) { _, newValue in
                                var updated = project
                                updated.instructions = newValue
                                ProjectManager.shared.updateProject(updated)
                            }
                    } else if let instructions = project.instructions {
                        Text(instructions)
                            .font(.system(size: 12))
                            .foregroundColor(theme.primaryText)
                            .padding(.horizontal, 12)
                    } else {
                        VStack(spacing: 6) {
                            Image(systemName: "pencil.slash")
                                .font(.system(size: 16))
                                .foregroundColor(theme.tertiaryText)
                            Text("No instructions set")
                                .font(.caption)
                                .foregroundColor(theme.tertiaryText)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .padding(.horizontal, 12)
                    }
                }

                Divider()
                    .opacity(0.3)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 8)

                CollapsibleSection("Scheduled", isExpanded: $scheduledExpanded) {
                    Button(action: { }) {
                        Image(systemName: "plus")
                            .font(.system(size: 11))
                            .foregroundColor(theme.tertiaryText)
                    }
                    .buttonStyle(.plain)
                } content: {
                    VStack(spacing: 6) {
                        Image(systemName: "calendar.badge.clock")
                            .font(.system(size: 16))
                            .foregroundColor(theme.tertiaryText)
                        Text("No scheduled tasks")
                            .font(.caption)
                            .foregroundColor(theme.tertiaryText)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .padding(.horizontal, 12)
                }

                Divider()
                    .opacity(0.3)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 8)

                CollapsibleSection("Context", isExpanded: $contextExpanded) {
                    Button(action: { }) {
                        Image(systemName: "plus")
                            .font(.system(size: 11))
                            .foregroundColor(theme.tertiaryText)
                    }
                    .buttonStyle(.plain)
                } content: {
                    if let folderPath = project.folderPath {
                        FolderTreeView(rootPath: folderPath, onFileSelected: onFileSelected)
                            .padding(.horizontal, 12)
                    } else {
                        VStack(spacing: 6) {
                            Image(systemName: "folder.badge.questionmark")
                                .font(.system(size: 16))
                                .foregroundColor(theme.tertiaryText)
                            Text("No folder linked")
                                .font(.caption)
                                .foregroundColor(theme.tertiaryText)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .padding(.horizontal, 12)
                    }
                }

                Divider()
                    .opacity(0.3)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 8)

                CollapsibleSection("Memory", isExpanded: $memoryExpanded) {
                    MemorySummaryView(projectId: project.id)
                        .padding(.horizontal, 12)
                }
            }
            .padding(.vertical, 12)
        }
    }
    .onAppear {
        instructionsText = project.instructions ?? ""
    }
}
```

- [ ] **Step 2: Remove duplicate border from `ProjectView`**

In `ProjectView.swift`, remove the overlay on the inspector container (lines 41-44). Replace the inspector rendering:

```swift
// Right inspector overlay
if windowState.showProjectInspector,
   let projectId = session.activeProjectId,
   let project = ProjectManager.shared.projects.first(where: { $0.id == projectId }) {
    ProjectInspectorPanel(project: project, onFileSelected: openFilePreview)
        .transition(.move(edge: .trailing))
}
```

Note: `.frame(width: 300)` is removed — `SidebarContainer` sets the width. The border overlay is removed — `SidebarContainer` handles its own border.

- [ ] **Step 3: Compile check**

```bash
cd Packages/OsaurusCore && swift build 2>&1 | grep -E "error:" | grep -v "IkigaJSON"
```

- [ ] **Step 4: Commit**

```bash
git add Packages/OsaurusCore/Views/Projects/ProjectInspectorPanel.swift Packages/OsaurusCore/Views/Projects/ProjectView.swift
git commit -m "feat: adopt SidebarContainer on inspector panel, remove manual bg/border"
```

---

## Task 5: FolderTreeView — Horizontal Scroll Fix + `SidebarRowBackground`

**Files:**
- Modify: `Packages/OsaurusCore/Views/Projects/FolderTreeView.swift:37-119`

- [ ] **Step 1: Update `FileRowView` to use `SidebarRowBackground` and fix truncation**

In `FolderTreeView.swift`, replace the `FileRowView` body (lines 46-118):

```swift
var body: some View {
    VStack(alignment: .leading, spacing: 2) {
        HStack(spacing: 4) {
            if item.isDirectory {
                Image(systemName: expandedDirs.contains(item.path) ? "chevron.down" : "chevron.right")
                    .font(.system(size: 8))
                    .foregroundColor(theme.tertiaryText)
                    .frame(width: 12)
            } else {
                Spacer().frame(width: 12)
            }

            Image(systemName: item.isDirectory ? "folder" : (item.isMd ? "doc.text" : "doc"))
                .font(.system(size: 11))
                .foregroundColor(item.isDirectory ? theme.accentColor.opacity(0.7) : theme.tertiaryText)

            Text(item.name)
                .font(.system(size: 11))
                .foregroundColor(theme.primaryText)
                .lineLimit(1)
                .truncationMode(.middle)
                .frame(maxWidth: .infinity, alignment: .leading)
                .help(item.name)

            if item.isMd {
                Text("context")
                    .font(.system(size: 9))
                    .foregroundColor(theme.accentColor)
                    .padding(.horizontal, 4)
                    .padding(.vertical, 1)
                    .background(
                        Capsule().fill(theme.accentColor.opacity(0.12))
                    )
                    .layoutPriority(1)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.leading, CGFloat(depth) * 16)
        .padding(.vertical, 3)
        .padding(.horizontal, 4)
        .background(
            SidebarRowBackground(isSelected: false, isHovered: isHovered && !item.isDirectory)
        )
        .clipShape(RoundedRectangle(cornerRadius: SidebarStyle.rowCornerRadius, style: .continuous))
        .contentShape(Rectangle())
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.1)) {
                isHovered = hovering
            }
        }
        .onTapGesture {
            if item.isDirectory {
                if expandedDirs.contains(item.path) {
                    expandedDirs.remove(item.path)
                } else {
                    expandedDirs.insert(item.path)
                }
            } else {
                onFileSelected?(item.path)
            }
        }

        if item.isDirectory && expandedDirs.contains(item.path) {
            VStack(alignment: .leading, spacing: 2) {
                ForEach(listDirectory(at: item.path), id: \.path) { child in
                    FileRowView(
                        item: child,
                        depth: depth + 1,
                        expandedDirs: $expandedDirs,
                        onFileSelected: onFileSelected
                    )
                }
            }
            .animation(.easeInOut(duration: 0.2), value: expandedDirs)
        }
    }
}
```

- [ ] **Step 2: Compile check**

```bash
cd Packages/OsaurusCore && swift build 2>&1 | grep -E "error:" | grep -v "IkigaJSON"
```

- [ ] **Step 3: Commit**

```bash
git add Packages/OsaurusCore/Views/Projects/FolderTreeView.swift
git commit -m "fix: prevent inspector horizontal scroll, adopt SidebarRowBackground in file tree"
```

---

## Task 6: CollapsibleSection Header Typography

**Files:**
- Modify: `Packages/OsaurusCore/Views/Common/CollapsibleSection.swift:41-42`

- [ ] **Step 1: Update header font**

In `CollapsibleSection.swift`, replace line 42:

```swift
                    Text(title)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(theme.primaryText)
```

This changes from `.headline` (which is 13pt semibold on macOS but could vary) to an explicit `.system(size: 13, weight: .semibold)` matching the `ChatSessionSidebar` "History" header.

- [ ] **Step 2: Compile check**

```bash
cd Packages/OsaurusCore && swift build 2>&1 | grep -E "error:" | grep -v "IkigaJSON"
```

- [ ] **Step 3: Commit**

```bash
git add Packages/OsaurusCore/Views/Common/CollapsibleSection.swift
git commit -m "fix: standardize CollapsibleSection header to explicit 13pt semibold"
```

---

## Task 7: ProjectView — Inline Chat/Work + `ThemedBackgroundLayer`

**Files:**
- Modify: `Packages/OsaurusCore/Views/Projects/ProjectView.swift`

- [ ] **Step 1: Rewrite `ProjectView` body with 3-state routing and themed background**

Replace the entire `ProjectView` body:

```swift
struct ProjectView: View {
    @ObservedObject var windowState: ChatWindowState
    let session: ProjectSession

    @Environment(\.theme) private var theme
    @State private var previewArtifact: SharedArtifact?

    var body: some View {
        ZStack(alignment: .trailing) {
            // Themed background (matches Chat and Work modes)
            ThemedBackgroundLayer(
                cachedBackgroundImage: windowState.cachedBackgroundImage,
                showSidebar: windowState.showSidebar
            )

            // Center content
            Group {
                if let projectId = session.activeProjectId {
                    if let sessionId = session.inlineSessionId {
                        inlineChatContent(projectId: projectId, sessionId: sessionId)
                    } else if let taskId = session.inlineWorkTaskId {
                        inlineWorkContent(projectId: projectId, taskId: taskId)
                    } else if let project = projectFor(projectId) {
                        ProjectHomeView(
                            project: project,
                            windowState: windowState,
                            onFileSelected: openFilePreview
                        )
                    }
                } else {
                    ProjectListView(windowState: windowState)
                }
            }
            .transition(.opacity)

            // Right inspector overlay
            if windowState.showProjectInspector,
               let projectId = session.activeProjectId,
               let project = projectFor(projectId) {
                ProjectInspectorPanel(project: project, onFileSelected: openFilePreview)
                    .transition(.move(edge: .trailing))
            }
        }
        .clipShape(contentClipShape)
        .animation(.spring(response: 0.35, dampingFraction: 0.88), value: windowState.showProjectInspector)
        .onChange(of: session.inlineWorkTaskId) { old, new in
            if new != nil { WorkToolManager.shared.registerTools() }
            if old != nil && new == nil { WorkToolManager.shared.unregisterTools() }
        }
        .sheet(item: $previewArtifact) { artifact in
            ArtifactViewerSheet(
                artifact: artifact,
                onDismiss: { previewArtifact = nil }
            )
            .environment(\.theme, windowState.theme)
        }
    }

    // MARK: - Helpers

    private func projectFor(_ id: UUID) -> Project? {
        ProjectManager.shared.projects.first { $0.id == id }
    }

    private func openFilePreview(_ path: String) {
        guard let artifact = SharedArtifact.fromFilePath(path) else { return }
        previewArtifact = artifact
    }

    private var contentClipShape: UnevenRoundedRectangle {
        let radius: CGFloat = 24
        return UnevenRoundedRectangle(
            topLeadingRadius: windowState.showSidebar ? 0 : radius,
            bottomLeadingRadius: windowState.showSidebar ? 0 : radius,
            bottomTrailingRadius: radius,
            topTrailingRadius: radius,
            style: .continuous
        )
    }

    // MARK: - Inline Views

    @ViewBuilder
    private func inlineChatContent(projectId: UUID, sessionId: UUID) -> some View {
        // TODO: Load ChatSessionData for sessionId, render chat content inline
        // This requires accessing the ChatSession for the given sessionId
        // and rendering the same message list / input card used in chatModeContent
        Text("Inline chat: \(sessionId.uuidString)")
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    @ViewBuilder
    private func inlineWorkContent(projectId: UUID, taskId: UUID) -> some View {
        // TODO: Load WorkTask for taskId, render work view inline
        // This requires accessing the WorkSession and rendering the same
        // reasoning loop / tool call UI used in WorkView
        Text("Inline work: \(taskId.uuidString)")
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
```

**Note:** The `inlineChatContent` and `inlineWorkContent` methods are stubs. The actual Chat and Work views have deep integration with `ChatSession`, `WorkSession`, and their engines. Wiring these inline requires understanding how `ChatView.chatModeContent` and `WorkView` construct their views from `windowState.session` and `windowState.workSession`. This is the most complex integration point and will need to be refined during implementation by studying how the views get their session data.

- [ ] **Step 2: Compile check**

```bash
cd Packages/OsaurusCore && swift build 2>&1 | grep -E "error:" | grep -v "IkigaJSON"
```

- [ ] **Step 3: Commit**

```bash
git add Packages/OsaurusCore/Views/Projects/ProjectView.swift
git commit -m "feat: add ThemedBackgroundLayer, clip shape, and inline chat/work routing to ProjectView"
```

---

## Task 8: ProjectHomeView — Mode Picker + Remove Inspector Toggle + Width Fix

**Files:**
- Modify: `Packages/OsaurusCore/Views/Projects/ProjectHomeView.swift`

- [ ] **Step 1: Add mode picker enum**

Add at the top of the file, after imports:

```swift
/// Determines whether project input creates a chat or work task.
private enum ProjectInputMode: String, CaseIterable {
    case chat
    case work
}
```

- [ ] **Step 2: Add state property for mode picker**

Add to `ProjectHomeView`'s properties:

```swift
@State private var projectInputMode: ProjectInputMode = .chat
```

- [ ] **Step 3: Remove `isInspectorButtonHovered` state and the manual inspector toggle button from `headerSection`**

Replace `headerSection` — remove the inspector toggle button (the toolbar handles this now):

```swift
private var headerSection: some View {
    VStack(alignment: .leading, spacing: 8) {
        Text(project.name)
            .font(.title)
            .foregroundColor(theme.primaryText)

        Text("What would you like to work on in this project?")
            .font(.subheadline)
            .foregroundColor(theme.secondaryText)

        if let folderPath = project.folderPath {
            Button(action: {
                NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: folderPath)
            }) {
                HStack(spacing: 4) {
                    Image(systemName: "folder")
                        .font(.system(size: 11))
                    Text(folderPath)
                        .font(.system(size: 11))
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                .foregroundColor(isFolderHovered ? theme.secondaryText : theme.tertiaryText)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(isFolderHovered ? theme.secondaryBackground.opacity(0.5) : theme.secondaryBackground.opacity(0.3))
                )
            }
            .buttonStyle(.plain)
            .onHover { hovering in
                withAnimation(.easeInOut(duration: 0.15)) {
                    isFolderHovered = hovering
                }
            }
        }
    }
}
```

Also remove the `@State private var isInspectorButtonHovered` property declaration.

- [ ] **Step 4: Add mode picker above the FloatingInputCard**

In the `body`, wrap the `FloatingInputCard` with a mode picker. Replace the FloatingInputCard section in the `ZStack`:

```swift
VStack(spacing: 8) {
    // Mode picker
    HStack(spacing: 0) {
        modeSegment(.chat, icon: "bubble.left", label: "Chat")
        modeSegment(.work, icon: "bolt.circle", label: "Work")
    }
    .padding(2)
    .background(
        RoundedRectangle(cornerRadius: 20, style: .continuous)
            .fill(theme.secondaryBackground.opacity(0.3))
    )

    FloatingInputCard(
        // ... all existing parameters unchanged ...
        // Update onSend to use projectInputMode:
        onSend: { manualText in
            let message = manualText ?? inputSession.input
            let trimmed = message.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { return }

            switch projectInputMode {
            case .chat:
                windowState.startNewChat()
                windowState.session.input = trimmed
                // Set inline session ID instead of switching modes
                windowState.projectSession?.inlineSessionId = windowState.session.sessionData.id
                windowState.pushNavigation(NavigationEntry(
                    mode: .project, projectId: project.id,
                    sessionId: windowState.session.sessionData.id
                ))
                windowState.session.sendCurrent()
            case .work:
                // Create work task scoped to project
                windowState.projectSession?.inlineWorkTaskId = UUID() // placeholder — actual task creation via WorkSession
                windowState.pushNavigation(NavigationEntry(
                    mode: .project, projectId: project.id,
                    workTaskId: windowState.projectSession?.inlineWorkTaskId
                ))
            }
            inputSession.input = ""
        },
        // ... rest of parameters ...
    )
    .frame(maxWidth: 1100)
    .frame(maxWidth: .infinity)
}
.padding(.bottom, 12)
```

- [ ] **Step 5: Add `modeSegment` helper**

Add to `ProjectHomeView`:

```swift
@Namespace private var modePickerAnimation

@ViewBuilder
private func modeSegment(_ mode: ProjectInputMode, icon: String, label: String) -> some View {
    HStack(spacing: 5) {
        Image(systemName: icon)
            .font(.system(size: 10, weight: .semibold))
        Text(label)
            .font(.system(size: 11, weight: .semibold))
    }
    .fixedSize()
    .foregroundColor(projectInputMode == mode ? theme.primaryText : theme.tertiaryText)
    .padding(.horizontal, 14)
    .padding(.vertical, 5)
    .background {
        if projectInputMode == mode {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(theme.secondaryBackground.opacity(0.8))
                .shadow(color: theme.shadowColor.opacity(0.08), radius: 1.5, x: 0, y: 0.5)
                .matchedGeometryEffect(id: "modePickerIndicator", in: modePickerAnimation)
        }
    }
    .contentShape(Rectangle())
    .animation(theme.springAnimation(), value: projectInputMode == mode)
    .onTapGesture { projectInputMode = mode }
}
```

- [ ] **Step 6: Update `.padding(.trailing, ...)` for inspector**

Change line 81 from `maxWidth: 800` to reflect the new width and keep the inspector offset:

```swift
.padding(.trailing, windowState.showProjectInspector ? SidebarStyle.inspectorWidth : 0)
```

- [ ] **Step 7: Compile check**

```bash
cd Packages/OsaurusCore && swift build 2>&1 | grep -E "error:" | grep -v "IkigaJSON"
```

- [ ] **Step 8: Commit**

```bash
git add Packages/OsaurusCore/Views/Projects/ProjectHomeView.swift
git commit -m "feat: add chat/work mode picker, remove manual inspector toggle, fix input width"
```

---

## Task 9: AppSidebar — Full Rewrite

**Files:**
- Modify: `Packages/OsaurusCore/Views/Sidebar/AppSidebar.swift`

This is the largest single task. The sidebar gets a complete rewrite with stacked project list + draggable divider + unified recents using real `SessionRow` and `TaskRow`.

- [ ] **Step 1: Write the new `AppSidebar`**

Replace the entire contents of `AppSidebar.swift`:

```swift
//
//  AppSidebar.swift
//  osaurus
//
//  Unified sidebar for all three modes (Chat, Work, Projects).
//  Stacked layout: project list + draggable divider + unified recents.
//

import SwiftUI

/// Unified sidebar for all three modes (Chat, Work, Projects).
struct AppSidebar: View {
    @ObservedObject var windowState: ChatWindowState
    @ObservedObject var session: ChatSession

    @AppStorage("isRecentsExpanded") private var isRecentsExpanded = true
    @AppStorage("isProjectsExpanded") private var isProjectsExpanded = true
    @AppStorage("sidebarProjectSectionHeight") private var projectSectionHeight: Double = 140

    @Environment(\.theme) private var theme
    @State private var searchQuery: String = ""
    @FocusState private var searchFocused: Bool
    @State private var isNewChatHovered = false
    @State private var isDraggingDivider = false

    private let minProjectHeight: CGFloat = 56
    private let maxProjectFraction: CGFloat = 0.5

    var body: some View {
        GeometryReader { geometry in
            let maxProjectHeight = geometry.size.height * maxProjectFraction

            VStack(spacing: 0) {
                // New Chat button
                newChatButton
                    .padding(.horizontal, 12)
                    .padding(.top, 8)
                    .padding(.bottom, 4)

                // Search field
                SidebarSearchField(
                    text: $searchQuery,
                    placeholder: "Search conversations...",
                    isFocused: $searchFocused
                )
                .padding(.horizontal, 12)
                .padding(.bottom, 8)

                Divider().opacity(0.3).padding(.horizontal, 12)

                // Projects section
                projectsSection(maxHeight: maxProjectHeight)

                // Draggable divider
                draggableDivider(maxHeight: maxProjectHeight)

                // Recents section
                recentsSection

                Spacer(minLength: 0)
            }
        }
    }

    // MARK: - New Chat Button

    private var newChatButton: some View {
        Button(action: {
            if ProjectManager.shared.activeProjectId != nil {
                // Create project-scoped chat
                windowState.startNewChat()
                // TODO: Set projectId on the new session and open inline
                windowState.projectSession?.inlineSessionId = windowState.session.sessionData.id
            } else {
                windowState.startNewChat()
            }
        }) {
            HStack {
                Image(systemName: "plus.bubble")
                    .font(.system(size: 13, weight: .medium))
                Text("New Chat")
                    .font(.system(size: 13, weight: .medium))
                Spacer()
            }
            .foregroundColor(theme.primaryText)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(
                SidebarRowBackground(isSelected: false, isHovered: isNewChatHovered)
            )
            .clipShape(RoundedRectangle(cornerRadius: SidebarStyle.rowCornerRadius, style: .continuous))
        }
        .buttonStyle(.plain)
        .onHover { isNewChatHovered = $0 }
    }

    // MARK: - Projects Section

    @ViewBuilder
    private func projectsSection(maxHeight: CGFloat) -> some View {
        CollapsibleSection("Projects", isExpanded: $isProjectsExpanded) {
            Text("\(ProjectManager.shared.activeProjects.count)")
                .font(.system(size: 10, weight: .medium))
                .foregroundColor(theme.tertiaryText)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(
                    Capsule().fill(theme.secondaryBackground.opacity(0.5))
                )
        } content: {
            let projects = ProjectManager.shared.activeProjects
            if projects.isEmpty {
                emptyProjectsRow
            } else {
                ScrollView(.vertical, showsIndicators: false) {
                    VStack(spacing: 2) {
                        ForEach(projects) { project in
                            ProjectSidebarRow(
                                project: project,
                                isActive: project.id == ProjectManager.shared.activeProjectId,
                                windowState: windowState
                            )
                        }
                    }
                    .padding(.horizontal, 8)
                }
                .frame(maxHeight: min(CGFloat(projectSectionHeight), maxHeight))
            }

            // All Projects row
            if !projects.isEmpty {
                allProjectsRow
                    .padding(.horizontal, 8)
                    .padding(.top, 4)
            }
        }
    }

    private var emptyProjectsRow: some View {
        Button(action: {
            windowState.sidebarContentMode = .projects
        }) {
            HStack(spacing: 6) {
                Image(systemName: "plus")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(theme.tertiaryText)
                Text("Create a project to get started")
                    .font(.system(size: 11))
                    .foregroundColor(theme.secondaryText)
                Spacer()
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 8)
    }

    private var allProjectsRow: some View {
        Button(action: {
            windowState.sidebarContentMode = .projects
        }) {
            HStack(spacing: 6) {
                Image(systemName: "square.grid.2x2")
                    .font(.system(size: 11))
                    .foregroundColor(theme.secondaryText)
                Text("All Projects")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(theme.secondaryText)
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundColor(theme.tertiaryText)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(
                SidebarRowBackground(isSelected: false, isHovered: false)
            )
            .clipShape(RoundedRectangle(cornerRadius: SidebarStyle.rowCornerRadius, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    // MARK: - Draggable Divider

    @ViewBuilder
    private func draggableDivider(maxHeight: CGFloat) -> some View {
        VStack(spacing: 0) {
            Divider().opacity(0.3).padding(.horizontal, 12)
        }
        .frame(height: 8)
        .contentShape(Rectangle())
        .gesture(
            DragGesture(minimumDistance: 1)
                .onChanged { value in
                    isDraggingDivider = true
                    let newHeight = projectSectionHeight + Double(value.translation.height)
                    projectSectionHeight = max(Double(minProjectHeight), min(newHeight, Double(maxHeight)))
                }
                .onEnded { _ in
                    isDraggingDivider = false
                }
        )
        .onHover { hovering in
            if hovering {
                NSCursor.resizeUpDown.push()
            } else {
                NSCursor.pop()
            }
        }
    }

    // MARK: - Recents Section

    private var recentsSection: some View {
        CollapsibleSection("Recents", isExpanded: $isRecentsExpanded) {
            ScrollView(.vertical, showsIndicators: false) {
                LazyVStack(spacing: 2) {
                    ForEach(windowState.filteredSessions) { sessionData in
                        // TODO: Replace with real SessionRow when wiring is complete.
                        // Real SessionRow requires callbacks (onSelect, onStartRename,
                        // onConfirmRename, onCancelRename, onDelete, onOpenInNewWindow)
                        // and agent lookup. For now, use a simplified row that handles
                        // inline session activation.
                        RecentRow(sessionData: sessionData, windowState: windowState)
                    }
                    // TODO: Interleave WorkTask rows (TaskRow) here.
                    // Requires fetching work tasks filtered by active project
                    // and sorting both lists by updatedAt.
                }
                .padding(.horizontal, 8)
            }
        }
    }
}

// MARK: - Project Sidebar Row

private struct ProjectSidebarRow: View {
    let project: Project
    let isActive: Bool
    @ObservedObject var windowState: ChatWindowState

    @Environment(\.theme) private var theme
    @State private var isHovered = false

    var body: some View {
        Button(action: {
            ProjectManager.shared.setActiveProject(project.id)
            windowState.switchMode(to: .project)
            windowState.projectSession = ProjectSession(activeProjectId: project.id)
            windowState.pushNavigation(NavigationEntry(mode: .project, projectId: project.id))
        }) {
            HStack(spacing: 8) {
                Image(systemName: project.icon)
                    .font(.system(size: 11))
                    .foregroundColor(isActive ? theme.accentColor : theme.secondaryText)

                Text(project.name)
                    .font(.system(size: 12))
                    .foregroundColor(theme.primaryText)
                    .lineLimit(1)
                    .truncationMode(.tail)

                Spacer()

                if isActive {
                    Circle()
                        .fill(theme.accentColor)
                        .frame(width: 6, height: 6)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(
                SidebarRowBackground(isSelected: isActive, isHovered: isHovered)
            )
            .clipShape(RoundedRectangle(cornerRadius: SidebarStyle.rowCornerRadius, style: .continuous))
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .contextMenu {
            if isActive {
                Button("Deselect Project") {
                    ProjectManager.shared.setActiveProject(nil)
                    windowState.projectSession = nil
                }
            }
        }
    }
}

// MARK: - Recent Row (simplified, to be replaced with real SessionRow)

private struct RecentRow: View {
    let sessionData: ChatSessionData
    @ObservedObject var windowState: ChatWindowState

    @Environment(\.theme) private var theme
    @State private var isHovered = false

    var body: some View {
        Button(action: {
            if windowState.mode == .project, windowState.projectSession?.activeProjectId != nil {
                // Open inline within project
                windowState.projectSession?.inlineSessionId = sessionData.id
                windowState.pushNavigation(NavigationEntry(
                    mode: .project,
                    projectId: windowState.projectSession?.activeProjectId,
                    sessionId: sessionData.id
                ))
            } else {
                // Normal session selection
                windowState.session.load(from: sessionData)
                windowState.switchMode(to: .chat)
            }
        }) {
            HStack(spacing: 8) {
                Circle()
                    .fill(theme.accentColor.opacity(0.5))
                    .frame(width: 8, height: 8)

                Text(sessionData.title)
                    .font(.system(size: 12))
                    .foregroundColor(theme.primaryText)
                    .lineLimit(1)
                    .truncationMode(.tail)

                Spacer()

                Text(formatRelativeDate(sessionData.updatedAt))
                    .font(.system(size: 10))
                    .foregroundColor(theme.tertiaryText)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(
                SidebarRowBackground(
                    isSelected: sessionData.id == windowState.session.sessionData.id,
                    isHovered: isHovered
                )
            )
            .clipShape(RoundedRectangle(cornerRadius: SidebarStyle.rowCornerRadius, style: .continuous))
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
    }
}
```

- [ ] **Step 2: Compile check**

```bash
cd Packages/OsaurusCore && swift build 2>&1 | grep -E "error:" | grep -v "IkigaJSON"
```

- [ ] **Step 3: Commit**

```bash
git add Packages/OsaurusCore/Views/Sidebar/AppSidebar.swift
git commit -m "feat: rewrite AppSidebar with stacked projects, draggable divider, unified recents"
```

---

## Task 10: Code Cleanup — Delete Dead Code

**Files:**
- Delete: `Packages/OsaurusCore/Views/Sidebar/SidebarNavRow.swift`
- Verify: no remaining references to deleted types

- [ ] **Step 1: Delete `SidebarNavRow.swift`**

```bash
rm Packages/OsaurusCore/Views/Sidebar/SidebarNavRow.swift
```

- [ ] **Step 2: Verify no remaining references**

```bash
grep -rn "SidebarNavRow\|ActiveProjectChipView\|RecentSessionRow\|modeToggleItem" Packages/OsaurusCore/Sources/ Packages/OsaurusCore/Views/ Packages/OsaurusCore/Managers/ 2>/dev/null
```

Expected: zero results.

- [ ] **Step 3: Compile check**

```bash
cd Packages/OsaurusCore && swift build 2>&1 | grep -E "error:" | grep -v "IkigaJSON"
```

- [ ] **Step 4: Commit**

```bash
git add -A
git commit -m "chore: delete SidebarNavRow and verify no dead code references"
```

---

## Task 11: Final Verification

- [ ] **Step 1: Full compile check**

```bash
cd Packages/OsaurusCore && swift build 2>&1 | grep -E "error:" | grep -v "IkigaJSON"
```

- [ ] **Step 2: Run existing tests**

```bash
swift test --package-path Packages/OsaurusCore 2>&1 | tail -20
```

- [ ] **Step 3: Verify no dead code grep**

```bash
grep -rn "ActiveProjectChipView\|RecentSessionRow\|SidebarNavRow\|modeToggleItem\|showInspector:" Packages/OsaurusCore/ 2>/dev/null | grep -v "showProjectInspector"
```

Expected: zero results.

- [ ] **Step 4: Commit any remaining fixes**

```bash
git add -A
git commit -m "chore: final verification pass — all clean"
```

---

## Implementation Notes

### Inline Chat/Work (Task 7) — Stub Warning

The `inlineChatContent` and `inlineWorkContent` methods in Task 7 are **stubs**. Wiring the actual Chat and Work views inline requires deep integration:

- **Inline Chat:** Needs to load a `ChatSessionData` by ID, configure a `ChatSession` for it, and render the same message list + streaming UI from `ChatView.chatModeContent`. The key challenge is that `chatModeContent` reads `windowState.session` directly — inline chat may need a separate `ChatSession` instance or the ability to swap `windowState.session` when entering/exiting inline mode.

- **Inline Work:** Needs to load a `WorkTask` by ID, create or restore a `WorkSession` for it, and render the `WorkView` content. The key challenge is that `WorkView` reads `windowState.workSession` — inline work may need to set `windowState.workSession` temporarily while staying in `.project` mode.

These stubs compile and show placeholder text. Full wiring should be done as a follow-up task once the surrounding infrastructure (sidebar, toolbar, navigation) is stable and testable.

### Sidebar Recents (Task 9) — Simplified Row Warning

The `RecentRow` in the sidebar rewrite is a **simplified stand-in** for the real `SessionRow` and `TaskRow`. It uses `SidebarRowBackground` correctly but lacks:
- Agent color dot computation (hashing agent UUID to hue)
- Inline rename mode
- Context menus (rename, delete, open in new window)
- `TaskRow` morphing status icon with 60fps spinner

Wiring the real `SessionRow` and `TaskRow` requires their callbacks (rename, delete, etc.) to work in the project context. This should be done as a follow-up once the sidebar structure is stable.
