//
//  SidebarNavRow.swift
//  osaurus
//
//  A navigation item row for the unified sidebar (Projects, Scheduled, Customize).
//

import SwiftUI

/// A navigation item row for the unified sidebar (Projects, Scheduled, Customize).
struct SidebarNavRow: View {
    let icon: String
    let label: String
    var badge: Int? = nil
    var isActive: Bool = false
    let action: () -> Void

    @State private var isHovered = false
    @Environment(\.theme) private var theme

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(isActive ? theme.accentColor : theme.secondaryText)
                    .frame(width: 20)

                Text(label)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(isActive ? theme.accentColor : theme.primaryText)

                Spacer()

                if let badge, badge > 0 {
                    Text("\(badge)")
                        .font(.caption2.weight(.semibold))
                        .foregroundColor(isActive ? theme.accentColor : theme.tertiaryText)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(
                            Capsule()
                                .fill(
                                    isActive
                                        ? theme.accentColor.opacity(0.12)
                                        : theme.secondaryBackground.opacity(0.5)
                                )
                        )
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(
                        isActive
                            ? theme.accentColor.opacity(0.08)
                            : (isHovered ? theme.secondaryBackground.opacity(0.3) : Color.clear)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .strokeBorder(
                                isActive ? theme.accentColor.opacity(0.15) : Color.clear,
                                lineWidth: 1
                            )
                    )
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .accessibilityAddTraits(isActive ? .isSelected : [])
    }
}
