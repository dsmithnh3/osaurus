//
//  ProjectInlineChatView.swift
//  osaurus
//
//  Full chat rendering embedded within the Projects tab.
//  Replicates ChatView's message thread + input card without its own sidebar.
//

import SwiftUI

/// Full inline chat view for the Projects tab.
/// Renders the active ChatSession's message thread and input card.
struct ProjectInlineChatView: View {
    @ObservedObject var windowState: ChatWindowState
    @ObservedObject var session: ChatSession

    @State private var isPinnedToBottom: Bool = true
    @State private var scrollToBottomTrigger: Int = 0
    @State private var editingTurnId: UUID?
    @State private var editText: String = ""
    @State private var userImagePreview: NSImage?

    private var theme: ThemeProtocol { windowState.theme }

    init(windowState: ChatWindowState) {
        self.windowState = windowState
        self.session = windowState.session
    }

    var body: some View {
        VStack(spacing: 0) {
            // Spacer for toolbar clearance
            Color.clear
                .frame(height: 52)
                .allowsHitTesting(false)

            if session.hasAnyModel || session.isDiscoveringModels {
                if !session.hasVisibleThreadMessages {
                    // Empty state while waiting for first response
                    VStack(spacing: 12) {
                        ProgressView()
                            .scaleEffect(0.8)
                        Text("Starting conversation...")
                            .font(.subheadline)
                            .foregroundColor(theme.secondaryText)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    // Message thread
                    messageThread
                }

                // Input card for follow-up messages
                FloatingInputCard(
                    text: $session.input,
                    selectedModel: $session.selectedModel,
                    pendingAttachments: $session.pendingAttachments,
                    isContinuousVoiceMode: $session.isContinuousVoiceMode,
                    voiceInputState: $session.voiceInputState,
                    showVoiceOverlay: $session.showVoiceOverlay,
                    pickerItems: session.pickerItems,
                    activeModelOptions: $session.activeModelOptions,
                    isStreaming: session.isStreaming,
                    supportsImages: session.selectedModelSupportsImages,
                    estimatedContextTokens: session.estimatedContextTokens,
                    contextBreakdown: session.estimatedContextBreakdown,
                    onSend: { manualText in
                        if let manualText = manualText {
                            session.input = manualText
                        }
                        session.sendCurrent()
                    },
                    onStop: { session.stop() },
                    agentId: windowState.agentId,
                    windowId: windowState.windowId,
                    onClearChat: { session.reset() },
                    onSkillSelected: { skillId in
                        session.pendingOneOffSkillId = skillId
                    },
                    pendingSkillId: $session.pendingOneOffSkillId
                )
                .frame(maxWidth: 1100)
                .frame(maxWidth: .infinity)
            } else {
                Spacer()
                Text("No models available")
                    .font(.subheadline)
                    .foregroundColor(theme.tertiaryText)
                Spacer()
            }
        }
        .padding(.trailing, windowState.showProjectInspector ? SidebarStyle.inspectorWidth : 0)
        .sheet(
            isPresented: Binding(
                get: { userImagePreview != nil },
                set: { if !$0 { userImagePreview = nil } }
            )
        ) {
            if let img = userImagePreview {
                ImageFullScreenView(image: img, altText: "")
                    .imageFullScreenSheetPresentation()
            }
        }
    }

    // MARK: - Message Thread

    private var messageThread: some View {
        let blocks = session.visibleBlocks
        let groupHeaderMap = session.visibleBlocksGroupHeaderMap
        let displayName = windowState.cachedAgentDisplayName
        let lastAssistantTurnId = session.lastAssistantTurnIdForThread

        return ZStack {
            MessageThreadView(
                blocks: blocks,
                groupHeaderMap: groupHeaderMap,
                width: 1100,
                agentName: displayName,
                isStreaming: session.isStreaming,
                lastAssistantTurnId: lastAssistantTurnId,
                expandedBlocksStore: session.expandedBlocksStore,
                scrollToBottomTrigger: scrollToBottomTrigger,
                onScrolledToBottom: { isPinnedToBottom = true },
                onScrolledAwayFromBottom: { isPinnedToBottom = false },
                onCopy: copyTurnContent,
                onRegenerate: regenerateTurn,
                onEdit: beginEditingTurn,
                onDelete: deleteTurn,
                editingTurnId: editingTurnId,
                editText: $editText,
                onConfirmEdit: confirmEditAndRegenerate,
                onCancelEdit: cancelEditing,
                onUserImagePreview: openUserAttachmentPreview
            )

            // Scroll button overlay
            VStack {
                Spacer()
                HStack {
                    Spacer()
                    ScrollToBottomButton(
                        isPinnedToBottom: isPinnedToBottom,
                        hasTurns: session.hasVisibleThreadMessages,
                        onTap: {
                            isPinnedToBottom = true
                            scrollToBottomTrigger += 1
                        }
                    )
                }
            }
        }
    }

    // MARK: - Message Actions

    private func copyTurnContent(turnId: UUID) {
        guard let turn = session.turns.first(where: { $0.id == turnId }) else { return }
        var textToCopy = ""
        if turn.hasThinking {
            textToCopy += turn.thinking
        }
        if !turn.contentIsEmpty {
            if !textToCopy.isEmpty { textToCopy += "\n\n" }
            textToCopy += turn.visibleContent
        }
        guard !textToCopy.isEmpty else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(textToCopy, forType: .string)
    }

    private func regenerateTurn(turnId: UUID) {
        session.regenerate(turnId: turnId)
    }

    private func deleteTurn(turnId: UUID) {
        if session.isStreaming { session.stop() }
        session.deleteTurn(id: turnId)
    }

    private func beginEditingTurn(turnId: UUID) {
        guard let turn = session.turns.first(where: { $0.id == turnId }),
              turn.role == .user
        else { return }
        editText = turn.content
        editingTurnId = turnId
    }

    private func confirmEditAndRegenerate() {
        guard let turnId = editingTurnId else { return }
        let trimmed = editText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        session.editAndRegenerate(turnId: turnId, newContent: trimmed)
        editingTurnId = nil
        editText = ""
    }

    private func cancelEditing() {
        editingTurnId = nil
        editText = ""
    }

    private func openUserAttachmentPreview(attachmentId: String) {
        if let img = ChatImageCache.shared.cachedImage(for: attachmentId) {
            userImagePreview = img
            return
        }
        for turn in session.turns {
            for att in turn.attachments where att.id.uuidString == attachmentId {
                if let data = att.imageData, let img = NSImage(data: data) {
                    userImagePreview = img
                    return
                }
            }
        }
    }
}
