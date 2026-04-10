//
//  TaskRow.swift
//  osaurus
//
//  Shared task row component for displaying work tasks in sidebars.
//  Extracted from WorkTaskSidebar for reuse across Work and Projects tabs.
//

import SwiftUI

struct TaskRow: View {
    let task: WorkTask
    let isSelected: Bool
    let onSelect: () -> Void
    let onDelete: () -> Void

    @Environment(\.theme) private var theme: ThemeProtocol
    @State private var isHovered = false

    var body: some View {
        HStack(spacing: 10) {
            // Morphing status icon with accent background
            statusIconView

            // Content
            VStack(alignment: .leading, spacing: 2) {
                Text(task.title)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(theme.primaryText)
                    .lineLimit(1)

                Text(formatRelativeDate(task.updatedAt))
                    .font(.system(size: 10))
                    .foregroundColor(theme.secondaryText.opacity(0.85))
            }

            Spacer()

            // Delete button (on hover)
            if isHovered {
                SidebarRowActionButton(
                    icon: "trash",
                    help: "Delete",
                    action: onDelete
                )
                .transition(.opacity.combined(with: .scale(scale: 0.9)))
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(SidebarRowBackground(isSelected: isSelected, isHovered: isHovered))
        .clipShape(RoundedRectangle(cornerRadius: SidebarStyle.rowCornerRadius, style: .continuous))
        .contentShape(RoundedRectangle(cornerRadius: SidebarStyle.rowCornerRadius, style: .continuous))
        .onTapGesture {
            onSelect()
        }
        .onHover { hovering in
            withAnimation(theme.springAnimation(responseMultiplier: 0.8)) {
                isHovered = hovering
            }
        }
        .contextMenu {
            Button(role: .destructive) {
                onDelete()
            } label: { Text("Delete", bundle: .module) }
        }
        .animation(theme.springAnimation(responseMultiplier: 0.8), value: isHovered)
        .animation(theme.springAnimation(responseMultiplier: 0.8), value: isSelected)
    }

    // MARK: - Status Icon

    private var statusIconView: some View {
        ZStack {
            Circle()
                .fill(statusColor.opacity(theme.isDark ? 0.14 : 0.10))
                .frame(width: 24, height: 24)

            MorphingStatusIcon(state: statusIconState, accentColor: statusColor, size: 12)
        }
    }

    private var statusIconState: StatusIconState {
        switch task.status {
        case .active: return .active
        case .completed: return .completed
        case .cancelled: return .failed
        }
    }

    private var statusColor: Color {
        switch task.status {
        case .active: return theme.accentColor
        case .completed: return theme.successColor
        case .cancelled: return theme.tertiaryText
        }
    }
}
