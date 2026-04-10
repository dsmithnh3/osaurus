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
        // (ProjectView only shows this when inlineWorkTaskId != nil,
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
                .modifier(InlineWorkPulseModifier())

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

// MARK: - Pulse Modifier

private struct InlineWorkPulseModifier: ViewModifier {
    @State private var isPulsing = false

    func body(content: Content) -> some View {
        content
            .scaleEffect(isPulsing ? 1.4 : 1.0)
            .opacity(isPulsing ? 0.4 : 1.0)
            .animation(
                .easeInOut(duration: 0.9).repeatForever(autoreverses: true),
                value: isPulsing
            )
            .onAppear {
                isPulsing = true
            }
    }
}

// MARK: - Work Status Button

private struct WorkStatusButton: View {
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
                .modifier(InlineWorkPulseModifier())
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

// MARK: - Clarification Overlay

private struct ClarificationOverlay: View {
    let request: ClarificationRequest
    let onSubmit: (String) -> Void

    @Environment(\.theme) private var theme
    @State private var isAppearing = false

    var body: some View {
        VStack {
            Spacer()
            ClarificationCardView(request: request, onSubmit: onSubmit)
                .opacity(isAppearing ? 1 : 0)
                .offset(y: isAppearing ? 0 : 30)
                .padding(.horizontal, 20)
                .padding(.bottom, 20)
        }
        .onAppear {
            withAnimation(theme.springAnimation()) {
                isAppearing = true
            }
        }
    }
}
