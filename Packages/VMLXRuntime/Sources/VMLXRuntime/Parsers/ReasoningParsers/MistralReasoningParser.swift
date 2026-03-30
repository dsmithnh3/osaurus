import Foundation

/// Reasoning parser for Mistral 4 models.
///
/// Mistral 4 uses `[THINK]...[/THINK]` tokens for reasoning content, controlled
/// via the `reasoning_effort` field in the chat template.
///
/// Token IDs: `[THINK]` = 34, `[/THINK]` = 35 (extra_special_tokens in tokenizer).
/// When decoded, these produce the literal text strings `[THINK]` and `[/THINK]`.
///
/// Supports three scenarios:
/// 1. Both tags in output: `[THINK]reasoning[/THINK]content`
/// 2. Only closing tag (think in prompt): `reasoning[/THINK]content`
/// 3. No tags: pure content (`reasoning_effort="none"`)
public struct MistralReasoningParser: ReasoningParser {

    public static var supportedModels: [String] { ["mistral4", "mistral-large"] }

    private var buffer: String = ""
    private var inThinking: Bool = false

    private static let openTag = "[THINK]"
    private static let closeTag = "[/THINK]"

    public init() {}

    public mutating func processChunk(_ text: String) -> ReasoningResult {
        buffer += text

        if !inThinking {
            // Look for opening tag
            if let range = buffer.range(of: Self.openTag) {
                let beforeTag = String(buffer[buffer.startIndex..<range.lowerBound])
                buffer = String(buffer[range.upperBound...])
                inThinking = true

                // Check if close tag is also in remaining buffer
                if let closeRange = buffer.range(of: Self.closeTag) {
                    let thinking = String(buffer[buffer.startIndex..<closeRange.lowerBound])
                    buffer = String(buffer[closeRange.upperBound...])
                    inThinking = false
                    return ReasoningResult(
                        reasoning: thinking.isEmpty ? nil : thinking,
                        content: beforeTag.isEmpty ? (buffer.isEmpty ? nil : buffer) : beforeTag,
                        inThinking: false
                    )
                }

                // Still inside thinking
                let thinking = buffer
                buffer = ""
                return ReasoningResult(
                    reasoning: thinking.isEmpty ? nil : thinking,
                    content: beforeTag.isEmpty ? nil : beforeTag,
                    inThinking: true
                )
            }

            // Check for close tag only (implicit reasoning mode)
            if let closeRange = buffer.range(of: Self.closeTag) {
                let reasoning = String(buffer[buffer.startIndex..<closeRange.lowerBound])
                buffer = String(buffer[closeRange.upperBound...])
                return ReasoningResult(
                    reasoning: reasoning.isEmpty ? nil : reasoning,
                    content: buffer.isEmpty ? nil : buffer,
                    inThinking: false
                )
            }

            // Check for partial tag at end
            let partialLen = _partialTagMatchLength(Self.openTag)
            if partialLen > 0 {
                let safeEnd = buffer.index(buffer.endIndex, offsetBy: -partialLen)
                let safe = String(buffer[buffer.startIndex..<safeEnd])
                buffer = String(buffer[safeEnd...])
                return ReasoningResult(reasoning: nil, content: safe.isEmpty ? nil : safe, inThinking: false)
            }

            // Also check for partial close tag (implicit mode)
            let partialCloseLen = _partialTagMatchLength(Self.closeTag)
            if partialCloseLen > 0 {
                let safeEnd = buffer.index(buffer.endIndex, offsetBy: -partialCloseLen)
                let safe = String(buffer[buffer.startIndex..<safeEnd])
                buffer = String(buffer[safeEnd...])
                return ReasoningResult(reasoning: nil, content: safe.isEmpty ? nil : safe, inThinking: false)
            }

            // No tag activity
            let content = buffer
            buffer = ""
            return ReasoningResult(reasoning: nil, content: content.isEmpty ? nil : content, inThinking: false)

        } else {
            // Inside thinking block -- look for close tag
            if let closeRange = buffer.range(of: Self.closeTag) {
                let thinking = String(buffer[buffer.startIndex..<closeRange.lowerBound])
                buffer = String(buffer[closeRange.upperBound...])
                inThinking = false
                return ReasoningResult(
                    reasoning: thinking.isEmpty ? nil : thinking,
                    content: buffer.isEmpty ? nil : buffer,
                    inThinking: false
                )
            }

            // Check for partial close tag
            let partialLen = _partialTagMatchLength(Self.closeTag)
            if partialLen > 0 {
                let safeEnd = buffer.index(buffer.endIndex, offsetBy: -partialLen)
                let safe = String(buffer[buffer.startIndex..<safeEnd])
                buffer = String(buffer[safeEnd...])
                return ReasoningResult(reasoning: safe.isEmpty ? nil : safe, content: nil, inThinking: true)
            }

            // No close tag -- all is reasoning
            let thinking = buffer
            buffer = ""
            return ReasoningResult(reasoning: thinking.isEmpty ? nil : thinking, content: nil, inThinking: true)
        }
    }

    public mutating func finalize() -> ReasoningResult {
        let remaining = buffer
        buffer = ""
        if inThinking {
            inThinking = false
            return ReasoningResult(reasoning: remaining.isEmpty ? nil : remaining, content: nil, inThinking: false)
        }
        return ReasoningResult(reasoning: nil, content: remaining.isEmpty ? nil : remaining, inThinking: false)
    }

    public mutating func reset() {
        buffer = ""
        inThinking = false
    }

    // MARK: - Private

    private func _partialTagMatchLength(_ tag: String) -> Int {
        for len in (1..<tag.count).reversed() {
            let tagPrefix = String(tag.prefix(len))
            if buffer.hasSuffix(tagPrefix) {
                return len
            }
        }
        return 0
    }
}
