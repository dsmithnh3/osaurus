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

    init(project: Project, windowState: ChatWindowState) {
        self.project = project
        self._windowState = ObservedObject(wrappedValue: windowState)
        self._inputSession = StateObject(wrappedValue: ChatSession())
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
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
                        .foregroundColor(theme.secondaryText)
                }
                .buttonStyle(.plain)
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
                    .foregroundColor(theme.tertiaryText)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .fill(theme.secondaryBackground.opacity(0.3))
                    )
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var outputsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Outputs")
                .font(.headline)
                .foregroundColor(theme.primaryText)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    Text("No outputs yet")
                        .font(.subheadline)
                        .foregroundColor(theme.tertiaryText)
                        .padding(20)
                }
            }
        }
    }

    private var recentsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Recents")
                .font(.headline)
                .foregroundColor(theme.primaryText)

            Text("No recent conversations")
                .font(.subheadline)
                .foregroundColor(theme.tertiaryText)
        }
    }
}
