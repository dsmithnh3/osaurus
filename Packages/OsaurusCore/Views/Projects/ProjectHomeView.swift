//
//  ProjectHomeView.swift
//  osaurus
//
//  Center panel of the project view — header, outputs grid, and recents list.
//

import SwiftUI

/// Determines whether project input creates a chat or work task.
private enum ProjectInputMode: String, CaseIterable {
    case chat
    case work
}

/// Center panel of the project view.
struct ProjectHomeView: View {
    let project: Project
    @ObservedObject var windowState: ChatWindowState
    var onFileSelected: ((String) -> Void)?

    @StateObject private var inputSession: ChatSession

    @Environment(\.theme) private var theme

    @State private var isFolderHovered = false
    @State private var projectInputMode: ProjectInputMode = .chat
    @Namespace private var modePickerAnimation

    init(project: Project, windowState: ChatWindowState, onFileSelected: ((String) -> Void)? = nil) {
        self.project = project
        self._windowState = ObservedObject(wrappedValue: windowState)
        self.onFileSelected = onFileSelected
        self._inputSession = StateObject(wrappedValue: ChatSession())
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 24) {
                    headerSection
                    outputsSection
                    recentsSection
                }
                .padding(20)
                .padding(.bottom, 100)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            VStack(spacing: 8) {
                // Mode picker
                HStack(spacing: 0) {
                    modeSegment(.chat, icon: "bubble.left", label: "Chat")
                    modeSegment(.work, icon: "bolt.circle", label: "Work")
                }
                .padding(2)
                .background(
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .fill(theme.secondaryBackground.opacity(0.3))
                )

                FloatingInputCard(
                    text: $inputSession.input,
                    selectedModel: $inputSession.selectedModel,
                    pendingAttachments: $inputSession.pendingAttachments,
                    isContinuousVoiceMode: $inputSession.isContinuousVoiceMode,
                    voiceInputState: $inputSession.voiceInputState,
                    showVoiceOverlay: $inputSession.showVoiceOverlay,
                    pickerItems: inputSession.pickerItems,
                    activeModelOptions: $inputSession.activeModelOptions,
                    isStreaming: inputSession.isStreaming,
                    supportsImages: false,
                    estimatedContextTokens: 0,
                    onSend: { manualText in
                        let message = manualText ?? inputSession.input
                        let trimmed = message.trimmingCharacters(in: .whitespacesAndNewlines)
                        guard !trimmed.isEmpty else { return }

                        switch projectInputMode {
                        case .chat:
                            windowState.startNewChat()
                            windowState.session.input = trimmed
                            windowState.projectSession?.inlineSessionId = windowState.session.sessionId
                            windowState.pushNavigation(NavigationEntry(
                                mode: .project, projectId: project.id,
                                sessionId: windowState.session.sessionId
                            ))
                            windowState.session.sendCurrent()
                        case .work:
                            windowState.projectSession?.inlineWorkTaskId = UUID()
                            windowState.pushNavigation(NavigationEntry(
                                mode: .project, projectId: project.id,
                                workTaskId: windowState.projectSession?.inlineWorkTaskId
                            ))
                        }
                        inputSession.input = ""
                    },
                    onStop: {},
                    agentId: windowState.agentId,
                    windowId: windowState.windowId,
                    onClearChat: { inputSession.reset() },
                    onSkillSelected: { skillId in
                        inputSession.pendingOneOffSkillId = skillId
                    },
                    pendingSkillId: $inputSession.pendingOneOffSkillId
                )
                .frame(maxWidth: 1100)
                .frame(maxWidth: .infinity)
            }
            .padding(.bottom, 12)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.trailing, windowState.showProjectInspector ? SidebarStyle.inspectorWidth : 0)
    }

    private var headerSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(project.name)
                .font(.title)
                .foregroundColor(theme.primaryText)

            Text("What would you like to work on in this project?")
                .font(.subheadline)
                .foregroundColor(theme.secondaryText)

            if let folderPath = project.folderPath {
                Button(action: {
                    NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: folderPath)
                }) {
                    HStack(spacing: 4) {
                        Image(systemName: "folder")
                            .font(.system(size: 11))
                        Text(folderPath)
                            .font(.system(size: 11))
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                    .foregroundColor(isFolderHovered ? theme.secondaryText : theme.tertiaryText)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .fill(isFolderHovered ? theme.secondaryBackground.opacity(0.5) : theme.secondaryBackground.opacity(0.3))
                    )
                }
                .buttonStyle(.plain)
                .onHover { hovering in
                    withAnimation(.easeInOut(duration: 0.15)) {
                        isFolderHovered = hovering
                    }
                }
            }
        }
    }

    private var outputsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Outputs")
                .font(.headline)
                .foregroundColor(theme.primaryText)

            VStack(spacing: 8) {
                Image(systemName: "rectangle.stack")
                    .font(.system(size: 20))
                    .foregroundColor(theme.tertiaryText)
                Text("No outputs yet")
                    .font(.subheadline)
                    .foregroundColor(theme.tertiaryText)
                Text("Outputs from tasks will appear here")
                    .font(.caption)
                    .foregroundColor(theme.tertiaryText.opacity(0.7))
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 24)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(theme.secondaryBackground.opacity(0.2))
            )
        }
    }

    private var recentsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Recents")
                .font(.headline)
                .foregroundColor(theme.primaryText)

            VStack(spacing: 8) {
                Image(systemName: "bubble.left.and.bubble.right")
                    .font(.system(size: 20))
                    .foregroundColor(theme.tertiaryText)
                Text("No recent conversations")
                    .font(.subheadline)
                    .foregroundColor(theme.tertiaryText)
                Text("Conversations in this project will appear here")
                    .font(.caption)
                    .foregroundColor(theme.tertiaryText.opacity(0.7))
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 24)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(theme.secondaryBackground.opacity(0.2))
            )
        }
    }

    @ViewBuilder
    private func modeSegment(_ mode: ProjectInputMode, icon: String, label: String) -> some View {
        HStack(spacing: 5) {
            Image(systemName: icon)
                .font(.system(size: 10, weight: .semibold))
            Text(label)
                .font(.system(size: 11, weight: .semibold))
        }
        .fixedSize()
        .foregroundColor(projectInputMode == mode ? theme.primaryText : theme.tertiaryText)
        .padding(.horizontal, 14)
        .padding(.vertical, 5)
        .background {
            if projectInputMode == mode {
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .fill(theme.secondaryBackground.opacity(0.8))
                    .shadow(color: theme.shadowColor.opacity(0.08), radius: 1.5, x: 0, y: 0.5)
                    .matchedGeometryEffect(id: "modePickerIndicator", in: modePickerAnimation)
            }
        }
        .contentShape(Rectangle())
        .animation(theme.springAnimation(), value: projectInputMode == mode)
        .onTapGesture { projectInputMode = mode }
    }
}
