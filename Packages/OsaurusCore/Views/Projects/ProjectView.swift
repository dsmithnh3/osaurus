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
            // Center content
            if let projectId = session.activeProjectId,
               let project = ProjectManager.shared.projects.first(where: { $0.id == projectId }) {
                ProjectHomeView(
                    project: project,
                    windowState: windowState,
                    onFileSelected: openFilePreview
                )
                .transition(.opacity)
                .animation(.easeInOut(duration: 0.2), value: projectId)
            } else {
                ProjectListView(windowState: windowState)
                    .transition(.opacity)
            }

            // Right inspector overlay
            if windowState.showProjectInspector,
               let projectId = session.activeProjectId,
               let project = ProjectManager.shared.projects.first(where: { $0.id == projectId }) {
                ProjectInspectorPanel(project: project, onFileSelected: openFilePreview)
                    .transition(.move(edge: .trailing))
            }
        }
        .animation(.spring(response: 0.35, dampingFraction: 0.88), value: windowState.showProjectInspector)
        .sheet(item: $previewArtifact) { artifact in
            ArtifactViewerSheet(
                artifact: artifact,
                onDismiss: { previewArtifact = nil }
            )
            .environment(\.theme, windowState.theme)
        }
    }

    private func openFilePreview(_ path: String) {
        guard let artifact = SharedArtifact.fromFilePath(path) else { return }
        previewArtifact = artifact
    }
}
