//
//  FolderTreeView.swift
//  osaurus
//
//  Recursive directory tree browser for the project context section.
//

import SwiftUI

// MARK: - Supporting Types

private struct FileItem {
    let name: String
    let path: String
    let isDirectory: Bool
    var isMd: Bool { !isDirectory && name.hasSuffix(".md") }
}

private func listDirectory(at path: String) -> [FileItem] {
    let fm = FileManager.default
    let url = URL(fileURLWithPath: path)
    guard
        let contents = try? fm.contentsOfDirectory(
            at: url,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        )
    else { return [] }

    return contents.compactMap { fileURL in
        let isDir = (try? fileURL.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory ?? false
        return FileItem(name: fileURL.lastPathComponent, path: fileURL.path, isDirectory: isDir)
    }.sorted { a, b in
        if a.isDirectory != b.isDirectory { return a.isDirectory }
        return a.name.localizedCaseInsensitiveCompare(b.name) == .orderedAscending
    }
}

// MARK: - FileRowView (breaks recursive opaque-type inference)

private struct FileRowView: View {
    let item: FileItem
    let depth: Int
    @Binding var expandedDirs: Set<String>
    var onFileSelected: ((String) -> Void)?

    @Environment(\.theme) private var theme
    @State private var isHovered = false

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
}

// MARK: - SharedArtifact from file path

extension SharedArtifact {
    /// Creates a SharedArtifact from a local file path for preview purposes.
    static func fromFilePath(_ path: String) -> SharedArtifact? {
        let url = URL(fileURLWithPath: path)
        let fm = FileManager.default
        guard fm.fileExists(atPath: path) else { return nil }

        let filename = url.lastPathComponent
        let mime = SharedArtifact.mimeType(from: filename)
        let fileSize = (try? fm.attributesOfItem(atPath: path)[.size] as? Int) ?? 0

        // Read text content for text-based files (cap at 1 MB)
        var textContent: String?
        let isTextType =
            mime.hasPrefix("text/") || mime == "application/json"
            || mime == "application/xml" || mime == "application/x-yaml"
        if isTextType, fileSize < 1_048_576 {
            textContent = try? String(contentsOf: url, encoding: .utf8)
        }

        return SharedArtifact(
            contextId: "file-preview",
            contextType: .work,
            filename: filename,
            mimeType: mime,
            fileSize: fileSize,
            hostPath: path,
            content: textContent
        )
    }
}

// MARK: - FolderTreeView

/// Recursive directory tree browser for the project context section.
struct FolderTreeView: View {
    let rootPath: String
    var onFileSelected: ((String) -> Void)?

    @State private var expandedDirs: Set<String> = []
    @Environment(\.theme) private var theme

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("On your computer")
                .font(.system(size: 10, weight: .semibold))
                .foregroundColor(theme.tertiaryText)
                .textCase(.uppercase)
                .padding(.bottom, 4)

            ForEach(listDirectory(at: rootPath), id: \.path) { item in
                FileRowView(
                    item: item,
                    depth: 0,
                    expandedDirs: $expandedDirs,
                    onFileSelected: onFileSelected
                )
            }
        }
    }
}
