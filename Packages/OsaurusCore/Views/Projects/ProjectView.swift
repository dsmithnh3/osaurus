//
//  ProjectView.swift
//  osaurus
//
//  Unified workspace coordinator for the project 3-panel layout.
//  Directly composes chat and work content instead of delegating to
//  ProjectInlineChatView or ProjectInlineWorkView.
//

import SwiftUI

/// Coordinator for the project 3-panel layout: sidebar + center (chat or work) + inspector.
struct ProjectView: View {
    @ObservedObject var windowState: ChatWindowState
    let session: ProjectSession

    /// Observed chat session for proper SwiftUI binding propagation.
    @ObservedObject private var chatSession: ChatSession

    @Environment(\.theme) private var theme
    @State private var previewArtifact: SharedArtifact?

    // MARK: - Chat State

    @State private var chatIsPinnedToBottom: Bool = true
    @State private var chatScrollToBottomTrigger: Int = 0
    @State private var editingTurnId: UUID?
    @State private var editText: String = ""
    @State private var userImagePreview: NSImage?

    // MARK: - Work State

    @State private var workIsPinnedToBottom: Bool = true
    @State private var workScrollToBottomTrigger: Int = 0
    @State private var isProgressPanelOpen: Bool = false
    @State private var selectedArtifact: SharedArtifact?
    @State private var fileOperations: [WorkFileOperation] = []

    // MARK: - Picker Animation

    @Namespace private var modePickerAnimation

    // MARK: - Init

    init(windowState: ChatWindowState, session: ProjectSession) {
        self.windowState = windowState
        self.session = session
        self._chatSession = ObservedObject(wrappedValue: windowState.session)
    }

    // MARK: - Body

