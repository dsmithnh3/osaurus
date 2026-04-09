//
//  CollapsibleSection.swift
//  osaurus
//
//  Reusable collapsible section with chevron toggle, following macOS System Settings pattern.
//

import SwiftUI

/// Reusable collapsible section with chevron toggle, following macOS System Settings pattern.
struct CollapsibleSection<Content: View, HeaderAccessory: View>: View {
    let title: String
    @Binding var isExpanded: Bool
    let headerAccessory: HeaderAccessory
    let content: Content

    @Environment(\.theme) private var theme

    init(
        _ title: String,
        isExpanded: Binding<Bool>,
        @ViewBuilder headerAccessory: () -> HeaderAccessory = { EmptyView() },
        @ViewBuilder content: () -> Content
    ) {
        self.title = title
        self._isExpanded = isExpanded
        self.headerAccessory = headerAccessory()
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button(action: { withAnimation(.easeInOut(duration: 0.2)) { isExpanded.toggle() } }) {
                HStack {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundColor(theme.tertiaryText)
                        .rotationEffect(.degrees(isExpanded ? 90 : 0))
                        .animation(.easeInOut(duration: 0.2), value: isExpanded)

                    Text(title)
                        .font(.headline)
                        .foregroundColor(theme.primaryText)

                    Spacer()

                    headerAccessory
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(title)
            .accessibilityHint(isExpanded ? "Collapse section" : "Expand section")
            .accessibilityAddTraits(.isButton)

            if isExpanded {
                content
                    .padding(.horizontal, 16)
                    .padding(.bottom, 12)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
    }
}
