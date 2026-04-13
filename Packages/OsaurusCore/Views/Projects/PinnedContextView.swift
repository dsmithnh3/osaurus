//
//  PinnedContextView.swift
//  osaurus
//
//  Displays pinned context files and folders in the project inspector.
//

import SwiftUI

/// Displays pinned context entries above the folder tree in the inspector.
struct PinnedContextView: View {
    let entries: [ProjectContextEntry]
    let onRemove: (UUID) -> Void
    var onFileSelected: ((String) -> Void)?

    @Environment(\.theme) private var theme
    @State private var hoveredEntry: UUID?
    @State private var expandedDirs: Set<String> = []

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("Pinned")
                .font(.system(size: 10, weight: .semibold))
                .foregroundColor(theme.tertiaryText)
                .textCase(.uppercase)
                .padding(.bottom, 4)

            ForEach(entries) { entry in
                pinnedEntryRow(entry)

                // Expand directory contents
                if entry.isDirectory && expandedDirs.contains(entry.path) {
                    VStack(alignment: .leading, spacing: 2) {
                        ForEach(listDirectory(at: entry.path), id: \.path) { child in
                            FileRowView(
                                item: child,
                                depth: 1,
                                maxDepth: 4,
                                expandedDirs: $expandedDirs,
                                onFileSelected: onFileSelected
                            )
                        }
                    }
                    .animation(.easeInOut(duration: 0.2), value: expandedDirs)
                }
            }
        }
        .padding(.bottom, 8)
    }

    // MARK: - Entry Row

    @ViewBuilder
    private func pinnedEntryRow(_ entry: ProjectContextEntry) -> some View {
        let isHovered = hoveredEntry == entry.id
        let name = URL(fileURLWithPath: entry.path).lastPathComponent

        HStack(spacing: 4) {
            // Accent dot to differentiate from folder tree
            Circle()
                .fill(theme.accentColor.opacity(0.5))
                .frame(width: 4, height: 4)

            if entry.isDirectory {
                Image(
                    systemName: expandedDirs.contains(entry.path)
                        ? "chevron.down" : "chevron.right"
                )
                .font(.system(size: 8))
                .foregroundColor(theme.tertiaryText)
                .frame(width: 12)
            }

            Image(systemName: entry.isDirectory ? "folder.fill" : "doc.fill")
                .font(.system(size: 11))
                .foregroundColor(
                    entry.isDirectory
                        ? theme.accentColor.opacity(0.7)
                        : theme.tertiaryText
                )

            Text(name)
                .font(.system(size: 11))
                .foregroundColor(theme.primaryText)
                .lineLimit(1)
                .truncationMode(.middle)
                .frame(maxWidth: .infinity, alignment: .leading)
                .help(entry.path)

            if isHovered {
                Button(action: { onRemove(entry.id) }) {
                    Image(systemName: "xmark")
                        .font(.system(size: 8, weight: .semibold))
                        .foregroundColor(theme.tertiaryText)
                        .frame(width: 16, height: 16)
                        .background(
                            Circle().fill(theme.secondaryBackground.opacity(0.6))
                        )
                }
                .buttonStyle(.plain)
                .transition(.opacity)
                .help("Remove from pinned context")
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 3)
        .padding(.horizontal, 4)
        .background(
            SidebarRowBackground(isSelected: false, isHovered: isHovered)
        )
        .clipShape(
            RoundedRectangle(cornerRadius: SidebarStyle.rowCornerRadius, style: .continuous)
        )
        .contentShape(Rectangle())
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.1)) {
                hoveredEntry = hovering ? entry.id : nil
            }
        }
        .onTapGesture {
            if entry.isDirectory {
                if expandedDirs.contains(entry.path) {
                    expandedDirs.remove(entry.path)
                } else {
                    expandedDirs.insert(entry.path)
                }
            } else {
                onFileSelected?(entry.path)
            }
        }
    }
}
