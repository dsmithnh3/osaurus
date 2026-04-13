//
//  MemorySummaryView.swift
//  osaurus
//
//  Compact view of project-scoped memory entries for the inspector panel.
//

import Combine
import SwiftUI

/// Compact view of project-scoped memory entries for the inspector panel.
struct MemorySummaryView: View {
    let projectId: UUID

    @Environment(\.theme) private var theme
    @State private var total: Int = 0
    @State private var byType: [MemoryEntryType: Int] = [:]
    @State private var recentEntries: [MemoryEntry] = []

    var body: some View {
        Group {
            if total == 0 {
                VStack(spacing: 8) {
                    Image(systemName: "brain")
                        .font(.system(size: 18))
                        .foregroundColor(theme.tertiaryText)
                    Text("No memories yet")
                        .font(.caption)
                        .foregroundColor(theme.tertiaryText)
                    Text("Memories from project conversations will appear here")
                        .font(.caption2)
                        .foregroundColor(theme.tertiaryText.opacity(0.7))
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Image(systemName: "brain")
                            .font(.system(size: 12))
                            .foregroundColor(theme.accentColor)
                        Text("\(total) memor\(total == 1 ? "y" : "ies")")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(theme.primaryText)
                    }

                    if !byType.isEmpty {
                        FlowLayout(spacing: 4) {
                            ForEach(byType.sorted(by: { $0.value > $1.value }), id: \.key) { type, count in
                                Text("\(type.displayName) \(count)")
                                    .font(.system(size: 9))
                                    .foregroundColor(theme.secondaryText)
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(
                                        Capsule().fill(theme.secondaryBackground.opacity(0.5))
                                    )
                            }
                        }
                    }

                    if !recentEntries.isEmpty {
                        Divider()
                        ForEach(recentEntries.prefix(3), id: \.id) { entry in
                            HStack(alignment: .top, spacing: 6) {
                                Circle()
                                    .fill(theme.accentColor.opacity(0.4))
                                    .frame(width: 4, height: 4)
                                    .padding(.top, 5)
                                Text(entry.content)
                                    .font(.system(size: 10))
                                    .foregroundColor(theme.secondaryText)
                                    .lineLimit(2)
                            }
                        }
                    }
                }
            }
        }
        .task { await loadData() }
        .onReceive(NotificationCenter.default.publisher(for: .memoryEntriesDidChange)) { _ in
            Task { await loadData() }
        }
    }

    private func loadData() async {
        let db = MemoryDatabase.shared
        guard db.isOpen else { return }
        let pid = projectId.uuidString
        do {
            let stats = try db.countEntriesByProject(projectId: pid)
            total = stats.total
            byType = stats.byType
            recentEntries = try db.loadProjectEntries(projectId: pid, limit: 5)
        } catch {
            // Silently fail — empty state is fine
        }
    }
}
