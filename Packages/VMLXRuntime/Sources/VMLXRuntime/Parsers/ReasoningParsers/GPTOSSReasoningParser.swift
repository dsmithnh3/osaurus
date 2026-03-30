import Foundation

/// Reasoning parser for GPT-OSS / Harmony protocol models.
///
/// GPT-OSS models use channel markers to separate reasoning from content:
/// ```
/// <|channel|>analysis<|message|>...reasoning...
/// <|channel|>final<|message|>...content...
/// ```
///
/// When the Harmony analysis prefix is injected into the prompt, the model
/// output starts directly with reasoning text (no leading marker) and
/// transitions to content via `<|channel|>final<|message|>`.
///
/// Used by GLM-4.7 Flash and similar models with Harmony protocol.
public struct GPTOSSReasoningParser: ReasoningParser {

    public static var supportedModels: [String] { ["gptoss", "harmony"] }

    private var buffer: String = ""
    private var emittedReasoning: Int = 0
    private var emittedContent: Int = 0
    private var sawMarker: Bool = false

    // Channel marker tokens
    private static let channelTag = "<|channel|>"
    private static let messageTag = "<|message|>"
    private static let startTag = "<|start|>"
    private static let analysisChannel = "analysis"
    private static let finalChannel = "final"

    // Full marker strings
    private static let analysisMarker = "<|channel|>analysis<|message|>"
    private static let finalMarker = "<|channel|>final<|message|>"

    public init() {}

    public mutating func processChunk(_ text: String) -> ReasoningResult {
        buffer += text

        // Parse the entire accumulated buffer each time
        let (reasoning, content) = _parseChannels(buffer)

        if !sawMarker && (reasoning != nil || content != nil) {
            // Check if we actually have Harmony markers
            if buffer.contains(Self.channelTag) || buffer.contains(Self.startTag) {
                sawMarker = true
            }
        }

        // If no Harmony markers detected, treat as plain content
        if !sawMarker {
            // Buffer a few chars to detect potential markers
            if buffer.count < 3 {
                return ReasoningResult(reasoning: nil, content: nil, inThinking: false)
            }
            let output = buffer
            buffer = ""
            return ReasoningResult(reasoning: nil, content: output, inThinking: false)
        }

        // Calculate deltas
        var newReasoning: String? = nil
        var newContent: String? = nil

        if let r = reasoning, r.count > emittedReasoning {
            newReasoning = String(r.dropFirst(emittedReasoning))
            emittedReasoning = r.count
        }

        if let c = content, c.count > emittedContent {
            newContent = String(c.dropFirst(emittedContent))
            emittedContent = c.count
        }

        let inThinking = reasoning != nil && content == nil

        return ReasoningResult(
            reasoning: newReasoning,
            content: newContent,
            inThinking: inThinking
        )
    }

    public mutating func finalize() -> ReasoningResult {
        let remaining = buffer
        buffer = ""

        if sawMarker {
            let (reasoning, content) = _parseChannels(remaining)

            var newReasoning: String? = nil
            var newContent: String? = nil

            if let r = reasoning, r.count > emittedReasoning {
                newReasoning = String(r.dropFirst(emittedReasoning))
            }
            if let c = content, c.count > emittedContent {
                newContent = String(c.dropFirst(emittedContent))
            }

            emittedReasoning = 0
            emittedContent = 0
            sawMarker = false

            return ReasoningResult(reasoning: newReasoning, content: newContent, inThinking: false)
        }

        emittedReasoning = 0
        emittedContent = 0
        sawMarker = false

        return ReasoningResult(reasoning: nil, content: remaining.isEmpty ? nil : remaining, inThinking: false)
    }

    public mutating func reset() {
        buffer = ""
        emittedReasoning = 0
        emittedContent = 0
        sawMarker = false
    }

    // MARK: - Private

    /// Parse channel content from text. Returns (reasoning, content).
    private func _parseChannels(_ text: String) -> (String?, String?) {
        var reasoningParts: [String] = []
        var contentParts: [String] = []

        var workText = text

        // Strip leading <|start|>assistant if present
        let startAssistant = Self.startTag + "assistant"
        if workText.hasPrefix(startAssistant) {
            workText = String(workText.dropFirst(startAssistant.count))
        }

        if !workText.contains(Self.channelTag) {
            // No channel markers at all
            return (nil, nil)
        }

        // Text before first channel marker is implicit reasoning
        if let firstChannel = workText.range(of: Self.channelTag) {
            let preText = String(workText[workText.startIndex..<firstChannel.lowerBound])
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if !preText.isEmpty {
                reasoningParts.append(preText)
            }
            workText = String(workText[firstChannel.lowerBound...])
        }

        // Parse channel markers
        while let channelRange = workText.range(of: Self.channelTag) {
            let afterChannel = String(workText[channelRange.upperBound...])

            if afterChannel.hasPrefix(Self.analysisChannel + Self.messageTag) {
                let contentStart = afterChannel.index(afterChannel.startIndex, offsetBy: (Self.analysisChannel + Self.messageTag).count)
                let remaining = String(afterChannel[contentStart...])

                // Find next channel marker
                if let nextChannel = remaining.range(of: Self.channelTag) {
                    let part = String(remaining[remaining.startIndex..<nextChannel.lowerBound])
                        .trimmingCharacters(in: .whitespacesAndNewlines)
                    if !part.isEmpty {
                        reasoningParts.append(part)
                    }
                    workText = String(remaining[nextChannel.lowerBound...])
                } else if let nextStart = remaining.range(of: Self.startTag) {
                    let part = String(remaining[remaining.startIndex..<nextStart.lowerBound])
                        .trimmingCharacters(in: .whitespacesAndNewlines)
                    if !part.isEmpty {
                        reasoningParts.append(part)
                    }
                    workText = String(remaining[nextStart.upperBound...])
                } else {
                    let part = remaining.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !part.isEmpty {
                        reasoningParts.append(part)
                    }
                    workText = ""
                }
            } else if afterChannel.hasPrefix(Self.finalChannel + Self.messageTag) {
                let contentStart = afterChannel.index(afterChannel.startIndex, offsetBy: (Self.finalChannel + Self.messageTag).count)
                let remaining = String(afterChannel[contentStart...])

                // Find next channel marker (stop after first final)
                if let nextChannel = remaining.range(of: Self.channelTag) {
                    let part = String(remaining[remaining.startIndex..<nextChannel.lowerBound])
                        .trimmingCharacters(in: .whitespacesAndNewlines)
                    if !part.isEmpty {
                        contentParts.append(part)
                    }
                    // Stop after first final channel to prevent second-cycle leaks
                    break
                } else if let nextStart = remaining.range(of: Self.startTag) {
                    let part = String(remaining[remaining.startIndex..<nextStart.lowerBound])
                        .trimmingCharacters(in: .whitespacesAndNewlines)
                    if !part.isEmpty {
                        contentParts.append(part)
                    }
                    break
                } else {
                    let part = remaining.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !part.isEmpty {
                        contentParts.append(part)
                    }
                    workText = ""
                }
            } else {
                // Unknown channel, skip
                break
            }
        }

        let reasoning = reasoningParts.isEmpty ? nil : reasoningParts.joined(separator: "\n")
        let content = contentParts.isEmpty ? nil : contentParts.joined(separator: "\n")
        return (reasoning, content)
    }
}
