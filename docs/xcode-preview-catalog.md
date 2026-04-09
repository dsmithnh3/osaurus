# Xcode Preview Catalog

This document catalogs all SwiftUI views in OsaurusCore that support Xcode Previews, organized by feature area. It identifies which preview mechanism each view uses (#Preview macro or PreviewProvider struct) and notes the purpose and key dependencies of each view.

## Table of Contents

- [Overview](#overview)
- [Chat Views](#chat-views)
- [Agent Views](#agent-views)
- [Common Components](#common-components)
- [Management Views](#management-views)
- [Model Views](#model-views)
- [Onboarding Views](#onboarding-views)
- [Plugin Views](#plugin-views)
- [Settings Views](#settings-views)
- [Skill Views](#skill-views)
- [Voice Views](#voice-views)
- [Toast Views](#toast-views)
- [Work Views](#work-views)
- [Schedule Views](#schedule-views)
- [Sandbox Views](#sandbox-views)
- [Watcher Views](#watcher-views)
- [Insights Views](#insights-views)
- [Summary Statistics](#summary-statistics)

---

## Overview

Osaurus is transitioning from the legacy `PreviewProvider` protocol to the modern `#Preview` macro introduced in Swift 5.9+. This catalog tracks the current state of all preview implementations across the codebase.

**Preview Types:**
- **#Preview** - Modern macro-based previews (Swift 5.9+, recommended)
- **PreviewProvider** - Legacy protocol-based previews (still functional, but verbose)

**Total Views with Previews:** 60
**Using #Preview:** 26
**Using PreviewProvider:** 34

---

## Chat Views

### ChatEmptyState.swift
- **Path:** `Packages/OsaurusCore/Views/Chat/ChatEmptyState.swift`
- **Preview Type:** `PreviewProvider`
- **Purpose:** Immersive empty state with prominent agent selector and staggered entrance animations for a polished first impression. Shows different states based on model availability.
- **Key Dependencies:**
  - AnimatedOrb (for hero orb)
  - AgentPill (for agent selection)
  - ModelManager (for download state)
  - AgentQuickAction (for quick action buttons)
- **Preview Scenarios:**
  - With models available (ready state with quick actions)
  - Without models (setup needed state)
- **Notes:** Uses state-driven animation with `hasAppeared` flag for staggered element entrance.

### ChatSessionSidebar.swift
- **Path:** `Packages/OsaurusCore/Views/Chat/ChatSessionSidebar.swift`
- **Preview Type:** `PreviewProvider`
- **Purpose:** Sidebar showing chat session history with search, rename, and delete capabilities.
- **Key Dependencies:**
  - ChatSessionData model
  - AgentManager for per-agent display
  - SearchService for query matching
  - SidebarContainer layout component
- **Preview Scenarios:** Empty state with no sessions
- **Notes:** Supports inline editing, contextual actions, and optional "Open in New Window" callback.

### ClarificationCardView.swift
- **Path:** `Packages/OsaurusCore/Views/Chat/ClarificationCardView.swift`
- **Preview Type:** `PreviewProvider`
- **Purpose:** Floating overlay for clarification questions, styled after VoiceInputOverlay. Appears anchored to the bottom of the chat area.
- **Key Dependencies:**
  - ClarificationRequest model (question, options, context)
- **Preview Scenarios:** Sample clarification with 4 deployment options
- **Notes:** Supports both predefined options (radio buttons) and custom text input.

### FloatingInputCard.swift
- **Path:** `Packages/OsaurusCore/Views/Chat/FloatingInputCard.swift`
- **Preview Type:** `PreviewProvider`
- **Purpose:** Premium floating input card with model chip, smooth animations, and document attachment support.
- **Key Dependencies:**
  - EditableTextView for multi-line input
  - DocumentChip for attachments
  - Agent and model data
- **Preview Scenarios:**
  - Empty input
  - With text + attachments
- **Notes:** Handles keyboard shortcuts, drag-and-drop, clipboard images, and send actions.

### MarkdownImageView.swift
- **Path:** `Packages/OsaurusCore/Views/Chat/MarkdownImageView.swift`
- **Preview Type:** `PreviewProvider`
- **Purpose:** Renders images from URLs (data URIs, file paths, or remote URLs) with loading states, error handling, and full-screen viewer.
- **Key Dependencies:**
  - ThreadCache for image caching
  - ImageFullScreenView for expansion
  - NSImage loading (base64, local, remote)
- **Preview Scenarios:**
  - Remote image (placekitten)
  - Invalid URL (error state)
- **Notes:** Auto-sizes to baseWidth, supports save/copy actions, hover toolbar.

### MarkdownMessageView.swift
- **Path:** `Packages/OsaurusCore/Views/Chat/MarkdownMessageView.swift`
- **Preview Type:** `PreviewProvider`
- **Purpose:** Renders markdown text with proper typography, code blocks, images, tables, math, and more. Optimized for streaming responses with stable block identity.
- **Key Dependencies:**
  - SelectableTextView for text groups
  - CodeBlockView for fenced code
  - MarkdownImageView for images
  - MathBlockView for LaTeX
  - ThreadCache for parsed content
- **Preview Scenarios:** Comprehensive markdown sample (headers, lists, code, tables, images, blockquotes, horizontal rules)
- **Notes:** Background parsing with debouncing, segment-based rendering for efficient updates during streaming.

---

## Agent Views

### AgentsView.swift
- **Path:** `Packages/OsaurusCore/Views/Agent/AgentsView.swift`
- **Preview Type:** `#Preview`
- **Purpose:** Main interface for creating, editing, and managing AI agents with their configurations, tools, and skills.
- **Key Dependencies:**
  - AgentManager
  - ToolRegistry
  - SkillSearchService
  - AgentKey for cryptographic identity
- **Notes:** Uses `#Preview` macro (modern syntax).

---

## Common Components

### AnimatedOrb.swift
- **Path:** `Packages/OsaurusCore/Views/Common/AnimatedOrb.swift`
- **Preview Type:** `PreviewProvider`
- **Purpose:** Mesmerizing animated orb with liquid-like motion, particles, and glow effects. Uses a Metal shader (`OrbShader.metal`) for GPU-accelerated rendering.
- **Key Dependencies:**
  - ShaderLibrary.orbEffect (Metal shader)
  - TimelineView for 15fps animation
- **Preview Scenarios:** Multiple sizes (tiny, small, medium, large) and variations with/without glow/float
- **Notes:** Size presets: `.tiny` (24pt), `.small` (40pt), `.medium` (64pt), `.large` (96pt). Seed string creates deterministic but unique animations per agent.

### AnimatedProgressComponents.swift
- **Path:** `Packages/OsaurusCore/Views/Common/AnimatedProgressComponents.swift`
- **Preview Type:** `PreviewProvider`
- **Purpose:** Collection of animated progress components for background tasks: shimmer progress bars, typing indicators, pulsing status dots, and morphing status icons.
- **Key Components:**
  - `ShimmerProgressBar` - Progress with gradient shimmer and glow
  - `IndeterminateShimmerProgress` - Loading indicator
  - `ConfigurableTypingIndicator` - Three-dot bounce animation
  - `PulsingStatusDot` - Status with pulsing ring
  - `MorphingStatusIcon` - Morphs between pending/active/completed/failed states
  - `AnimatedStepCounter` - Smooth numeric transitions
- **Preview Scenarios:** All components with different states
- **Notes:** Self-contained animations, no external dependencies beyond theme.

### AnimatedTabSelector.swift
- **Path:** `Packages/OsaurusCore/Views/Common/AnimatedTabSelector.swift`
- **Preview Type:** `#Preview`
- **Purpose:** Modern animated tab selector with sliding indicator using matchedGeometryEffect. Used for sub-navigation within Models, Tools, Plugins, and Sandbox views.
- **Key Dependencies:**
  - AnimatedTabItem protocol
  - Tab enums: ModelListTab, ToolsTab, PluginsTab, SandboxTab
- **Preview Scenarios:** Multiple tab selectors with counts and badges
- **Notes:** Generic over `AnimatedTabItem` conforming types.

### GlassListRow.swift
- **Path:** `Packages/OsaurusCore/Views/Common/GlassListRow.swift`
- **Preview Type:** `#Preview`
- **Purpose:** Card-based list row with enhanced shadows and hover effects.
- **Key Dependencies:** Theme system
- **Notes:** Generic container for list content with glass styling.

### NotchView.swift
- **Path:** `Packages/OsaurusCore/Views/Common/NotchView.swift`
- **Preview Type:** `PreviewProvider`
- **Purpose:** Dynamic Island-inspired notch UI for background tasks. Cup-shaped overlay that blends with the display bezel and expands on hover with bouncy swing animation and staggered content reveal.
- **Key Dependencies:**
  - BackgroundTask model
  - NotchShape (custom Shape)
- **Preview Scenarios:** Active task with progress, expanded state
- **Notes:** Detects hardware notch dimensions, uses custom cup shape to blend with MacBook display.

### SectionHeader.swift
- **Path:** `Packages/OsaurusCore/Views/Common/SectionHeader.swift`
- **Preview Type:** `#Preview`
- **Purpose:** Consistent section header component used throughout settings and management views.
- **Key Dependencies:** Theme typography
- **Notes:** Simple text label with standardized styling.

### ThemedAlertDialog.swift
- **Path:** `Packages/OsaurusCore/Views/Common/ThemedAlertDialog.swift`
- **Preview Type:** `PreviewProvider`
- **Purpose:** Custom alert dialog with theme-aware styling, supporting single-button, two-button, and three-button layouts.
- **Key Dependencies:** Theme system
- **Preview Scenarios:** Various button configurations
- **Notes:** Respects theme glass effects and color schemes.

---

## Management Views

### ManagementView.swift
- **Path:** `Packages/OsaurusCore/Views/Management/ManagementView.swift`
- **Preview Type:** `#Preview`
- **Purpose:** Main settings and management interface with sidebar navigation.
- **Key Dependencies:**
  - SidebarNavigation
  - All manager sub-views (Models, Tools, Agents, Skills, Plugins, etc.)
- **Notes:** Central hub for all configuration screens.

### ManagerHeader.swift
- **Path:** `Packages/OsaurusCore/Views/Management/ManagerHeader.swift`
- **Preview Type:** `#Preview`
- **Purpose:** Consistent header component for manager views with icon, title, subtitle, and optional action buttons.
- **Key Dependencies:** Theme system
- **Preview Scenarios:** Multiple header variations
- **Notes:** Reusable across all management screens.

### SidebarNavigation.swift
- **Path:** `Packages/OsaurusCore/Views/Management/SidebarNavigation.swift`
- **Preview Type:** `#Preview`
- **Purpose:** Navigation sidebar for management views with icons and labels.
- **Key Dependencies:** ManagementTab enum
- **Notes:** Handles tab selection and visual highlighting.

### AcknowledgementsView.swift
- **Path:** `Packages/OsaurusCore/Views/Management/AcknowledgementsView.swift`
- **Preview Type:** `#Preview`
- **Purpose:** Displays open source licenses and acknowledgements for dependencies.
- **Key Dependencies:** License data models
- **Notes:** Auto-generated from package dependencies.

---

## Model Views

### ModelPickerView.swift
- **Path:** `Packages/OsaurusCore/Views/Model/ModelPickerView.swift`
- **Preview Type:** `PreviewProvider`
- **Purpose:** Picker interface for selecting AI models with filtering, search, and download capabilities.
- **Key Dependencies:**
  - ModelManager
  - ProviderCapability
  - ModelDefinition
- **Preview Scenarios:** Grid and list layouts with various model states
- **Notes:** Supports both local MLX models and remote providers.

### ModelDownloadView.swift
- **Path:** `Packages/OsaurusCore/Views/Model/ModelDownloadView.swift`
- **Preview Type:** `#Preview`
- **Purpose:** Interface for browsing, filtering, and downloading MLX models from the Hugging Face registry.
- **Key Dependencies:**
  - ModelManager
  - MLX model metadata
- **Notes:** Three-tab interface: All models, Suggested models, Downloaded models.

---

## Onboarding Views

All onboarding views use **PreviewProvider** and are part of the initial setup flow.

### OnboardingView.swift
- **Path:** `Packages/OsaurusCore/Views/Onboarding/OnboardingView.swift`
- **Preview Type:** `PreviewProvider`
- **Purpose:** Main onboarding flow coordinator, managing step progression.
- **Key Dependencies:** All onboarding step views
- **Notes:** Tab-view based multi-step wizard.

### OnboardingWelcomeView.swift
- **Path:** `Packages/OsaurusCore/Views/Onboarding/OnboardingWelcomeView.swift`
- **Preview Type:** `PreviewProvider`
- **Purpose:** Welcome screen with app introduction.
- **Notes:** First step in onboarding.

### OnboardingChoosePathView.swift
- **Path:** `Packages/OsaurusCore/Views/Onboarding/OnboardingChoosePathView.swift`
- **Preview Type:** `PreviewProvider`
- **Purpose:** Choice between local MLX models or remote cloud providers.
- **Notes:** Branching step that determines subsequent flow.

### OnboardingLocalDownloadView.swift
- **Path:** `Packages/OsaurusCore/Views/Onboarding/OnboardingLocalDownloadView.swift`
- **Preview Type:** `PreviewProvider`
- **Purpose:** Model selection and download for local path.
- **Key Dependencies:** ModelManager, MLX model registry
- **Notes:** Shows suggested models for Apple Silicon.

### OnboardingAPISetupView.swift
- **Path:** `Packages/OsaurusCore/Views/Onboarding/OnboardingAPISetupView.swift`
- **Preview Type:** `PreviewProvider`
- **Purpose:** API key configuration for remote providers.
- **Key Dependencies:** RemoteProviderManager
- **Notes:** Secure field for API key entry.

### OnboardingIdentitySetupView.swift
- **Path:** `Packages/OsaurusCore/Views/Onboarding/OnboardingIdentitySetupView.swift`
- **Preview Type:** `PreviewProvider`
- **Purpose:** Master key setup with biometric authentication.
- **Key Dependencies:** MasterKey, DeviceKey
- **Notes:** Critical security step with keychain integration.

### OnboardingWalkthroughView.swift
- **Path:** `Packages/OsaurusCore/Views/Onboarding/OnboardingWalkthroughView.swift`
- **Preview Type:** `PreviewProvider`
- **Purpose:** Feature walkthrough highlighting key capabilities.
- **Notes:** Educational step before completion.

### OnboardingCompleteView.swift
- **Path:** `Packages/OsaurusCore/Views/Onboarding/OnboardingCompleteView.swift`
- **Preview Type:** `PreviewProvider`
- **Purpose:** Completion screen with success message.
- **Notes:** Final step, allows proceeding to main app.

---

## Plugin Views

### PluginsView.swift
- **Path:** `Packages/OsaurusCore/Views/Plugin/PluginsView.swift`
- **Preview Type:** `#Preview`
- **Purpose:** Plugin management interface for browsing, installing, and configuring native dylib plugins.
- **Key Dependencies:**
  - PluginManager
  - PluginRepositoryService
  - ExternalPlugin model
- **Notes:** Two-tab interface: Installed plugins, Browse repository.

### ToolsManagerView.swift
- **Path:** `Packages/OsaurusCore/Views/Plugin/ToolsManagerView.swift`
- **Preview Type:** `#Preview`
- **Purpose:** Central tool management showing all available tools from built-in, plugin, MCP, and sandbox sources.
- **Key Dependencies:**
  - ToolRegistry
  - Tool permission system
  - ToolSourceType enum
- **Notes:** Three-tab interface: Available, Remote (MCP), Sandbox.

### ToolPermissionView.swift
- **Path:** `Packages/OsaurusCore/Views/Plugin/ToolPermissionView.swift`
- **Preview Type:** `#Preview` (with multiple named previews)
- **Purpose:** Interface for configuring tool execution permissions (ask/auto/deny policy).
- **Key Dependencies:**
  - ToolPermissionManager
  - Tool schema
- **Preview Scenarios:**
  - Dark mode
  - Light mode
  - Tool with no arguments
- **Notes:** Shows tool description, arguments schema, and policy selector.

### ToolSecretsSheet.swift
- **Path:** `Packages/OsaurusCore/Views/Plugin/ToolSecretsSheet.swift`
- **Preview Type:** `#Preview`
- **Purpose:** Secure sheet for managing tool-specific secrets (API keys, tokens).
- **Key Dependencies:**
  - SecretManager
  - Tool secret schema
- **Notes:** Uses SecureField, per-agent secret scoping.

---

## Settings Views

All settings views use **#Preview**.

### ServerView.swift
- **Path:** `Packages/OsaurusCore/Views/Settings/ServerView.swift`
- **Preview Type:** `#Preview`
- **Purpose:** Server configuration for HTTP API, MCP server, and relay tunnel.
- **Key Dependencies:**
  - OsaurusServer
  - MCPServerManager
  - RelayTunnelManager
- **Notes:** Manages ports, auth, and public accessibility.

### ProvidersView.swift
- **Path:** `Packages/OsaurusCore/Views/Settings/ProvidersView.swift`
- **Preview Type:** `#Preview`
- **Purpose:** Configuration for AI model providers (local MLX, remote APIs).
- **Key Dependencies:**
  - RemoteProviderManager
  - ModelManager
  - ProviderType enum
- **Notes:** Shows configured providers and their models.

### RemoteProvidersView.swift
- **Path:** `Packages/OsaurusCore/Views/Settings/RemoteProvidersView.swift`
- **Preview Type:** `#Preview`
- **Purpose:** Management of remote provider connections (OpenAI, Anthropic, etc.).
- **Key Dependencies:**
  - RemoteProviderManager
  - RemoteProvider model
- **Notes:** List of providers with add/edit/delete.

### RemoteProviderEditSheet.swift
- **Path:** `Packages/OsaurusCore/Views/Settings/RemoteProviderEditSheet.swift`
- **Preview Type:** `#Preview`
- **Purpose:** Sheet for adding or editing remote provider configuration.
- **Key Dependencies:**
  - ProviderType
  - API key management
- **Notes:** Form with name, base URL, API key, and model discovery.

### PermissionsView.swift
- **Path:** `Packages/OsaurusCore/Views/Settings/PermissionsView.swift`
- **Preview Type:** `#Preview`
- **Purpose:** System permission management for file access, camera, microphone, etc.
- **Key Dependencies:**
  - PermissionManager
  - macOS permission APIs
- **Notes:** Shows permission status and request buttons.

### DirectoryPickerView.swift
- **Path:** `Packages/OsaurusCore/Views/Settings/DirectoryPickerView.swift`
- **Preview Type:** `#Preview`
- **Purpose:** Reusable directory picker with security-scoped bookmark support.
- **Key Dependencies:**
  - NSOpenPanel
  - Bookmark persistence
- **Notes:** Used throughout app for folder selection.

### StatusPanelView.swift
- **Path:** `Packages/OsaurusCore/Views/Settings/StatusPanelView.swift`
- **Preview Type:** `#Preview`
- **Purpose:** System status panel showing app version, diagnostics, and health checks.
- **Key Dependencies:**
  - App metadata
  - System info
- **Notes:** Debugging and support tool.

---

## Skill Views

### SkillsView.swift
- **Path:** `Packages/OsaurusCore/Views/Skill/SkillsView.swift`
- **Preview Type:** `#Preview`
- **Purpose:** Management interface for agent skills (markdown-based instruction documents).
- **Key Dependencies:**
  - SkillSearchService
  - SkillStore
  - Skill model
- **Notes:** List of skills with create/edit/delete, GitHub import.

### SkillEditorSheet.swift
- **Path:** `Packages/OsaurusCore/Views/Skill/SkillEditorSheet.swift`
- **Preview Type:** `#Preview`
- **Purpose:** Editor for creating or modifying skill documents (SKILL.md).
- **Key Dependencies:**
  - Skill model
  - Markdown editing
- **Notes:** Text editor with metadata fields (name, description, triggers).

### GitHubImportSheet.swift
- **Path:** `Packages/OsaurusCore/Views/Skill/GitHubImportSheet.swift`
- **Preview Type:** `#Preview`
- **Purpose:** Import skills from Agent Skills repository on GitHub.
- **Key Dependencies:**
  - GitHub API integration
  - Skill repository format
- **Notes:** Browse and import community skills.

---

## Voice Views

All voice views use **PreviewProvider**.

### VoiceView.swift
- **Path:** `Packages/OsaurusCore/Views/Voice/VoiceView.swift`
- **Preview Type:** `#Preview`
- **Purpose:** Main voice configuration interface with tabbed settings.
- **Key Dependencies:** All voice settings tab views
- **Notes:** Container for voice setup and configuration tabs.

### VoiceSetupTab.swift
- **Path:** `Packages/OsaurusCore/Views/Voice/VoiceSetupTab.swift`
- **Preview Type:** `PreviewProvider`
- **Purpose:** Initial setup and model download for FluidAudio (Parakeet TDT).
- **Key Dependencies:**
  - SpeechService
  - FluidAudio model manager
- **Notes:** One-time setup, downloads CoreML model.

### AudioSettingsTab.swift
- **Path:** `Packages/OsaurusCore/Views/Voice/AudioSettingsTab.swift`
- **Preview Type:** `PreviewProvider`
- **Purpose:** Audio device selection (microphone, system audio).
- **Key Dependencies:**
  - AVCaptureDevice
  - SpeechService
- **Notes:** Lists available audio input sources.

### VoiceInputSettingsTab.swift
- **Path:** `Packages/OsaurusCore/Views/Voice/VoiceInputSettingsTab.swift`
- **Preview Type:** `PreviewProvider`
- **Purpose:** Configuration for voice input mode selection.
- **Key Dependencies:** Voice mode enum
- **Notes:** Choose between VAD mode and transcription mode.

### VADModeSettingsTab.swift
- **Path:** `Packages/OsaurusCore/Views/Voice/VADModeSettingsTab.swift`
- **Preview Type:** `PreviewProvider`
- **Purpose:** Voice Activity Detection settings (always-on listening with wake word).
- **Key Dependencies:**
  - VADService
  - Sensitivity settings
- **Notes:** Configures thresholds, cooldown, accumulation windows.

### TranscriptionModeSettingsTab.swift
- **Path:** `Packages/OsaurusCore/Views/Voice/TranscriptionModeSettingsTab.swift`
- **Preview Type:** `PreviewProvider`
- **Purpose:** Transcription mode settings (hotkey-triggered dictation).
- **Key Dependencies:**
  - TranscriptionModeService
  - HotkeyRecorder
- **Notes:** Configures global hotkey, output method (typing vs clipboard).

### VoiceInputOverlay.swift
- **Path:** `Packages/OsaurusCore/Views/Voice/VoiceInputOverlay.swift`
- **Preview Type:** `PreviewProvider`
- **Purpose:** Floating overlay showing live transcription during voice input.
- **Key Dependencies:**
  - SpeechService
  - Transcription state
- **Preview Scenarios:** Active listening state
- **Notes:** Animated waveform, text preview, cancel button.

### TranscriptionOverlayView.swift
- **Path:** `Packages/OsaurusCore/Views/Voice/TranscriptionOverlayView.swift`
- **Preview Type:** `PreviewProvider`
- **Purpose:** Compact overlay for transcription mode showing interim results.
- **Key Dependencies:** Transcription text stream
- **Notes:** Positioned near text cursor in transcription mode.

### VoiceComponents.swift
- **Path:** `Packages/OsaurusCore/Views/Voice/VoiceComponents.swift`
- **Preview Type:** `PreviewProvider`
- **Purpose:** Reusable voice UI components (waveform, mic button, status indicators).
- **Key Components:**
  - Waveform visualization
  - Mic button with states
  - Recording status pill
- **Preview Scenarios:** Various component states
- **Notes:** Shared by voice overlays and settings.

---

## Toast Views

All toast views use **PreviewProvider**.

### ToastView.swift
- **Path:** `Packages/OsaurusCore/Views/Toast/ToastView.swift`
- **Preview Type:** `PreviewProvider`
- **Purpose:** Generic toast notification component with icon, message, and optional action.
- **Key Dependencies:**
  - ToastData model
  - ToastLevel enum (info, success, warning, error)
- **Preview Scenarios:** Different toast levels and content
- **Notes:** Auto-dismiss with configurable duration.

### ThemedToastView.swift
- **Path:** `Packages/OsaurusCore/Views/Toast/ThemedToastView.swift`
- **Preview Type:** `PreviewProvider`
- **Purpose:** Theme-aware toast with glass effects and accent colors.
- **Key Dependencies:**
  - Theme system
  - ToastData
- **Preview Scenarios:** Various themes and states
- **Notes:** Respects light/dark mode and custom themes.

### BackgroundTaskToastView.swift
- **Path:** `Packages/OsaurusCore/Views/Toast/BackgroundTaskToastView.swift`
- **Preview Type:** `PreviewProvider`
- **Purpose:** Specialized toast for background task progress notifications.
- **Key Dependencies:**
  - BackgroundTask model
  - Progress indicators
- **Preview Scenarios:** Tasks at different progress levels
- **Notes:** Shows progress bar, step counter, and morphing status icons.

### ToastContainerView.swift
- **Path:** `Packages/OsaurusCore/Views/Toast/ToastContainerView.swift`
- **Preview Type:** `PreviewProvider`
- **Purpose:** Container managing toast queue and positioning.
- **Key Dependencies:**
  - ToastManager
  - Toast lifecycle
- **Preview Scenarios:** Multiple stacked toasts
- **Notes:** Handles enter/exit animations and z-ordering.

---

## Work Views

### WorkTaskSidebar.swift
- **Path:** `Packages/OsaurusCore/Views/Work/WorkTaskSidebar.swift`
- **Preview Type:** `PreviewProvider`
- **Purpose:** Sidebar for work mode showing issue tracker with task hierarchy.
- **Key Dependencies:**
  - Issue model
  - IssueDependency graph
  - IssueStore
- **Preview Scenarios:** Task list with various statuses
- **Notes:** Tree view showing objectives → issues → sub-issues.

---

## Schedule Views

### SchedulesView.swift
- **Path:** `Packages/OsaurusCore/Views/Schedule/SchedulesView.swift`
- **Preview Type:** `#Preview`
- **Purpose:** Management interface for recurring task automation (cron-like schedules).
- **Key Dependencies:**
  - ScheduleManager
  - Schedule model
  - Frequency enum (once, hourly, daily, weekly, monthly, cron)
- **Notes:** Create, edit, enable/disable scheduled agent tasks.

---

## Sandbox Views

### SandboxView.swift
- **Path:** `Packages/OsaurusCore/Views/Sandbox/SandboxView.swift`
- **Preview Type:** `#Preview`
- **Purpose:** Management interface for Linux VM sandbox (Apple Containerization).
- **Key Dependencies:**
  - SandboxManager
  - SandboxPluginManager
  - VM configuration
- **Notes:** Two-tab interface: Container settings, Agent workspaces.

---

## Watcher Views

### WatchersView.swift
- **Path:** `Packages/OsaurusCore/Views/Watcher/WatchersView.swift`
- **Preview Type:** `#Preview`
- **Purpose:** File system watcher configuration (FSEvents-based monitoring that triggers agents).
- **Key Dependencies:**
  - WatcherManager
  - Watcher model
  - FSEvents
- **Notes:** Configure paths, responsiveness, and agent reactions to file changes.

---

## Insights Views

### InsightsView.swift
- **Path:** `Packages/OsaurusCore/Views/Insights/InsightsView.swift`
- **Preview Type:** `#Preview`
- **Purpose:** Analytics and insights dashboard (usage stats, memory trends, etc.).
- **Key Dependencies:**
  - Analytics data
  - Chart components
- **Notes:** Visualizes app usage patterns and performance metrics.

---

## Summary Statistics

### Preview Type Distribution

| Preview Type | Count | Percentage |
|--------------|-------|------------|
| #Preview (modern) | 26 | 43.3% |
| PreviewProvider (legacy) | 34 | 56.7% |
| **Total** | **60** | **100%** |

### Views by Feature Area

| Feature Area | Count | Preview Types |
|--------------|-------|---------------|
| Common Components | 7 | 3 #Preview, 4 PreviewProvider |
| Chat | 6 | 6 PreviewProvider |
| Onboarding | 8 | 8 PreviewProvider |
| Voice | 9 | 1 #Preview, 8 PreviewProvider |
| Toast | 4 | 4 PreviewProvider |
| Settings | 7 | 7 #Preview |
| Plugin/Tools | 4 | 4 #Preview |
| Skills | 3 | 3 #Preview |
| Management | 4 | 4 #Preview |
| Models | 2 | 1 #Preview, 1 PreviewProvider |
| Agent | 1 | 1 #Preview |
| Work | 1 | 1 PreviewProvider |
| Schedule | 1 | 1 #Preview |
| Sandbox | 1 | 1 #Preview |
| Watcher | 1 | 1 #Preview |
| Insights | 1 | 1 #Preview |

### Migration Recommendations

**High Priority** (frequently changed, complex previews):
1. Chat views (6 files) - Core user-facing UI, active development
2. Voice views (8 files) - Complex state management would benefit from modern syntax
3. Toast views (4 files) - Heavily reused, modern syntax reduces boilerplate

**Medium Priority** (stable, but would benefit):
1. Onboarding views (8 files) - One-time setup flow, less frequently changed
2. Model views (1 file) - ModelPickerView is complex and could use simplification

**Low Priority** (already modern or simple):
- All settings views ✓ (already using #Preview)
- All management views ✓ (already using #Preview)
- All plugin/tool views ✓ (already using #Preview)

---

## Preview Best Practices

### Modern #Preview Macro
```swift
#Preview {
    MyView(data: sampleData)
        .frame(width: 400, height: 600)
        .background(Color(hex: "0f0f10"))
}

// Named previews
#Preview("Dark Mode") {
    MyView().preferredColorScheme(.dark)
}

#Preview("Light Mode") {
    MyView().preferredColorScheme(.light)
}
```

### Legacy PreviewProvider
```swift
#if DEBUG
    struct MyView_Previews: PreviewProvider {
        static var previews: some View {
            MyView(data: sampleData)
                .frame(width: 400, height: 600)
                .background(Color(hex: "0f0f10"))
        }
    }
#endif
```

### Common Preview Dependencies
- **Theme**: Most views depend on `@Environment(\.theme)` - ensure theme provider in preview
- **Managers**: Use `.shared` singletons or provide mock instances
- **Sample Data**: Define static sample data for previews (e.g., `Agent.default`, sample markdown strings)
- **Frame Sizing**: Explicitly set frame dimensions for consistent preview rendering
- **Background**: Many views are designed for dark mode - preview with `Color(hex: "0f0f10")` background

---

## Notes

- All preview files are wrapped in `#if DEBUG` to exclude them from release builds
- Preview data should be lightweight and not require real system resources
- Some views may have preview limitations due to dependencies on:
  - Native system permissions (camera, microphone)
  - External services (model downloads, API calls)
  - Hardware-specific features (notch detection, biometric auth)
  - AppKit-heavy components (NSViewRepresentable wrappers)

For views with complex dependencies, previews focus on the UI structure and layout rather than full functionality.

---

*Last Updated: 2026-04-09*
*Generated from OsaurusCore package inspection*
