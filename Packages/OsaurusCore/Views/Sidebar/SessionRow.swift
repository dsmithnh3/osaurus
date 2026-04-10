//
//  SessionRow.swift
//  osaurus
//
//  Shared row view for displaying a chat session in any sidebar.
//

import SwiftUI

struct SessionRow: View {
    let session: ChatSessionData
    let agent: Agent?
    let isSelected: Bool
    let isEditing: Bool
    @Binding var editingTitle: String
    let onSelect: () -> Void
    let onStartRename: () -> Void
    let onConfirmRename: () -> Void
    let onCancelRename: () -> Void
    let onDelete: () -> Void
    /// Optional callback for opening in a new window
    var onOpenInNewWindow: (() -> Void)? = nil

    @Environment(\.theme) private var theme
    @State private var isHovered = false
    @FocusState private var isTextFieldFocused: Bool

    /// Whether this is the default agent
    private var isDefaultAgent: Bool {
        guard let agent = agent else { return true }
        return agent.isBuiltIn
    }

    /// Get a consistent color for the agent based on its ID
    private var agentColor: Color {
        guard let agent = agent, !agent.isBuiltIn else { return theme.secondaryText }
        // Generate a consistent hue from the agent ID
        let hash = agent.id.hashValue
        let hue = Double(abs(hash) % 360) / 360.0
        return Color(hue: hue, saturation: 0.6, brightness: 0.8)
    }

    var body: some View {
        if isEditing {
            editingView
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
                .background(SidebarRowBackground(isSelected: isSelected, isHovered: isHovered))
                .clipShape(RoundedRectangle(cornerRadius: SidebarStyle.rowCornerRadius, style: .continuous))
        } else {
            HStack(spacing: 10) {
                // Agent indicator
                if isDefaultAgent {
                    defaultAgentIndicator
                } else if let agent = agent {
                    agentIndicatorView(agent)
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text(session.title)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(theme.primaryText)
                        .lineLimit(1)

                    Text(formatRelativeDate(session.updatedAt))
                        .font(.system(size: 10))
                        .foregroundColor(theme.secondaryText.opacity(0.85))
                }
                Spacer()

                // Action buttons (visible on hover)
                if isHovered {
                    HStack(spacing: 4) {
                        SidebarRowActionButton(
                            icon: "pencil",
                            help: "Rename",
                            action: onStartRename
                        )

                        SidebarRowActionButton(
                            icon: "trash",
                            help: "Delete",
                            action: onDelete
                        )
                    }
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
            .animation(theme.springAnimation(responseMultiplier: 0.8), value: isSelected)
            .contextMenu {
                if let openInNewWindow = onOpenInNewWindow {
                    Button {
                        openInNewWindow()
                    } label: {
                        Label { Text("Open in New Window", bundle: .module) } icon: { Image(systemName: "macwindow.badge.plus") }
                    }
                    Divider()
                }
                Button( action: onStartRename) { Text("Rename", bundle: .module) }
                Button(role: .destructive, action: onDelete) { Text("Delete", bundle: .module) }
            }
        }
    }

    /// Default agent indicator with person icon
    private var defaultAgentIndicator: some View {
        ZStack {
            Circle()
                .fill(theme.secondaryText.opacity(theme.isDark ? 0.12 : 0.08))
                .frame(width: 24, height: 24)

            Image(systemName: "person.fill")
                .font(.system(size: 10, weight: .medium))
                .foregroundColor(theme.secondaryText.opacity(0.8))
        }
        .help(Text("Default", bundle: .module))
    }

    @ViewBuilder
    private func agentIndicatorView(_ agent: Agent) -> some View {
        ZStack {
            Circle()
                .fill(agentColor.opacity(theme.isDark ? 0.14 : 0.10))
                .frame(width: 24, height: 24)

            Text(agent.name.prefix(1).uppercased())
                .font(.system(size: 10, weight: .bold, design: .rounded))
                .foregroundColor(agentColor)
        }
        .help(agent.name)
    }

    private var editingView: some View {
        TextField(text: $editingTitle, prompt: Text("Title", bundle: .module)) {
            Text("Title", bundle: .module)
        }
        .onSubmit(onConfirmRename)
            .textFieldStyle(.plain)
            .font(.system(size: 12, weight: .medium))
            .foregroundColor(theme.primaryText)
            .padding(.horizontal, 4)
            .padding(.vertical, 2)
            .background(theme.primaryBackground.opacity(0.5))
            .clipShape(RoundedRectangle(cornerRadius: 4))
            .focused($isTextFieldFocused)
            .onExitCommand(perform: onCancelRename)
            .onAppear {
                isTextFieldFocused = true
            }
            .onChange(of: isTextFieldFocused) { _, focused in
                if !focused {
                    // Clicked outside - confirm the rename
                    onConfirmRename()
                }
            }
    }

}
