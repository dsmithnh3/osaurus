import Foundation

/// Tool call parser for Kimi K2 and Moonshot models.
///
/// Supports Kimi's special token-based tool call format:
/// ```
/// <|tool_calls_section_begin|>
/// <|tool_call_begin|>get_weather:0<|tool_call_argument_begin|>{"city": "Paris"}<|tool_call_end|>
/// <|tool_calls_section_end|>
/// ```
///
/// Function names may be prefixed with `functions.` and suffixed with `:N` call index.
public struct MoonshotToolParser: ToolCallParser {

    public static var supportedModels: [String] { ["moonshot", "kimi"] }

    private var buffer: String = ""
    private var state: State = .text

    private enum State {
        case text
        case potentialTag
        case inToolCalls     // Between section begin and section end
    }

    // Kimi tokens
    private static let sectionBeginTokens = [
        "<|tool_calls_section_begin|>",
        "<|tool_call_section_begin|>",   // Singular variant
    ]
    private static let sectionEndToken = "<|tool_calls_section_end|>"
    private static let callBeginToken = "<|tool_call_begin|>"
    private static let callEndToken = "<|tool_call_end|>"
    private static let argBeginToken = "<|tool_call_argument_begin|>"

    public init() {}

    public mutating func processChunk(_ text: String) -> [ToolParserResult] {
        var results: [ToolParserResult] = []
        buffer += text

        while !buffer.isEmpty {
            switch state {
            case .text:
                // Look for section begin or individual call begin
                if let (range, _) = _findToken(in: buffer, tokens: Self.sectionBeginTokens) {
                    let prefix = String(buffer[buffer.startIndex..<range.lowerBound])
                    if !prefix.isEmpty {
                        results.append(.text(prefix))
                    }
                    buffer = String(buffer[range.upperBound...])
                    state = .inToolCalls
                    continue
                }

                // Also match if we see <|tool_call_begin|> without section wrapper
                if let callRange = buffer.range(of: Self.callBeginToken) {
                    let prefix = String(buffer[buffer.startIndex..<callRange.lowerBound])
                    if !prefix.isEmpty {
                        results.append(.text(prefix))
                    }
                    buffer = String(buffer[callRange.lowerBound...])
                    state = .inToolCalls
                    continue
                }

                // Check for potential partial token at end
                if _hasPotentialTokenStart(buffer) {
                    state = .potentialTag
                    results.append(.buffered)
                    return results
                }

                results.append(.text(buffer))
                buffer = ""

            case .potentialTag:
                // Check if we now have a full token
                if _findToken(in: buffer, tokens: Self.sectionBeginTokens) != nil ||
                   buffer.contains(Self.callBeginToken) {
                    state = .text
                    continue
                } else if _isPotentialTokenPrefix(buffer) {
                    results.append(.buffered)
                    return results
                } else {
                    state = .text
                    continue
                }

            case .inToolCalls:
                // Look for section end or check if we have complete tool calls
                if buffer.contains(Self.sectionEndToken) || buffer.contains(Self.callEndToken) {
                    let calls = _parseToolCallsBlock(buffer)
                    if !calls.isEmpty {
                        for call in calls {
                            results.append(.toolCall(call))
                        }
                        // Remove everything up to and including section end
                        if let endRange = buffer.range(of: Self.sectionEndToken) {
                            buffer = String(buffer[endRange.upperBound...])
                        } else {
                            // No section end, remove up to last call end
                            if let lastCallEnd = buffer.range(of: Self.callEndToken, options: .backwards) {
                                buffer = String(buffer[lastCallEnd.upperBound...])
                            } else {
                                buffer = ""
                            }
                        }
                        state = .text
                    } else {
                        results.append(.buffered)
                        return results
                    }
                } else {
                    results.append(.buffered)
                    return results
                }
            }
        }

        return results
    }

