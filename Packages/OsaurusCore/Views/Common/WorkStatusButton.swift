//
//  WorkStatusButton.swift
//  osaurus
//
//  Reusable status button showing work execution progress, issue counts, and artifacts.
//

import SwiftUI

struct WorkStatusButton: View {
    let isExecuting: Bool
    let issues: [Issue]
    let artifactCount: Int
    let fileOpCount: Int
    let onTap: () -> Void

    @Environment(\.theme) private var theme: ThemeProtocol
    @State private var isHovered = false

    private var completedCount: Int {
        issues.filter { $0.status == .closed }.count
    }

    private var allDone: Bool {
        !issues.isEmpty && completedCount == issues.count
    }

    private var statusText: String {
        if isExecuting { return "Running" }
        if allDone { return "Done" }
        if issues.count > 1 { return "\(completedCount)/\(issues.count) tasks" }
        return "Progress"
    }

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 6) {
                statusIndicator

                Text(statusText)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(isHovered ? theme.primaryText : theme.secondaryText)

                detailChips

                Image(systemName: "chevron.left")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundColor(theme.tertiaryText)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background {
                Capsule(style: .continuous)
                    .fill(theme.secondaryBackground.opacity(isHovered ? 0.9 : 0.6))
            }
            .overlay {
                Capsule(style: .continuous)
                    .strokeBorder(theme.primaryBorder.opacity(isHovered ? 0.2 : 0.1), lineWidth: 0.5)
            }
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            withAnimation(.easeOut(duration: 0.15)) {
                isHovered = hovering
            }
        }
    }

    @ViewBuilder
    private var statusIndicator: some View {
        if isExecuting {
            Circle()
                .fill(theme.accentColor)
                .frame(width: 7, height: 7)
                .modifier(WorkPulseModifier())
        } else if allDone {
            Image(systemName: "checkmark")
                .font(.system(size: 9, weight: .bold))
                .foregroundColor(theme.successColor)
        } else {
            Circle()
                .fill(theme.tertiaryText.opacity(0.4))
                .frame(width: 6, height: 6)
        }
    }

    @ViewBuilder
    private var detailChips: some View {
        if artifactCount > 0 || fileOpCount > 0 {
            HStack(spacing: 4) {
                if fileOpCount > 0 {
                    chipLabel("pencil", count: fileOpCount)
                }
                if artifactCount > 0 {
                    chipLabel("doc.fill", count: artifactCount)
                }
            }
        }
    }

    private func chipLabel(_ systemName: String, count: Int) -> some View {
        HStack(spacing: 3) {
            Image(systemName: systemName)
                .font(.system(size: 9, weight: .medium))
            Text("\(count)", bundle: .module)
                .font(.system(size: 10, weight: .medium, design: .rounded))
        }
        .foregroundColor(theme.tertiaryText)
    }
}
