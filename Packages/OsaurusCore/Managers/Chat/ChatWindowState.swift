//
//  ChatWindowState.swift
//  osaurus
//
//  Per-window state container that isolates each ChatView window from shared singletons.
//  Pre-computes values needed for view rendering so view body is read-only.
//

import AppKit
import Combine
import Foundation
import SwiftUI

// MARK: - Close Confirmation

@MainActor
struct WorkCloseConfirmation: Identifiable {
    let id = UUID()
}

/// Controls what the main content area displays based on sidebar nav selection.
/// Orthogonal to ChatMode — ChatMode drives which engine is active,
/// SidebarContentMode drives content panel routing.
public enum SidebarContentMode: Sendable {
    case chat
    case projects
    case scheduled
}

/// Lightweight state for the active project context. Plain struct stored as
/// @Published on ChatWindowState (which is ObservableObject, not @Observable).
public struct ProjectSession: Equatable, Sendable {
    public var activeProjectId: UUID?
    public var showInspector: Bool = true

    public init(activeProjectId: UUID? = nil, showInspector: Bool = true) {
        self.activeProjectId = activeProjectId
        self.showInspector = showInspector
    }
}

/// Entry in the navigation stack for back/forward support.
public struct NavigationEntry: Equatable, Sendable {
    public let mode: ChatMode
    public let projectId: UUID?
    public let sessionId: UUID?

    public init(mode: ChatMode, projectId: UUID? = nil, sessionId: UUID? = nil) {
        self.mode = mode
        self.projectId = projectId
        self.sessionId = sessionId
    }
}

/// Per-window state container for ChatView - each window creates its own instance
@MainActor
final class ChatWindowState: ObservableObject {
    // MARK: - Identity & Session

    let windowId: UUID
    let session: ChatSession
    let foundationModelAvailable: Bool

    // MARK: - Mode State

    @Published var mode: ChatMode = .chat
    @Published var showSidebar: Bool = false

    /// When non-nil, ChatView should present a close confirmation for active work execution.
    @Published var workCloseConfirmation: WorkCloseConfirmation?

    // MARK: - Work State

    @Published var workSession: WorkSession?
    @Published private(set) var workTasks: [WorkTask] = []

    // MARK: - Agent State

    @Published var agentId: UUID
    @Published private(set) var agents: [Agent] = []
    @Published private(set) var discoveredAgents: [DiscoveredAgent] = []
    @Published var selectedDiscoveredAgent: DiscoveredAgent?
    @Published var selectedDiscoveredAgentProviderId: UUID?

    // MARK: - Theme State

    @Published private(set) var theme: ThemeProtocol
    @Published private(set) var cachedBackgroundImage: NSImage?

    // MARK: - Project State

    @Published var projectSession: ProjectSession?
    @Published var sidebarContentMode: SidebarContentMode = .chat
    @Published var showProjectInspector: Bool = true

    // MARK: - Navigation Stack

    @Published private(set) var navigationStack: [NavigationEntry] = []
    @Published private(set) var navigationIndex: Int = -1

    var canGoBack: Bool { navigationIndex > 0 }
    var canGoForward: Bool { navigationIndex < navigationStack.count - 1 }

    func pushNavigation(_ entry: NavigationEntry) {
        // Truncate forward history
        if navigationIndex < navigationStack.count - 1 {
            navigationStack = Array(navigationStack.prefix(navigationIndex + 1))
        }
        navigationStack.append(entry)
        navigationIndex = navigationStack.count - 1
    }

    func goBack() {
        guard canGoBack else { return }
        navigationIndex -= 1
        let entry = navigationStack[navigationIndex]
        restoreNavigationEntry(entry)
    }

    func goForward() {
        guard canGoForward else { return }
        navigationIndex += 1
        let entry = navigationStack[navigationIndex]
        restoreNavigationEntry(entry)
    }

    private func restoreNavigationEntry(_ entry: NavigationEntry) {
        switchMode(to: entry.mode)
        if let projectId = entry.projectId {
            projectSession = ProjectSession(activeProjectId: projectId)
            ProjectManager.shared.setActiveProject(projectId)
        }
    }

    // MARK: - Pre-computed View Values

    @Published private(set) var filteredSessions: [ChatSessionData] = []
    @Published private(set) var cachedSystemPrompt: String = ""
    @Published private(set) var cachedActiveAgent: Agent = .default
    @Published private(set) var cachedAgentDisplayName: String = "Assistant"

    // MARK: - Private

    private nonisolated(unsafe) var notificationObservers: [NSObjectProtocol] = []
    private var sessionRefreshWorkItem: DispatchWorkItem?
    private var bonjourCancellable: AnyCancellable?

    // MARK: - Initialization

