//
//  ProjectView.swift
//  osaurus
//
//  Coordinator for the project 3-panel layout: left sidebar + center + right inspector.
//

import SwiftUI

/// Coordinator for the project 3-panel layout.
struct ProjectView: View {
    @ObservedObject var windowState: ChatWindowState
    let session: ProjectSession

    @Environment(\.theme) private var theme
    @State private var previewArtifact: SharedArtifact?

    var body: some View {
        GeometryReader { proxy in
            let sidebarWidth: CGFloat = windowState.showSidebar ? SidebarStyle.width : 0

            HStack(alignment: .top, spacing: 0) {
                // Left sidebar
                if windowState.showSidebar {
                    AppSidebar(windowState: windowState, session: windowState.session)
                        .transition(.move(edge: .leading).combined(with: .opacity))
                }

                // Center + right inspector
                ZStack(alignment: .trailing) {
                    // Themed background (matches Chat and Work modes)
                    ThemedBackgroundLayer(
                        cachedBackgroundImage: windowState.cachedBackgroundImage,
                        showSidebar: windowState.showSidebar
                    )

                    // Center content
                    Group {
                        if session.activeProjectId != nil {
                            switch session.subMode {
                            case .chat:
                                ProjectInlineChatView(windowState: windowState)
                            case .work:
                                ProjectInlineWorkView(windowState: windowState)
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
                        ProjectInspectorPanel(project: project, onFileSelected: openFilePreview, onArtifactSelected: { previewArtifact = $0 })
                            .transition(.move(edge: .trailing))
                    }
                }
                .frame(width: proxy.size.width - sidebarWidth)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .animation(.spring(response: 0.35, dampingFraction: 0.88), value: windowState.showProjectInspector)
        .animation(theme.springAnimation(responseMultiplier: 0.9), value: windowState.showSidebar)
        .onChange(of: session.subMode) { old, new in
            if new == .work { WorkToolManager.shared.registerTools() }
            if old == .work && new != .work { WorkToolManager.shared.unregisterTools() }
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
}
