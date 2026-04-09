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
    guard let contents = try? fm.contentsOfDirectory(
        at: url, includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles]
    ) else { return [] }

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

    @Environment(\.theme) private var theme

    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            HStack(spacing: 4) {
                if item.isDirectory {
                    Image(systemName: expandedDirs.contains(item.path) ? "chevron.down" : "chevron.right")
                        .font(.system(size: 8))
                        .foregroundColor(theme.tertiaryText)
                        .frame(width: 12)
                        .onTapGesture {
                            if expandedDirs.contains(item.path) {
                                expandedDirs.remove(item.path)
                            } else {
                                expandedDirs.insert(item.path)
                            }
                        }
                } else {
                    Spacer().frame(width: 12)
                }

                Image(systemName: item.isDirectory ? "folder" : (item.isMd ? "doc.text" : "doc"))
                    .font(.system(size: 11))
                    .foregroundColor(item.isMd ? theme.accentColor : theme.tertiaryText)

                Text(item.name)
                    .font(.system(size: 11))
                    .foregroundColor(theme.primaryText)
                    .lineLimit(1)

                if item.isMd {
                    Text("context")
                        .font(.system(size: 9))
                        .foregroundColor(theme.accentColor.opacity(0.7))
                        .padding(.horizontal, 4)
                        .padding(.vertical, 1)
                        .background(
                            Capsule().fill(theme.accentColor.opacity(0.1))
                        )
                }
            }
            .padding(.leading, CGFloat(depth) * 16)
            .padding(.vertical, 2)

            if item.isDirectory && expandedDirs.contains(item.path) {
                ForEach(listDirectory(at: item.path), id: \.path) { child in
                    FileRowView(item: child, depth: depth + 1, expandedDirs: $expandedDirs)
                }
            }
        }
    }
}

// MARK: - FolderTreeView

/// Recursive directory tree browser for the project context section.
struct FolderTreeView: View {
    let rootPath: String

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
                FileRowView(item: item, depth: 0, expandedDirs: $expandedDirs)
            }
        }
    }
}