    var body: some View {
        GeometryReader { proxy in
            let sidebarWidth: CGFloat = windowState.showSidebar ? SidebarStyle.width : 0

            HStack(alignment: .top, spacing: 0) {
                if windowState.showSidebar {
                    AppSidebar(windowState: windowState, session: windowState.session)
                        .transition(.move(edge: .leading).combined(with: .opacity))
                }

                ZStack(alignment: .trailing) {
                    ThemedBackgroundLayer(
                        cachedBackgroundImage: windowState.cachedBackgroundImage,
                        showSidebar: windowState.showSidebar
                    )

                    centerContent
                        .transition(.opacity)

                    if windowState.showProjectInspector,
                       let projectId = session.activeProjectId,
                       let project = projectFor(projectId)
                    {
                        ProjectInspectorPanel(
                            project: project,
                            onFileSelected: openFilePreview,
                            onArtifactSelected: { previewArtifact = $0 }
                        )
                        .transition(.move(edge: .trailing))
                    }
                }
                .frame(width: proxy.size.width - sidebarWidth)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .animation(
            .spring(response: 0.35, dampingFraction: 0.88),
            value: windowState.showProjectInspector
        )
        .animation(theme.springAnimation(responseMultiplier: 0.9), value: windowState.showSidebar)
        // Sub-mode work tool registration + work session creation
        .onChange(of: session.subMode) { old, new in
            if new == .work {
                WorkToolManager.shared.registerTools()
                if windowState.workSession == nil {
                    windowState.workSession = WorkSession(
                        agentId: windowState.agentId, windowState: windowState)
                }
            }
            if old == .work && new != .work { WorkToolManager.shared.unregisterTools() }
        }
        .sheet(item: $previewArtifact) { artifact in
            ArtifactViewerSheet(artifact: artifact, onDismiss: { previewArtifact = nil })
                .environment(\.theme, windowState.theme)
        }
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
        // Work file operations tracking
        .onChange(of: windowState.workSession?.currentTask?.id) { refreshFileOperations() }
        .onAppear { refreshFileOperations() }
        .onReceive(NotificationCenter.default.publisher(for: .workFileOperationsDidChange)) { _ in
            refreshFileOperations()
        }
    }

    // MARK: - Center Content Routing

    @ViewBuilder
    private var centerContent: some View {
        if session.activeProjectId != nil {
            VStack(spacing: 0) {
                // Toolbar clearance
                Color.clear.frame(height: 52).allowsHitTesting(false)

                // Content based on sub-mode
                switch session.subMode {
                case .chat:
                    projectChatContent
                case .work:
                    projectWorkContent
                }
            }
            .padding(.trailing, windowState.showProjectInspector ? SidebarStyle.inspectorWidth : 0)
        } else {
            ProjectListView(windowState: windowState)
        }
    }

    // MARK: - Chat Content

    @ViewBuilder
    private var projectChatContent: some View {
        if chatSession.hasAnyModel || chatSession.isDiscoveringModels {
            if !chatSession.hasVisibleThreadMessages {
                ChatEmptyState(
                    hasModels: true,
                    selectedModel: chatSession.selectedModel,
                    agents: windowState.agents,
                    activeAgentId: windowState.agentId,
                    quickActions: windowState.activeAgent.chatQuickActions
                        ?? AgentQuickAction.defaultChatQuickActions,
                    onOpenModelManager: {
                        AppDelegate.shared?.showManagementWindow(initialTab: .models)
                    },
                    onUseFoundation: windowState.foundationModelAvailable
                        ? {
                            chatSession.selectedModel =
                                chatSession.pickerItems.first?.id ?? "foundation"
                        } : nil,
                    onQuickAction: { prompt in chatSession.input = prompt },
                    onSelectAgent: { newAgentId in windowState.switchAgent(to: newAgentId) },
                    onOpenOnboarding: nil,
                    discoveredAgents: windowState.discoveredAgents,
                    onSelectDiscoveredAgent: { _ in },
                    activeDiscoveredAgent: windowState.selectedDiscoveredAgent
                )
                .transition(.opacity.combined(with: .scale(scale: 0.98)))
            } else {
                chatMessageThread
            }

            // Chat/Work picker + input card
            chatWorkPicker

            FloatingInputCard(
                text: $chatSession.input,
                selectedModel: $chatSession.selectedModel,
                pendingAttachments: $chatSession.pendingAttachments,
                isContinuousVoiceMode: $chatSession.isContinuousVoiceMode,
                voiceInputState: $chatSession.voiceInputState,
                showVoiceOverlay: $chatSession.showVoiceOverlay,
                pickerItems: chatSession.pickerItems,
                activeModelOptions: $chatSession.activeModelOptions,
                isStreaming: chatSession.isStreaming,
                supportsImages: chatSession.selectedModelSupportsImages,
                estimatedContextTokens: chatSession.estimatedContextTokens,
                contextBreakdown: chatSession.estimatedContextBreakdown,
                onSend: { manualText in
                    if let manualText = manualText {
                        chatSession.input = manualText
                    }
                    chatSession.sendCurrent()
                },
                onStop: { chatSession.stop() },
                agentId: windowState.agentId,
                windowId: windowState.windowId,
                onClearChat: { chatSession.reset() },
                onSkillSelected: { skillId in
                    chatSession.pendingOneOffSkillId = skillId
                },
                pendingSkillId: $chatSession.pendingOneOffSkillId
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

    // MARK: - Chat Message Thread

    private var chatMessageThread: some View {
        let blocks = chatSession.visibleBlocks
        let groupHeaderMap = chatSession.visibleBlocksGroupHeaderMap
        let displayName = windowState.cachedAgentDisplayName
        let lastAssistantTurnId = chatSession.lastAssistantTurnIdForThread

        return ZStack {
            MessageThreadView(
                blocks: blocks,
                groupHeaderMap: groupHeaderMap,
                width: 1100,
                agentName: displayName,
                isStreaming: chatSession.isStreaming,
                lastAssistantTurnId: lastAssistantTurnId,
                expandedBlocksStore: chatSession.expandedBlocksStore,
                scrollToBottomTrigger: chatScrollToBottomTrigger,
                onScrolledToBottom: { chatIsPinnedToBottom = true },
                onScrolledAwayFromBottom: { chatIsPinnedToBottom = false },
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
                        isPinnedToBottom: chatIsPinnedToBottom,
                        hasTurns: chatSession.hasVisibleThreadMessages,
                        onTap: {
                            chatIsPinnedToBottom = true
                            chatScrollToBottomTrigger += 1
                        }
                    )
                }
            }
        }
    }

    // MARK: - Chat Message Actions

    private func copyTurnContent(turnId: UUID) {
        guard let turn = chatSession.turns.first(where: { $0.id == turnId }) else { return }
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
        chatSession.regenerate(turnId: turnId)
    }

    private func deleteTurn(turnId: UUID) {
        if chatSession.isStreaming { chatSession.stop() }
        chatSession.deleteTurn(id: turnId)
    }

    private func beginEditingTurn(turnId: UUID) {
        guard let turn = chatSession.turns.first(where: { $0.id == turnId }),
              turn.role == .user
        else { return }
        editText = turn.content
        editingTurnId = turnId
    }

    private func confirmEditAndRegenerate() {
        guard let turnId = editingTurnId else { return }
        let trimmed = editText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        chatSession.editAndRegenerate(turnId: turnId, newContent: trimmed)
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
        for turn in chatSession.turns {
            for att in turn.attachments where att.id.uuidString == attachmentId {
                if let data = att.imageData, let img = NSImage(data: data) {
                    userImagePreview = img
                    return
                }
            }
        }
    }

    // MARK: - Work Content

    @ViewBuilder
    private var projectWorkContent: some View {
        if let workSession = windowState.workSession {
            if workSession.currentTask == nil {
                WorkEmptyState(
                    hasModels: !workSession.pickerItems.isEmpty,
                    selectedModel: workSession.selectedModel,
                    agents: windowState.agents,
                    activeAgentId: windowState.agentId,
                    quickActions: windowState.activeAgent.workQuickActions
                        ?? AgentQuickAction.defaultWorkQuickActions,
                    onOpenModelManager: {
                        AppDelegate.shared?.showManagementWindow(initialTab: .models)
                    },
                    onUseFoundation: windowState.foundationModelAvailable
                        ? {
                            workSession.selectedModel =
                                workSession.pickerItems.first?.id ?? "foundation"
                        } : nil,
                    onQuickAction: { prompt in
                        workSession.input = prompt
                    },
                    onSelectAgent: { newAgentId in
                        windowState.switchAgent(to: newAgentId)
                    }
                )
            } else {
                workTaskExecutionView(workSession: workSession)
            }

            // Chat/Work picker + input card
            chatWorkPicker

            FloatingInputCard(
                text: Binding(
                    get: { workSession.input },
                    set: { workSession.input = $0 }
                ),
                selectedModel: Binding(
                    get: { workSession.selectedModel },
                    set: { workSession.selectedModel = $0 }
                ),
                pendingAttachments: Binding(
                    get: { workSession.pendingAttachments },
                    set: { workSession.pendingAttachments = $0 }
                ),
                isContinuousVoiceMode: Binding(
                    get: { workSession.isContinuousVoiceMode },
                    set: { workSession.isContinuousVoiceMode = $0 }
                ),
                voiceInputState: Binding(
                    get: { workSession.voiceInputState },
                    set: { workSession.voiceInputState = $0 }
                ),
                showVoiceOverlay: Binding(
                    get: { workSession.showVoiceOverlay },
                    set: { workSession.showVoiceOverlay = $0 }
                ),
                pickerItems: workSession.pickerItems,
                activeModelOptions: .constant([:]),
                isStreaming: workSession.isExecuting,
                supportsImages: workSession.selectedModelSupportsImages,
                estimatedContextTokens: workSession.estimatedContextTokens,
                contextBreakdown: workSession.estimatedContextBreakdown,
                onSend: { manualText in
                    if let manualText = manualText {
                        workSession.input = manualText
                    }
                    Task { await workSession.handleUserInput() }
                },
                onStop: { workSession.stopExecution() },
                agentId: windowState.agentId,
                windowId: windowState.windowId,
                workInputState: workSession.inputState,
                pendingQueuedMessage: workSession.pendingQueuedMessage,
                onClearQueued: { workSession.clearQueuedMessage() },
                onSendNow: {
                    Task { workSession.redirectExecution(message: workSession.input) }
                },
                onEndTask: { workSession.endTask() },
                onResume: { Task { await workSession.resumeSelectedIssue() } },
                canResume: workSession.canResumeSelectedIssue,
                cumulativeTokens: workSession.cumulativeTokens,
                onSkillSelected: { skillId in
                    workSession.pendingOneOffSkillId = skillId
                },
                pendingSkillId: Binding(
                    get: { workSession.pendingOneOffSkillId },
                    set: { workSession.pendingOneOffSkillId = $0 }
                )
            )
            .frame(maxWidth: 1100)
            .frame(maxWidth: .infinity)
        } else {
            Spacer()
            Text("Initializing work session...")
                .font(.subheadline)
                .foregroundColor(theme.tertiaryText)
            Spacer()
        }
    }

    // MARK: - Work Task Execution View

    private func workTaskExecutionView(workSession: WorkSession) -> some View {
        let hasBlocks = !workSession.issueBlocks.isEmpty

        return ZStack(alignment: .trailing) {
            // Layer 1: Full-width chat content
            ZStack(alignment: .bottom) {
                VStack(spacing: 0) {
                    if workSession.selectedIssueId != nil && hasBlocks {
                        workIssueDetailView(workSession: workSession)
                    } else {
                        workIssueEmptyDetailView
                    }

                    if let error = workSession.errorMessage {
                        workErrorBanner(error: error)
                    }
                    Spacer(minLength: 0)
                }

                if workSession.isExecuting {
                    workProcessingIndicator(workSession: workSession)
                        .transition(.opacity.combined(with: .move(edge: .bottom)))
                }
            }
            .frame(maxWidth: .infinity)

            // Layer 2: Status button (visible when panel is closed)
            if !isProgressPanelOpen {
                WorkStatusButton(
                    isExecuting: workSession.isExecuting,
                    issues: workSession.issues,
                    artifactCount: workSession.sharedArtifacts.count,
                    fileOpCount: fileOperations.count,
                    onTap: { isProgressPanelOpen = true }
                )
                .padding(.trailing, 16)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                .padding(.top, 14)
                .transition(.opacity)
            }

            // Layer 3: Overlay panel (toggled open)
            if isProgressPanelOpen {
                HStack(spacing: 0) {
                    Color.black.opacity(0.001)
                        .contentShape(Rectangle())
                        .onTapGesture { isProgressPanelOpen = false }

                    IssueTrackerPanel(
                        issues: workSession.issues,
                        activeIssueId: workSession.activeIssue?.id,
                        selectedIssueId: workSession.selectedIssueId,
                        finalArtifact: workSession.finalArtifact,
                        sharedArtifacts: workSession.sharedArtifacts,
                        fileOperations: fileOperations,
                        onDismiss: { isProgressPanelOpen = false },
                        onIssueSelect: { workSession.selectIssue($0) },
                        onIssueRun: { issue in Task { await workSession.executeIssue(issue) } },
                        onIssueClose: { issueId in
                            Task {
                                await workSession.closeIssue(issueId, reason: "Manually closed")
                            }
                        },
                        onArtifactView: { selectedArtifact = $0 },
                        onArtifactOpen: { artifact in
                            let url = URL(fileURLWithPath: artifact.hostPath)
                            NSWorkspace.shared.activateFileViewerSelecting([url])
                        },
                        onUndoOperation: { operationId in
                            undoFileOperation(operationId: operationId)
                        },
                        onUndoAllOperations: { undoAllFileOperations() }
                    )
                    .frame(width: 280)
                    .padding(.vertical, 12)
                    .padding(.trailing, 12)
                    .shadow(color: theme.shadowColor.opacity(0.2), radius: 16, x: -4, y: 0)
                }
                .transition(.move(edge: .trailing).combined(with: .opacity))
            }
        }
        .animation(theme.springAnimation(responseMultiplier: 0.8), value: isProgressPanelOpen)
        .sheet(item: $selectedArtifact) { artifact in
            ArtifactViewerSheet(
                artifact: artifact,
                onDismiss: { selectedArtifact = nil }
            )
            .environment(\.theme, windowState.theme)
        }
    }

    // MARK: - Work Issue Detail View

    private func workIssueDetailView(workSession: WorkSession) -> some View {
        let blocks = workSession.issueBlocks
        let groupHeaderMap = workSession.issueBlocksGroupHeaderMap
        let agentName = windowState.cachedAgentDisplayName

        return ZStack(alignment: .bottomTrailing) {
            MessageThreadView(
                blocks: blocks,
                groupHeaderMap: groupHeaderMap,
                width: 1100,
                agentName: agentName,
                isStreaming: workSession.isExecuting
                    && workSession.activeIssue?.id == workSession.selectedIssueId,
                lastAssistantTurnId: blocks.last?.turnId,
                autoScrollEnabled: false,
                expandedBlocksStore: workSession.expandedBlocksStore,
                scrollToBottomTrigger: workScrollToBottomTrigger,
                onScrolledToBottom: { workIsPinnedToBottom = true },
                onScrolledAwayFromBottom: { workIsPinnedToBottom = false },
                onCopy: workCopyTurnContent
            )

            ScrollToBottomButton(
                isPinnedToBottom: workIsPinnedToBottom,
                hasTurns: !blocks.isEmpty,
                onTap: {
                    workIsPinnedToBottom = true
                    workScrollToBottomTrigger += 1
                }
            )
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.top, 16)
        .overlay {
            if let request = workSession.pendingClarification {
                ClarificationOverlay(request: request) { response in
                    Task { await workSession.submitClarification(response) }
                }
            }
        }
        .overlay {
            if let promptState = workSession.pendingSecretPrompt {
                SecretPromptOverlay(state: promptState) {
                    promptState.cancel()
                    workSession.pendingSecretPrompt = nil
                }
            }
        }
    }

    private var workIssueEmptyDetailView: some View {
        VStack(spacing: 12) {
            Image(systemName: "doc.text.magnifyingglass")
                .font(.system(size: 32, weight: .regular))
                .foregroundColor(theme.tertiaryText)

            Text("No execution history", bundle: .module)
                .font(theme.font(size: CGFloat(theme.bodySize) + 1, weight: .medium))
                .foregroundColor(theme.secondaryText)

            Text(
                "Select an issue to view its details, or run it to see live execution.",
                bundle: .module
            )
            .font(theme.font(size: CGFloat(theme.captionSize), weight: .regular))
            .foregroundColor(theme.tertiaryText)
            .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.horizontal, 20)
    }

    // MARK: - Work Processing Indicator

    private func workProcessingIndicator(workSession: WorkSession) -> some View {
        HStack(spacing: 6) {
            Circle()
                .fill(theme.accentColor.opacity(0.6))
                .frame(width: 5, height: 5)
                .modifier(WorkPulseModifier())

            Text(workSession.loopState?.statusMessage ?? "Working on it...")
                .font(
                    theme.font(size: CGFloat(theme.captionSize) - 1, weight: .regular))
                .foregroundColor(theme.tertiaryText)
                .animation(
                    .easeInOut(duration: 0.2), value: workSession.loopState?.statusMessage)
        }
        .padding(.bottom, 12)
    }

    // MARK: - Work Error Banner

    private func workErrorBanner(error: String) -> some View {
        HStack(spacing: 16) {
            ZStack {
                Circle()
                    .fill(theme.errorColor.opacity(0.15))
                    .frame(width: 40, height: 40)
                Image(systemName: "exclamationmark.circle.fill")
                    .font(.system(size: 20, weight: .regular))
                    .foregroundColor(theme.errorColor)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text("An error occurred")
                    .font(
                        theme.font(size: CGFloat(theme.bodySize) + 1, weight: .semibold))
                    .foregroundColor(theme.primaryText)

                Text(error)
                    .font(
                        theme.font(size: CGFloat(theme.captionSize), weight: .regular))
                    .foregroundColor(theme.secondaryText)
                    .lineLimit(2)
            }

            Spacer(minLength: 12)
        }
        .padding()
    }

    // MARK: - Work File Operations

    private func refreshFileOperations() {
        guard let workSession = windowState.workSession,
              workSession.currentTask != nil
        else {
            fileOperations = []
            return
        }
        Task { @MainActor in
            var allOperations: [WorkFileOperation] = []
            for issue in workSession.issues {
                let ops = await WorkFileOperationLog.shared.operations(for: issue.id)
                allOperations.append(contentsOf: ops)
            }
            fileOperations = allOperations.sorted { $0.timestamp > $1.timestamp }
        }
    }

    private func undoFileOperation(operationId: UUID) {
        guard let workSession = windowState.workSession else { return }
        Task {
            for issue in workSession.issues {
                do {
                    if let _ = try await WorkFileOperationLog.shared.undo(
                        issueId: issue.id,
                        operationId: operationId
                    ) {
                        return
                    }
                } catch {
                    continue
                }
            }
        }
    }

    private func undoAllFileOperations() {
        guard let workSession = windowState.workSession else { return }
        Task {
            for issue in workSession.issues {
                _ = try? await WorkFileOperationLog.shared.undoAll(issueId: issue.id)
            }
        }
    }

    private func workCopyTurnContent(turnId: UUID) {
        guard let workSession = windowState.workSession,
              let turn = workSession.turn(withId: turnId)
        else { return }
        var textToCopy = ""
        if turn.hasThinking {
            textToCopy += turn.thinking
        }
        if !turn.contentIsEmpty {
            if !textToCopy.isEmpty { textToCopy += "\n\n" }
            textToCopy += turn.content
        }
        guard !textToCopy.isEmpty else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(textToCopy, forType: .string)
    }

    // MARK: - Chat/Work Picker

    @ViewBuilder
    private var chatWorkPicker: some View {
        HStack(spacing: 0) {
            modeSegment(.chat, icon: "bubble.left.fill", label: "Chat")
            modeSegment(.work, icon: "hammer.fill", label: "Work")
        }
        .padding(3)
        .background {
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(theme.secondaryBackground.opacity(0.3))
        }
        .padding(.bottom, 8)
    }

    @ViewBuilder
    private func modeSegment(_ mode: ProjectSubMode, icon: String, label: String) -> some View {
        HStack(spacing: 5) {
            Image(systemName: icon)
                .font(.system(size: 10, weight: .semibold))
            Text(label)
                .font(.system(size: 11, weight: .semibold))
        }
        .fixedSize()
        .foregroundColor(session.subMode == mode ? theme.primaryText : theme.tertiaryText)
        .padding(.horizontal, 14)
        .padding(.vertical, 5)
        .background {
            if session.subMode == mode {
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .fill(theme.secondaryBackground.opacity(0.8))
                    .shadow(
                        color: theme.shadowColor.opacity(0.08), radius: 1.5, x: 0, y: 0.5)
                    .matchedGeometryEffect(id: "modePickerIndicator", in: modePickerAnimation)
            }
        }
        .contentShape(Rectangle())
        .animation(theme.springAnimation(), value: session.subMode == mode)
        .onTapGesture {
            windowState.projectSession?.subMode = mode
        }
    }

    // MARK: - Helpers

    private func projectFor(_ id: UUID) -> Project? {
        ProjectManager.shared.projects.first { $0.id == id }
    }

    private func openFilePreview(_ path: String) {
        guard let artifact = SharedArtifact.fromFilePath(path) else { return }
        previewArtifact = artifact
    }
}