    public mutating func finalize() -> [ParsedToolCall] {
        guard !buffer.isEmpty else { return [] }

        let text = buffer
        buffer = ""
        state = .text

        return _parseToolCallsBlock(text)
    }

    public mutating func reset() {
        buffer = ""
        state = .text
    }

    // MARK: - Private

    private func _findToken(in text: String, tokens: [String]) -> (Range<String.Index>, String)? {
        for token in tokens {
            if let range = text.range(of: token) {
                return (range, token)
            }
        }
        return nil
    }

    private func _hasPotentialTokenStart(_ text: String) -> Bool {
        let allTokens = Self.sectionBeginTokens + [Self.callBeginToken]
        for token in allTokens {
            for i in 1..<token.count {
                let prefix = String(token.prefix(i))
                if text.hasSuffix(prefix) { return true }
            }
        }
        return false
    }

    private func _isPotentialTokenPrefix(_ text: String) -> Bool {
        let allTokens = Self.sectionBeginTokens + [Self.callBeginToken]
        for token in allTokens {
            if token.hasPrefix(text) { return true }
        }
        return false
    }

    /// Parse individual tool calls from within a tool calls section.
    ///
    /// Format: `<|tool_call_begin|>func_name:0<|tool_call_argument_begin|>{...}<|tool_call_end|>`
    private func _parseToolCallsBlock(_ text: String) -> [ParsedToolCall] {
        var calls: [ParsedToolCall] = []
        var remaining = text

        while let beginRange = remaining.range(of: Self.callBeginToken) {
            guard let endRange = remaining.range(of: Self.callEndToken, range: beginRange.upperBound..<remaining.endIndex) else { break }

            let callContent = String(remaining[beginRange.upperBound..<endRange.lowerBound])

            if let call = _parseSingleCall(callContent) {
                calls.append(call)
            }

            remaining = String(remaining[endRange.upperBound...])
        }

        return calls
    }

    /// Parse a single tool call:
    /// `func_name:0<|tool_call_argument_begin|>{...}`
    /// or `functions.func_name:0<|tool_call_argument_begin|>{...}`
    private func _parseSingleCall(_ content: String) -> ParsedToolCall? {
        // Split on argument begin token
        guard let argRange = content.range(of: Self.argBeginToken) else {
            // No arguments marker - just a function name
            let funcName = _cleanFuncName(content.trimmingCharacters(in: .whitespacesAndNewlines))
            guard !funcName.isEmpty else { return nil }
            return ParsedToolCall(name: funcName, argumentsJSON: "{}")
        }

        let rawFuncId = String(content[content.startIndex..<argRange.lowerBound])
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let argsStr = String(content[argRange.upperBound...])
            .trimmingCharacters(in: .whitespacesAndNewlines)

        let funcName = _cleanFuncName(rawFuncId)
        guard !funcName.isEmpty else { return nil }

        // Validate JSON if present
        if !argsStr.isEmpty,
           let data = argsStr.data(using: .utf8),
           let _ = try? JSONSerialization.jsonObject(with: data) {
            return ParsedToolCall(name: funcName, argumentsJSON: argsStr)
        }

        return ParsedToolCall(name: funcName, argumentsJSON: argsStr.isEmpty ? "{}" : argsStr)
    }

    /// Clean function name: strip `:N` call index and `functions.` prefix.
    private func _cleanFuncName(_ raw: String) -> String {
        var name = raw

        // Strip trailing :N call index
        if let colonRange = name.range(of: ":", options: .backwards) {
            let afterColon = String(name[colonRange.upperBound...])
            if afterColon.allSatisfy(\.isNumber) {
                name = String(name[name.startIndex..<colonRange.lowerBound])
            }
        }

        // Strip functions. prefix
        if name.hasPrefix("functions.") {
            name = String(name.dropFirst("functions.".count))
        }

        // Take the last component if there are dots
        if let lastDot = name.lastIndex(of: ".") {
            name = String(name[name.index(after: lastDot)...])
        }

        return name.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
