import Foundation

/// Events emitted by the stream accumulator.
public enum StreamEvent: Sendable {
    /// Normal text content to display.
    case tokens(String)
    /// Reasoning/thinking content (inside think tags).
    case thinking(String)
    /// Tool call detected and complete.
    case toolInvocation(name: String, argsJSON: String, callId: String)
    /// Generation finished.
    case finished(reason: FinishReason)
}

/// Transforms raw token text into typed StreamEvents.
/// Integrates tool call parsing, reasoning extraction, and stop sequence detection.
public struct StreamAccumulator: Sendable {

    private var toolParser: (any ToolCallParser)?
    private var reasoningParser: (any ReasoningParser)?
    private var stopDetector: StopSequenceDetector

    /// All generated text so far (for tool call context).
    private var fullText: String = ""

    /// Generated token IDs so far.
    public private(set) var generatedTokenIds: [Int] = []

    public init(
        toolParser: (any ToolCallParser)? = nil,
        reasoningParser: (any ReasoningParser)? = nil,
        stopSequences: [String] = []
    ) {
        self.toolParser = toolParser
        self.reasoningParser = reasoningParser
        self.stopDetector = StopSequenceDetector(stopSequences: stopSequences)
    }

    /// Process a new text chunk (decoded from token IDs).
    /// Returns zero or more events to emit.
    public mutating func process(text: String, tokenIds: [Int] = []) -> [StreamEvent] {
        generatedTokenIds.append(contentsOf: tokenIds)
        fullText += text

        var events: [StreamEvent] = []

        // Step 1: Reasoning parser (extract think blocks)
        var contentText = text
        if var parser = reasoningParser {
            let result = parser.processChunk(text)
            reasoningParser = parser

            if let thinking = result.reasoning, !thinking.isEmpty {
                events.append(.thinking(thinking))
            }
            // Replace content with non-thinking portion
            contentText = result.content ?? ""
        }

        guard !contentText.isEmpty else { return events }

        // Step 2: Tool call parser
        if var parser = toolParser {
            let results = parser.processChunk(contentText)
            toolParser = parser

            for result in results {
                switch result {
                case .text(let t):
                    // Step 3: Stop sequence detection on text output
                    let safe = stopDetector.process(t)
                    if !safe.isEmpty {
                        events.append(.tokens(safe))
                    }
                    if stopDetector.stopped {
                        events.append(.finished(reason: .stop))
                        return events
                    }
                case .buffered:
                    break  // Accumulating potential tool call
                case .toolCall(let tc):
                    events.append(.toolInvocation(
                        name: tc.name, argsJSON: tc.argumentsJSON, callId: tc.id
                    ))
                }
            }
        } else {
            // No tool parser — just stop detection
            let safe = stopDetector.process(contentText)
            if !safe.isEmpty {
                events.append(.tokens(safe))
            }
            if stopDetector.stopped {
                events.append(.finished(reason: .stop))
            }
        }

        return events
    }

    /// Finalize: flush buffers, check for remaining tool calls.
    public mutating func finalize() -> [StreamEvent] {
        var events: [StreamEvent] = []

        // Flush tool parser
        if var parser = toolParser {
            let toolCalls = parser.finalize()
            toolParser = parser
            for tc in toolCalls {
                events.append(.toolInvocation(
                    name: tc.name, argsJSON: tc.argumentsJSON, callId: tc.id
                ))
            }
        }

        // Flush reasoning parser
        if var parser = reasoningParser {
            let result = parser.finalize()
            reasoningParser = parser
            if let thinking = result.reasoning, !thinking.isEmpty {
                events.append(.thinking(thinking))
            }
            if let content = result.content, !content.isEmpty {
                let safe = stopDetector.process(content)
                if !safe.isEmpty {
                    events.append(.tokens(safe))
                }
            }
        }

        // Flush stop detector buffer
        let remaining = stopDetector.flush()
        if !remaining.isEmpty {
            events.append(.tokens(remaining))
        }

        return events
    }

    /// Reset all state for next generation.
    public mutating func reset() {
        toolParser?.reset()
        reasoningParser?.reset()
        stopDetector.reset()
        fullText = ""
        generatedTokenIds = []
    }

    /// Total generated text.
    public var totalText: String { fullText }
}
