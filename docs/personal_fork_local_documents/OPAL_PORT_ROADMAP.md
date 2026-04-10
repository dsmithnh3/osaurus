# Osaurus Enhancements Roadmap

**Date:** 2026-04-09
**Source:** Opal codebase analysis (`~/Documents/clui-cc-main`)
**Purpose:** Features worth porting from Opal to Osaurus (rewritten in Swift)

---

## Priority 1: Claude Code CLI as Model Provider

**What:** Add `claude` CLI as a first-class model provider in Osaurus, so Daniel's Pro/Max subscription works as an inference backend — no API key needed.

**Why this is the highest priority:**
- Uses existing Claude Code subscription (not API credits)
- CLI handles auth, rate limiting, retries, session resume
- Gets Claude's full tool ecosystem (file editing, bash, MCP servers) as a bonus
- Osaurus agents could delegate to Claude Code for heavy reasoning tasks

**How Opal does it:**
- Spawns `claude -p --input-format stream-json --output-format stream-json --verbose`
- Bidirectional NDJSON over stdin/stdout
- 7 event types: `system/init`, `stream_event`, `assistant`, `result`, `rate_limit_event`, `permission_request`, unknown
- Permission responses sent back via stdin: `{type: "permission_response", question_id, option_id}`
- Session resume via `--resume SESSION_ID`
- Process lifecycle: SIGINT to cancel, SIGKILL after 5s fallback

**Swift implementation plan:**

| Component | OsaurusCore Location | Description |
|-----------|---------------------|-------------|
| `ClaudeCodeProvider` | `Services/Providers/` | New provider conforming to existing model routing protocol |
| `ClaudeCodeProcess` | `Services/Providers/` | Swift `Process` wrapper — spawn CLI, pipe stdin/stdout, parse NDJSON |
| `ClaudeCodeEventParser` | `Services/Providers/` | Parse NDJSON stream → normalize to Osaurus chat events |
| `ClaudeCodeSessionStore` | `Storage/` | Track session IDs for resume, map to Osaurus conversations |

**CLI binary discovery** (same as Opal):
```
~/.local/bin/claude
/usr/local/bin/claude  
/opt/homebrew/bin/claude
$(npm root -g)/claude
```

**Key flags:**
```bash
claude -p \
  --input-format stream-json \
  --output-format stream-json \
  --verbose \
  --include-partial-messages \
  --model <model> \
  --system-prompt <text> \
  --append-system-prompt <text> \
  --resume <sessionId> \
  --max-turns <n>
```

**Input message format (stdin):**
```json
{"type": "user", "message": {"role": "user", "content": [{"type": "text", "text": "..."}]}}
```

**Streaming output (stdout NDJSON):**
```json
{"type": "system", "subtype": "init", "session_id": "...", "tools": [...], "model": "..."}
{"type": "stream_event", "event": {"type": "content_block_delta", "delta": {"type": "text_delta", "text": "..."}}}
{"type": "result", "result": "...", "cost_usd": 0.05, "session_id": "..."}
```

**Environment cleanup:** Must remove `CLAUDECODE_*` and `CLAUDE_CODE_*` env vars before spawning to prevent CLI thinking it's a sub-process.

**Effort:** Medium (2-3 days). Osaurus already has `ModelServiceRouter` — this adds a new route alongside MLX, OpenAI-compat, Anthropic-compat, and Ollama.

---

## Priority 2: Ambient Context Helper

**What:** Passive macOS accessibility monitor that detects the frontmost app, extracts context (active file, selected text, window title), and auto-injects it into agent system prompts.

**Why:** Makes CIMCO agents contextually aware without any extra prompting. The Project Manager would automatically know you're reading an email from Robert Sonntag in Mail, or viewing a P&ID in Preview.

**How Opal does it:**
- Swift `context-helper` daemon using `AXUIElement` + `NSWorkspace`
- 17+ app-specific parsers (VS Code, Xcode, Terminal, Safari, Mail, Finder, Chrome, Notion, etc.)
- Outputs JSON context blob: `{app, title, selectedText, filePath, url, ...}`
- Injected as `[Active Context]` block prepended to system prompts
- Graceful degradation if accessibility permissions denied
- Runs as long-lived subprocess, polled on each prompt

**Swift implementation plan:**

| Component | OsaurusCore Location | Description |
|-----------|---------------------|-------------|
| `AmbientContextService` | `Services/` | Actor — polls frontmost app via `NSWorkspace.shared.frontmostApplication` |
| `AppContextParser` | `Services/Context/` | Protocol + 17 implementations (one per app) |
| `AmbientContextModel` | `Models/` | `AmbientContext` struct: app, title, selectedText, filePath, url |
| Integration | `Services/SystemPromptComposer` | Inject context block after memory context, before tools |

**App parsers to port:**

| App | Context Extracted |
|-----|------------------|
| VS Code | Active file path, workspace, language, selected text |
| Xcode | Project, scheme, active file, build status |
| Terminal/iTerm | Current directory, running command |
| Safari/Chrome | URL, page title, selected text |
| Mail | Sender, subject, selected text |
| Finder | Current directory, selected files |
| Preview | Open file path, page number |
| Microsoft Outlook | Sender, subject, folder |
| Microsoft Excel | Active workbook, sheet, selected range |
| Notes | Note title, folder |

**Key API:** `AXUIElementCopyAttributeValue()` for accessibility tree introspection. Requires Accessibility permission (System Settings → Privacy & Security → Accessibility).

**Effort:** Medium (2-3 days). The Swift code already exists in Opal's context-helper — it's a matter of refactoring into OsaurusCore's actor model.

---

## Priority 3: URL Scheme Automation

