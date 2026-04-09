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
        VStack(alignment: .leading, spacing: 4) {
            Text("Memory entries for this project will appear here")
                .font(.system(size: 11))
                .foregroundColor(theme.tertiaryText)
        }
    }
}
