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
            Button(action: { withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) { isExpanded.toggle() } }) {
                HStack {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundColor(theme.tertiaryText)
                        .rotationEffect(.degrees(isExpanded ? 90 : 0))
                        .animation(.spring(response: 0.3, dampingFraction: 0.8), value: isExpanded)

                    Text(title)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(theme.primaryText)

                    Spacer()

                    headerAccessory
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(title)
            .accessibilityHint(isExpanded ? "Collapse section" : "Expand section")
            .accessibilityAddTraits(.isButton)

            if isExpanded {
                Divider().opacity(0.5)

                content
                    .padding(.horizontal, 16)
                    .padding(.bottom, 12)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
    }
}