**What:** Register `osaurus://` URL protocol for external automation from Raycast, Alfred, Shortcuts, browser scripts, etc.

**Why:** Enables workflows like:
- Raycast shortcut → `osaurus://prompt?agent=CIMCO+PM&text=My+tasks+this+week`
- Alfred trigger → `osaurus://new-tab?agent=CIMCO+Estimator`
- Browser bookmarklet → `osaurus://prompt?text=Analyze+this+page`
- Apple Shortcuts → chain Osaurus actions with other apps

**How Opal does it:**
- Registers `opal://` via Electron's protocol handler
- Routes: `open`, `prompt`, `new-tab`
- Parameters: `provider`, `model`, `profile` (workspace), `cwd`, `focus`, `reuseTab`
- Smart tab reuse: prompts reuse idle compatible tabs; create new if busy or provider mismatch

**Swift implementation plan:**

| Component | Location | Description |
|-----------|----------|-------------|
| URL scheme registration | `App/Info.plist` | Register `osaurus://` CFBundleURLSchemes |
| `URLSchemeHandler` | `App/` | Parse incoming URLs, route to appropriate action |
| Actions | `Managers/` | `openAgent(id:)`, `sendPrompt(agentId:, text:)`, `newChat(agentId:)` |

**Proposed routes:**
```
osaurus://open                          # Focus app
osaurus://prompt?text=...&agent=...     # Send prompt to agent
osaurus://agent?name=...               # Switch to agent
osaurus://work?agent=...&task=...       # Start work mode task
osaurus://screenshot                    # Capture + analyze
```

**Effort:** Small (1 day). Standard macOS URL scheme handling via `NSAppleEventManager` or SwiftUI's `onOpenURL`.

---

## Priority 4: Tool Approval Taxonomy

**What:** Fine-grained tool permission classes with safe-command whitelisting, replacing the current binary ask/auto/deny model.

**Why:** The current model either blocks everything (ask) or allows everything (auto). A taxonomy lets read-only operations auto-approve while write/exec operations require confirmation — better for autonomous agents.

**How Opal does it:**
- 5 approval classes: `file_write`, `shell_exec`, `mcp_external`, `browser_action`, `workspace_change`
- Safe-command whitelist (20+ commands auto-approved): `cat`, `ls`, `grep`, `git status`, `git log`, `git diff`, `find`, `wc`, `head`, `tail`, `which`, `echo`, `pwd`, `env`, `date`, `uname`
- Per-run security tokens prevent cross-run confusion
- PermissionServer on localhost (HTTP hook for CLI providers)

**Swift implementation plan:**

| Component | OsaurusCore Location | Description |
|-----------|---------------------|-------------|
| `ToolApprovalClass` | `Models/` | Enum: `readOnly`, `fileWrite`, `shellExec`, `mcpExternal`, `browserAction`, `workspaceChange` |
| `ToolApprovalPolicy` | `Services/` | Maps tool names → approval classes, checks whitelist |
| Integration | `Tools/ToolRegistry` | Extend existing permission gating with class-based decisions |

**Effort:** Small (1 day). Extends existing tool permission infrastructure.

---

## Priority 5: Vision/Screenshot Context Pipeline

**What:** Take a screenshot → run local OCR (Apple Vision) → inject extracted text as context for the active agent.

**Why:** "Ask about this" workflow — screenshot what you're looking at, agent gets the text content without needing to access the app directly. Useful for P&IDs in Preview, emails in Outlook, specs in PDFs.

**How Opal does it:**
- Pre-compiled Swift binary using Apple Vision framework (~0.9s)
- Three modes: "Insert as text" (OCR → paste), "Copy markdown", "Ask about this" (OCR → prompt)
- Fallback chain: local OCR → Whisper → provider API vision
- Results cached during action picker for immediate preview

**Swift implementation plan:**

| Component | OsaurusCore Location | Description |
|-----------|---------------------|-------------|
| `ScreenCaptureService` | `Services/` | `CGWindowListCreateImage` or ScreenCaptureKit |
| `VisionOCRService` | `Services/` | `VNRecognizeTextRequest` — already available in Osaurus's macOS target |
| `ScreenshotTool` | `Tools/` | MCP tool: capture → OCR → return text |

**Effort:** Small (1 day). Apple Vision framework is already available to Osaurus.

---

## Summary

| # | Enhancement | Value | Effort | Dependencies |
|---|-------------|-------|--------|-------------|
| 1 | Claude Code CLI Provider | 🔴 Critical — uses Pro sub as model | Medium (2-3d) | Claude CLI installed |
| 2 | Ambient Context Helper | 🟠 High — passive intelligence | Medium (2-3d) | Accessibility permission |
| 3 | URL Scheme Automation | 🟡 Medium — external integration | Small (1d) | None |
| 4 | Tool Approval Taxonomy | 🟡 Medium — safety improvement | Small (1d) | None |
| 5 | Vision/Screenshot Pipeline | 🟢 Nice-to-have | Small (1d) | None |

**Total estimated effort:** 7-9 days

---

## Not Porting (Osaurus Already Better)

| Opal Feature | Why Skip |
|-------------|----------|
| Multi-provider kernel | Osaurus `ModelServiceRouter` handles this |
| Terminal tabs | Osaurus sandbox VM is more capable |
| Session history | Osaurus 4-layer memory is far superior |
| MCP client/server | Osaurus is both natively |
| Skill installation | Osaurus has its own skill + plugin system |
| Workspace profiles | Osaurus agents serve this purpose |
| Spring animations | Osaurus has its own SwiftUI polish |
| Provider Hub UI | Osaurus Settings already handles this |