    init(windowId: UUID, agentId: UUID, sessionData: ChatSessionData? = nil) {
        self.windowId = windowId
        self.agentId = agentId
        self.session = ChatSession()
        self.foundationModelAvailable = AppConfiguration.shared.foundationModelAvailable
        self.theme = Self.loadTheme(for: agentId)

        // Load initial data
        self.agents = AgentManager.shared.agents
        self.filteredSessions = ChatSessionsManager.shared.sessions(for: agentId)

        // Pre-compute view values
        self.cachedSystemPrompt = AgentManager.shared.effectiveSystemPrompt(for: agentId)
        self.cachedActiveAgent = agents.first { $0.id == agentId } ?? .default
        self.cachedAgentDisplayName = cachedActiveAgent.isBuiltIn ? "Assistant" : cachedActiveAgent.name
        decodeBackgroundImageAsync(themeConfig: theme.customThemeConfig)

        // Configure session
        self.session.agentId = agentId
        self.session.applyInitialModelSelection()
        if let data = sessionData {
            self.session.load(from: data)
        }
        self.session.onSessionChanged = { [weak self] in
            self?.refreshSessionsDebounced()
        }

        setupNotificationObservers()
        observeBonjourBrowser()
    }

    /// Wrap an existing `ExecutionContext`, reusing its sessions without duplication.
    /// Used for lazy window creation when a user clicks "View" on a toast.
    init(windowId: UUID, executionContext context: ExecutionContext) {
        self.windowId = windowId
        self.agentId = context.agentId
        self.session = context.chatSession
        self.foundationModelAvailable = AppConfiguration.shared.foundationModelAvailable
        self.theme = Self.loadTheme(for: context.agentId)

        self.agents = AgentManager.shared.agents
        self.filteredSessions = ChatSessionsManager.shared.sessions(for: context.agentId)
        self.cachedSystemPrompt = AgentManager.shared.effectiveSystemPrompt(for: context.agentId)
        self.cachedActiveAgent = agents.first { $0.id == context.agentId } ?? .default
        self.cachedAgentDisplayName = cachedActiveAgent.isBuiltIn ? "Assistant" : cachedActiveAgent.name
        decodeBackgroundImageAsync(themeConfig: theme.customThemeConfig)

        self.session.onSessionChanged = { [weak self] in
            self?.refreshSessionsDebounced()
        }

        if let workSession = context.workSession {
            self.mode = .work
            self.workSession = workSession
            workSession.windowState = self
            refreshWorkTasks()
        }

        setupNotificationObservers()
        observeBonjourBrowser()
    }

    deinit {
        print("[ChatWindowState] deinit – windowId: \(windowId)")
        notificationObservers.forEach { NotificationCenter.default.removeObserver($0) }
    }

    /// Stops any running execution and breaks reference chains — call when window is closing.
    func cleanup() {
        removeEphemeralProviderIfNeeded()
        selectedDiscoveredAgent = nil
        selectedDiscoveredAgentProviderId = nil
        workSession?.cancelExecution()
        session.stop()
        workSession = nil
        session.onSessionChanged = nil
    }

    // MARK: - API

    var activeAgent: Agent { cachedActiveAgent }

    var themeId: UUID? {
        AgentManager.shared.themeId(for: agentId)
    }

    func switchAgent(to newAgentId: UUID) {
        if !session.turns.isEmpty { session.save() }
        agentId = newAgentId
        removeEphemeralProviderIfNeeded()
        selectedDiscoveredAgent = nil
        selectedDiscoveredAgentProviderId = nil
        session.reset(for: newAgentId)
        refreshTheme()
        refreshSessions()
        refreshAgentConfig()
        AgentManager.shared.setActiveAgent(newAgentId)
    }

    func startNewChat() {
        if !session.turns.isEmpty { session.save() }
        flushCurrentSession()
        session.reset(for: agentId)
        refreshSessions()
    }

    // MARK: - Mode Switching

    func switchMode(to newMode: ChatMode) {
        guard newMode != mode else { return }

        // Save current chat if switching away from chat mode
        if mode == .chat && !session.turns.isEmpty {
            session.save()
        }

        mode = newMode
        sidebarContentMode = .chat  // Reset sidebar content on mode change

        switch newMode {
        case .work:
            WorkToolManager.shared.registerTools()
            if workSession == nil {
                workSession = WorkSession(agentId: agentId, windowState: self)
            }
            refreshWorkTasks()
        case .project:
            WorkToolManager.shared.unregisterTools()
            if projectSession == nil {
                projectSession = ProjectSession()
            }
        case .chat:
            WorkToolManager.shared.unregisterTools()
        }
    }

    func refreshWorkTasks() {
        guard WorkDatabase.shared.isOpen else {
            workTasks = []
            return
        }
        do {
            workTasks = try IssueStore.listTasks(agentId: agentId)
        } catch {
            print("[ChatWindowState] Failed to refresh work tasks: \(error)")
            workTasks = []
        }
    }

    func loadSession(_ sessionData: ChatSessionData) {
        guard sessionData.id != session.sessionId else { return }
        if !session.turns.isEmpty { session.save() }
        flushCurrentSession()

        if let freshData = ChatSessionStore.load(id: sessionData.id) {
            session.load(from: freshData)
        } else {
            session.load(from: sessionData)
        }

        // Update theme if session has different agent
        let sessionAgentId = sessionData.agentId ?? Agent.defaultId
        if sessionAgentId != agentId {
            theme = Self.loadTheme(for: sessionAgentId)
            decodeBackgroundImageAsync(themeConfig: theme.customThemeConfig)
        }
    }

