//
//  ProjectInlineWorkView.swift
//  osaurus
//
//  Work mode execution view embedded within the Projects tab.
//  Replicates WorkView's center content area without its own sidebar.
//

import SwiftUI

/// Inline work view for the Projects tab.
/// Renders the active WorkSession's task execution UI.
struct ProjectInlineWorkView: View {
    @ObservedObject var windowState: ChatWindowState
    @ObservedObject var session: WorkSession

    @State private var isPinnedToBottom: Bool = true
    @State private var scrollToBottomTrigger: Int = 0
    @State private var isProgressPanelOpen: Bool = false
    @State private var selectedArtifact: SharedArtifact?
    @State private var fileOperations: [WorkFileOperation] = []

    private var theme: ThemeProtocol { windowState.theme }

    init(windowState: ChatWindowState) {
        self.windowState = windowState
        // workSession must be non-nil when ProjectInlineWorkView is shown
        // (ProjectView only shows this when subMode == .work,
        //  which implies a workSession exists)
        self.session = windowState.workSession!
    }

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                ThemedBackgroundLayer(
                    cachedBackgroundImage: windowState.cachedBackgroundImage,
                    showSidebar: windowState.showSidebar
                )

                VStack(spacing: 0) {
                    // Toolbar clearance spacer
                    Color.clear
                        .frame(height: 52)
                        .allowsHitTesting(false)

                    if session.currentTask == nil {
                        agentEmptyState
                    } else {
                        taskExecutionView(width: proxy.size.width)
                    }

                    FloatingInputCard(
                        text: $session.input,
                        selectedModel: $session.selectedModel,
                        pendingAttachments: $session.pendingAttachments,
                        isContinuousVoiceMode: $session.isContinuousVoiceMode,
                        voiceInputState: $session.voiceInputState,
                        showVoiceOverlay: $session.showVoiceOverlay,
                        pickerItems: session.pickerItems,
                        activeModelOptions: .constant([:]),
                        isStreaming: session.isExecuting,
                        supportsImages: session.selectedModelSupportsImages,
                        estimatedContextTokens: session.estimatedContextTokens,
                        contextBreakdown: session.estimatedContextBreakdown,
                        onSend: { manualText in
                            if let manualText = manualText {
                                session.input = manualText
                            }
                            Task { await session.handleUserInput() }
                        },
                        onStop: { session.stopExecution() },
                        agentId: windowState.agentId,
                        windowId: windowState.windowId,
                        workInputState: session.inputState,
                        pendingQueuedMessage: session.pendingQueuedMessage,
                        onClearQueued: { session.clearQueuedMessage() },
                        onSendNow: {
                            Task { session.redirectExecution(message: session.input) }
                        },
                        onEndTask: { session.endTask() },
                        onResume: { Task { await session.resumeSelectedIssue() } },
                        canResume: session.canResumeSelectedIssue,
                        cumulativeTokens: session.cumulativeTokens,
                        onSkillSelected: { skillId in
                            session.pendingOneOffSkillId = skillId
                        },
                        pendingSkillId: $session.pendingOneOffSkillId
                    )
                }
            }
        }
        .sheet(item: $selectedArtifact) { artifact in
            ArtifactViewerSheet(
                artifact: artifact,
                onDismiss: { selectedArtifact = nil }
            )
            .environment(\.theme, windowState.theme)
        }
        .onChange(of: session.currentTask?.id) {
            refreshFileOperations()
        }
        .onAppear {
            refreshFileOperations()
        }
        .onReceive(NotificationCenter.default.publisher(for: .workFileOperationsDidChange)) { _ in
            refreshFileOperations()
        }
    }

    // MARK: - Empty State

    private var agentEmptyState: some View {
        WorkEmptyState(
            hasModels: !session.pickerItems.isEmpty,
            selectedModel: session.selectedModel,
            agents: windowState.agents,
            activeAgentId: windowState.agentId,
            quickActions: windowState.activeAgent.workQuickActions ?? AgentQuickAction.defaultWorkQuickActions,
            onOpenModelManager: {
                AppDelegate.shared?.showManagementWindow(initialTab: .models)
            },
            onUseFoundation: windowState.foundationModelAvailable
                ? {
                    session.selectedModel = session.pickerItems.first?.id ?? "foundation"
                } : nil,
            onQuickAction: { prompt in
                session.input = prompt
            },
            onSelectAgent: { newAgentId in
                windowState.switchAgent(to: newAgentId)
            }
        )
    }

    // MARK: - Task Execution View

    private func taskExecutionView(width: CGFloat) -> some View {
        let hasBlocks = !session.issueBlocks.isEmpty

        return ZStack(alignment: .trailing) {
            // Layer 1: Full-width chat content
            ZStack(alignment: .bottom) {
                VStack(spacing: 0) {
                    if session.selectedIssueId != nil && hasBlocks {
                        issueDetailView(width: width)
                    } else {
                        issueEmptyDetailView
                    }

                    if let error = session.errorMessage {
                        errorBanner(error: error)
                    }
                    Spacer(minLength: 0)
                }

                if session.isExecuting {
                    processingIndicator
                        .transition(.opacity.combined(with: .move(edge: .bottom)))
                }
            }
            .frame(maxWidth: .infinity)

            // Layer 2: Status button (visible when panel is closed)
            if !isProgressPanelOpen {
                WorkStatusButton(
                    isExecuting: session.isExecuting,
                    issues: session.issues,
                    artifactCount: session.sharedArtifacts.count,
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
                        issues: session.issues,
                        activeIssueId: session.activeIssue?.id,
                        selectedIssueId: session.selectedIssueId,
                        finalArtifact: session.finalArtifact,
                        sharedArtifacts: session.sharedArtifacts,
                        fileOperations: fileOperations,
                        onDismiss: { isProgressPanelOpen = false },
                        onIssueSelect: { session.selectIssue($0) },
                        onIssueRun: { issue in Task { await session.executeIssue(issue) } },
                        onIssueClose: { issueId in
                            Task { await session.closeIssue(issueId, reason: "Manually closed") }
                        },
                        onArtifactView: { selectedArtifact = $0 },
                        onArtifactOpen: { artifact in
                            let url = URL(fileURLWithPath: artifact.hostPath)
                            NSWorkspace.shared.activateFileViewerSelecting([url])
                        },
                        onUndoOperation: { operationId in undoFileOperation(operationId: operationId) },
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
    }

    // MARK: - Issue Detail View

    private func issueDetailView(width: CGFloat) -> some View {
        let blocks = session.issueBlocks
        let groupHeaderMap = session.issueBlocksGroupHeaderMap
        let agentName = windowState.cachedAgentDisplayName

        return ZStack(alignment: .bottomTrailing) {
            MessageThreadView(
                blocks: blocks,
                groupHeaderMap: groupHeaderMap,
                width: width,
                agentName: agentName,
                isStreaming: session.isExecuting && session.activeIssue?.id == session.selectedIssueId,
                lastAssistantTurnId: blocks.last?.turnId,
                autoScrollEnabled: false,
                expandedBlocksStore: session.expandedBlocksStore,
                scrollToBottomTrigger: scrollToBottomTrigger,
                onScrolledToBottom: { isPinnedToBottom = true },
                onScrolledAwayFromBottom: { isPinnedToBottom = false },
                onCopy: copyTurnContent
            )

            ScrollToBottomButton(
                isPinnedToBottom: isPinnedToBottom,
                hasTurns: !blocks.isEmpty,
                onTap: {
                    isPinnedToBottom = true
                    scrollToBottomTrigger += 1
                }
            )
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.top, 16)
        .overlay {
            if let request = session.pendingClarification {
                ClarificationOverlay(request: request) { response in
                    Task { await session.submitClarification(response) }
                }
            }
        }
        .overlay {
            if let promptState = session.pendingSecretPrompt {
                SecretPromptOverlay(state: promptState) {
                    promptState.cancel()
                    session.pendingSecretPrompt = nil
                }
            }
        }
    }

    private var issueEmptyDetailView: some View {
        VStack(spacing: 12) {
            Image(systemName: "doc.text.magnifyingglass")
                .font(.system(size: 32, weight: .regular))
                .foregroundColor(theme.tertiaryText)

            Text("No execution history", bundle: .module)
                .font(theme.font(size: CGFloat(theme.bodySize) + 1, weight: .medium))
                .foregroundColor(theme.secondaryText)

            Text("Select an issue to view its details, or run it to see live execution.", bundle: .module)
                .font(theme.font(size: CGFloat(theme.captionSize), weight: .regular))
                .foregroundColor(theme.tertiaryText)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.horizontal, 20)
    }

    // MARK: - Processing Indicator

    private var processingIndicator: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(theme.accentColor.opacity(0.6))
                .frame(width: 5, height: 5)
                .modifier(WorkPulseModifier())

            Text(session.loopState?.statusMessage ?? "Working on it...")
                .font(theme.font(size: CGFloat(theme.captionSize) - 1, weight: .regular))
                .foregroundColor(theme.tertiaryText)
                .animation(.easeInOut(duration: 0.2), value: session.loopState?.statusMessage)
        }
        .padding(.bottom, 12)
    }

    // MARK: - Error Banner

    private func errorBanner(error: String) -> some View {
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
                    .font(theme.font(size: CGFloat(theme.bodySize) + 1, weight: .semibold))
                    .foregroundColor(theme.primaryText)

                Text(error)
                    .font(theme.font(size: CGFloat(theme.captionSize), weight: .regular))
                    .foregroundColor(theme.secondaryText)
                    .lineLimit(2)
            }

            Spacer(minLength: 12)
        }
        .padding()
    }

    // MARK: - File Operations

    private func refreshFileOperations() {
        guard session.currentTask != nil else {
            fileOperations = []
            return
        }
        Task { @MainActor in
            var allOperations: [WorkFileOperation] = []
            for issue in session.issues {
                let ops = await WorkFileOperationLog.shared.operations(for: issue.id)
                allOperations.append(contentsOf: ops)
            }
            fileOperations = allOperations.sorted { $0.timestamp > $1.timestamp }
        }
    }

    private func undoFileOperation(operationId: UUID) {
        Task {
            for issue in session.issues {
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
        Task {
            for issue in session.issues {
                _ = try? await WorkFileOperationLog.shared.undoAll(issueId: issue.id)
            }
        }
    }

    private func copyTurnContent(turnId: UUID) {
        guard let turn = session.turn(withId: turnId) else { return }
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
}



