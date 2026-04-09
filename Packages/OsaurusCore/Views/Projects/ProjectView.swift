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

    var body: some View {
        ZStack(alignment: .trailing) {
            // Center content
            if let projectId = session.activeProjectId,
               let project = ProjectManager.shared.projects.first(where: { $0.id == projectId }) {
                ProjectHomeView(
                    project: project,
                    windowState: windowState
                )
            } else {
                ProjectListView(windowState: windowState)
            }

            // Right inspector overlay
            if windowState.showProjectInspector,
               let projectId = session.activeProjectId,
               let project = ProjectManager.shared.projects.first(where: { $0.id == projectId }) {
                ProjectInspectorPanel(project: project)
                    .frame(width: 300)
                    .transition(.move(edge: .trailing))
            }
        }
        .animation(.spring(response: 0.3, dampingFraction: 0.85), value: windowState.showProjectInspector)
    }
}
