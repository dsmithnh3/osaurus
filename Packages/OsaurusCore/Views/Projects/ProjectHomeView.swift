//
//  ProjectHomeView.swift
//  osaurus
//
//  Center panel of the project view — header, outputs grid, and recents list.
//

import SwiftUI

/// Center panel of the project view.
struct ProjectHomeView: View {
    let project: Project
    @ObservedObject var windowState: ChatWindowState

    @Environment(\.theme) private var theme

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                headerSection
                outputsSection
                recentsSection
            }
            .padding(20)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.trailing, windowState.showProjectInspector ? 300 : 0)
    }

    private var headerSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(project.name)
                    .font(.title)
                    .foregroundColor(theme.primaryText)

                Spacer()

                Button(action: { windowState.showProjectInspector.toggle() }) {
                    Image(systemName: "sidebar.right")
                        .font(.system(size: 14))
                        .foregroundColor(theme.secondaryText)
                }
                .buttonStyle(.plain)
                .help("Toggle inspector")
            }

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
                    .foregroundColor(theme.tertiaryText)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .fill(theme.secondaryBackground.opacity(0.3))
                    )
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var outputsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Outputs")
                .font(.headline)
                .foregroundColor(theme.primaryText)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    Text("No outputs yet")
                        .font(.subheadline)
                        .foregroundColor(theme.tertiaryText)
                        .padding(20)
                }
            }
        }
    }

    private var recentsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Recents")
                .font(.headline)
                .foregroundColor(theme.primaryText)

            Text("No recent conversations")
                .font(.subheadline)
                .foregroundColor(theme.tertiaryText)
        }
    }
}