    private func flushCurrentSession() {
        guard let sid = session.sessionId else { return }
        let agentStr = (session.agentId ?? Agent.defaultId).uuidString
        let convStr = sid.uuidString
        Task {
            await MemoryService.shared.flushSession(agentId: agentStr, conversationId: convStr)
        }
    }

    // MARK: - Refresh Methods

    func refreshAgents() {
        agents = AgentManager.shared.agents
        cachedActiveAgent = agents.first { $0.id == agentId } ?? .default
        cachedAgentDisplayName = cachedActiveAgent.isBuiltIn ? "Assistant" : cachedActiveAgent.name
    }

    func refreshSessions() {
        filteredSessions = ChatSessionsManager.shared.sessions(for: agentId)
    }

    /// Coalesces rapid `refreshSessions()` calls (e.g. during streaming saves).
    func refreshSessionsDebounced() {
        sessionRefreshWorkItem?.cancel()
        let workItem = DispatchWorkItem { [weak self] in
            Task { @MainActor in
                self?.refreshSessions()
            }
        }
        sessionRefreshWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3, execute: workItem)
    }

    func refreshTheme() {
        let newTheme = Self.loadTheme(for: agentId)
        let oldConfig = theme.customThemeConfig
        let newConfig = newTheme.customThemeConfig
        // Skip only if the full config is identical (not just the ID)
        guard oldConfig != newConfig else { return }

        theme = newTheme

        // Only re-decode background image when the theme itself changes (different ID)
        if oldConfig?.metadata.id != newConfig?.metadata.id {
            decodeBackgroundImageAsync(themeConfig: theme.customThemeConfig)
        }
    }

    func refreshAgentConfig() {
        cachedSystemPrompt = AgentManager.shared.effectiveSystemPrompt(for: agentId)
        cachedActiveAgent = agents.first { $0.id == agentId } ?? .default
        cachedAgentDisplayName = cachedActiveAgent.isBuiltIn ? "Assistant" : cachedActiveAgent.name
        session.invalidateTokenCache()
    }

    func refreshAll() async {
        refreshAgents()
        refreshSessions()
        refreshTheme()
        refreshAgentConfig()
        await session.refreshPickerItems()
    }

    // MARK: - Private

    private func observeBonjourBrowser() {
        bonjourCancellable = BonjourBrowser.shared.$discoveredAgents
            .receive(on: RunLoop.main)
            .sink { [weak self] agents in
                self?.discoveredAgents = agents
                if let selected = self?.selectedDiscoveredAgent,
                    !agents.contains(where: { $0.id == selected.id })
                {
                    self?.removeEphemeralProviderIfNeeded()
                    self?.selectedDiscoveredAgent = nil
                    self?.selectedDiscoveredAgentProviderId = nil
                }
            }
    }

    private func removeEphemeralProviderIfNeeded() {
        guard let providerId = selectedDiscoveredAgentProviderId,
            RemoteProviderManager.shared.isEphemeral(id: providerId)
        else { return }
        RemoteProviderManager.shared.removeProvider(id: providerId)
    }

    private static func loadTheme(for agentId: UUID) -> ThemeProtocol {
        if let themeId = AgentManager.shared.themeId(for: agentId),
            let custom = ThemeManager.shared.installedThemes.first(where: { $0.metadata.id == themeId })
        {
            return CustomizableTheme(config: custom)
        }
        return ThemeManager.shared.currentTheme
    }

    private func decodeBackgroundImageAsync(themeConfig: CustomTheme?) {
        Task { [weak self] in
            let decoded = themeConfig?.background.decodedImage()
            self?.cachedBackgroundImage = decoded
        }
    }

    private func setupNotificationObservers() {
        notificationObservers.append(
            NotificationCenter.default.addObserver(
                forName: .activeAgentChanged,
                object: nil,
                queue: .main
            ) { [weak self] _ in Task { @MainActor in self?.refreshAgents() } }
        )
        // Note: .chatOverlayActivated intentionally not observed here
        // State is loaded in init(), refreshAll() would cause excessive re-renders
        notificationObservers.append(
            NotificationCenter.default.addObserver(
                forName: .appConfigurationChanged,
                object: nil,
                queue: .main
            ) { [weak self] _ in Task { @MainActor in self?.refreshAgentConfig() } }
        )
        // Refresh theme when global theme changes (only if agent uses global theme)
        notificationObservers.append(
            NotificationCenter.default.addObserver(
                forName: .globalThemeChanged,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                Task { @MainActor in
                    if self?.themeId == nil { self?.refreshTheme() }
                }
            }
        )
        // Refresh theme and config (system prompt, token cache) when current agent is updated
        notificationObservers.append(
            NotificationCenter.default.addObserver(
                forName: .agentUpdated,
                object: nil,
                queue: .main
            ) { [weak self] notification in
                let updatedId = notification.object as? UUID
                Task { @MainActor in
                    if let self, updatedId == self.agentId {
                        self.refreshTheme()
                        self.refreshAgentConfig()
                    }
                }
            }
        )
    }
}
