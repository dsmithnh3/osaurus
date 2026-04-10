//
//  ProjectHomeView.swift
//  osaurus
//
//  Center panel of the project view — header, outputs grid, and recents list.
//

import SwiftUI

/// Center panel of the project view.
struct ProjectHomeView: View {
    let project: Project
    @ObservedObject var windowState: ChatWindowState

    @StateObject private var inputSession: ChatSession

    @Environment(\.theme) private var theme

    @State private var isFolderHovered = false
    @State private var isInspectorButtonHovered = false

    init(project: Project, windowState: ChatWindowState) {
        self.project = project
        self._windowState = ObservedObject(wrappedValue: windowState)
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
                    // Create a new project-scoped chat, switch to chat mode
                    windowState.startNewChat()
                    windowState.session.input = trimmed
                    windowState.switchMode(to: .chat)
                    windowState.pushNavigation(NavigationEntry(mode: .chat, projectId: project.id))
                    windowState.session.sendCurrent()
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
            .frame(maxWidth: 800)
            .frame(maxWidth: .infinity)
            .padding(.bottom, 12)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.trailing, windowState.showProjectInspector ? 300 : 0)
    }

    private var headerSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(project.name)
                    .font(.title)
                    .foregroundColor(theme.primaryText)

                Spacer()

                Button(action: { windowState.showProjectInspector.toggle() }) {
                    Image(systemName: "sidebar.right")
                        .font(.system(size: 14))
                        .foregroundColor(isInspectorButtonHovered ? theme.primaryText : theme.secondaryText)
                        .padding(6)
                        .background(
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .fill(isInspectorButtonHovered ? theme.secondaryBackground.opacity(0.5) : Color.clear)
                        )
                }
                .buttonStyle(.plain)
                .onHover { hovering in
                    withAnimation(.easeInOut(duration: 0.15)) {
                        isInspectorButtonHovered = hovering
                    }
                }
                .help("Toggle inspector")
            }

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
}
