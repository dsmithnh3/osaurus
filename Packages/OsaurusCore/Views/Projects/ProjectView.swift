//
//  ProjectView.swift
//  osaurus
//
//  Coordinator for the project 3-panel layout: sidebar (handled by parent) + center + right inspector.
//

import SwiftUI

/// Coordinator for the project 3-panel layout.
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
        Text("Inline chat: \(sessionId.uuidString)")
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    @ViewBuilder
    private func inlineWorkContent(projectId: UUID, taskId: UUID) -> some View {
        // TODO: Load WorkTask for taskId, render work view inline
        Text("Inline work: \(taskId.uuidString)")
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
