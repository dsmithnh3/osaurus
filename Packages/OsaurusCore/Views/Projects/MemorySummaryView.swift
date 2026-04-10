//
//  MemorySummaryView.swift
//  osaurus
//
//  Compact view of project-scoped memory entries for the inspector panel.
//

import SwiftUI

/// Compact view of project-scoped memory entries for the inspector panel.
struct MemorySummaryView: View {
    let projectId: UUID

    @Environment(\.theme) private var theme

    var body: some View {
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
    }
}
