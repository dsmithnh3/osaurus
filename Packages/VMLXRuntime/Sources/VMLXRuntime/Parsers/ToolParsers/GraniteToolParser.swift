import Foundation

/// Tool call parser for IBM Granite models.
///
/// Supports Granite's tool call formats:
/// - Token tag style: `<|tool_call|>[{"name": "func", "arguments": {...}}]`
/// - Plain XML style: `<tool_call>[{"name": "func", "arguments": {...}}]`
///
/// Granite emits a JSON array (not a single object) after the marker tag.
/// Each element is `{"name": "func_name", "arguments": {...}}` or uses
/// `"type"` as an alias for `"name"`.
public struct GraniteToolParser: ToolCallParser {

    public static var supportedModels: [String] { ["granite"] }

    private var buffer: String = ""
    private var state: State = .text

    private enum State {
        case text
        case potentialTag       // Accumulating what might be a marker tag
        case inToolCall         // After marker, accumulating JSON array
    }

    /// Granite 3.0 uses `<|tool_call|>`, Granite 3.1+ uses `<tool_call>`.
    private static let botToken = "<|tool_call|>"
    private static let botString = "<tool_call>"

    public init() {}

    public mutating func processChunk(_ text: String) -> [ToolParserResult] {
        var results: [ToolParserResult] = []
        buffer += text

        while !buffer.isEmpty {
            switch state {
            case .text:
                // Check for <|tool_call|> marker
                if let tokenRange = buffer.range(of: Self.botToken) {
                    let prefix = String(buffer[buffer.startIndex..<tokenRange.lowerBound])
                    if !prefix.isEmpty {
                        results.append(.text(prefix))
                    }
                    buffer = String(buffer[tokenRange.upperBound...])
                    state = .inToolCall
                    continue
                }

                // Check for <tool_call> marker
                if let stringRange = buffer.range(of: Self.botString) {
                    let prefix = String(buffer[buffer.startIndex..<stringRange.lowerBound])
                    if !prefix.isEmpty {
                        results.append(.text(prefix))
                    }
                    buffer = String(buffer[stringRange.upperBound...])
                    state = .inToolCall
                    continue
                }

                // Check for potential partial tag at end of buffer
                if _hasPotentialTagPrefix(buffer) {
                    state = .potentialTag
                    results.append(.buffered)
                    return results
                }

                // No markers found, emit as text
                results.append(.text(buffer))
                buffer = ""

            case .potentialTag:
                if buffer.contains(Self.botToken) || buffer.contains(Self.botString) {
                    state = .text
                    continue
                } else if Self.botToken.hasPrefix(buffer) || Self.botString.hasPrefix(buffer) ||
                          _isPartialSuffixOf(buffer, target: Self.botToken) ||
                          _isPartialSuffixOf(buffer, target: Self.botString) {
                    results.append(.buffered)
                    return results
                } else {
                    state = .text
                    continue
                }

            case .inToolCall:
                // After the marker, Granite emits a JSON array: [{"name": ...}, ...]
                // Wait until we have a complete JSON array (balanced brackets).
                let trimmed = buffer.trimmingCharacters(in: .whitespacesAndNewlines)
                if trimmed.hasPrefix("[") && _isJSONArrayComplete(trimmed) {
                    // Try to parse the complete array
                    if let calls = _parseToolCallArray(trimmed) {
                        for call in calls {
                            results.append(.toolCall(call))
                        }
                        buffer = ""
                        state = .text
                    } else {
                        // Malformed JSON — emit as text
                        results.append(.text(buffer))
                        buffer = ""
                        state = .text
                    }
                } else if !trimmed.hasPrefix("[") && !trimmed.isEmpty {
                    // Not a JSON array — try single JSON object fallback
                    if trimmed.hasPrefix("{") && _isJSONObjectComplete(trimmed) {
                        if let call = _parseSingleToolCall(trimmed) {
                            results.append(.toolCall(call))
                            buffer = ""
                            state = .text
                        } else {
                            results.append(.text(buffer))
                            buffer = ""
                            state = .text
                        }
                    } else if trimmed.hasPrefix("{") {
                        // Partial JSON object
                        results.append(.buffered)
                        return results
                    } else {
                        // Not JSON at all
                        results.append(.text(buffer))
                        buffer = ""
                        state = .text
                    }
                } else {
                    // Still accumulating
                    results.append(.buffered)
                    return results
                }
            }
        }

        return results
    }

    public mutating func finalize() -> [ParsedToolCall] {
        guard !buffer.isEmpty else { return [] }

        let fullText = buffer
        buffer = ""
        state = .text

        return _extractAllToolCalls(fullText)
    }

    public mutating func reset() {
        buffer = ""
        state = .text
    }

    // MARK: - Private

    private func _hasPotentialTagPrefix(_ text: String) -> Bool {
        for tag in [Self.botToken, Self.botString] {
            for i in 1..<tag.count {
                let prefix = String(tag.prefix(i))
                if text.hasSuffix(prefix) { return true }
            }
        }
        return false
    }

    private func _isPartialSuffixOf(_ text: String, target: String) -> Bool {
        target.hasPrefix(text)
    }

    private func _isJSONArrayComplete(_ text: String) -> Bool {
        guard text.hasPrefix("[") else { return false }
        var depth = 0
        for char in text {
            if char == "[" { depth += 1 }
            if char == "]" { depth -= 1 }
            if depth == 0 { return true }
        }
        return false
    }

    private func _isJSONObjectComplete(_ text: String) -> Bool {
        guard text.hasPrefix("{") else { return false }
        var depth = 0
        for char in text {
            if char == "{" { depth += 1 }
            if char == "}" { depth -= 1 }
            if depth == 0 { return true }
        }
        return false
    }

    /// Parse a JSON array of tool calls: [{"name": "func", "arguments": {...}}, ...]
    private func _parseToolCallArray(_ json: String) -> [ParsedToolCall]? {
        guard let data = json.data(using: .utf8),
              let rawCalls = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
            return nil
        }

        var calls: [ParsedToolCall] = []
        for call in rawCalls {
            // Granite uses "name" or "type" for the function name
            guard let funcName = (call["name"] as? String) ?? (call["type"] as? String) else {
                continue
            }

            let argsJSON: String
            if let argsDict = call["arguments"] as? [String: Any],
               let argsData = try? JSONSerialization.data(withJSONObject: argsDict),
               let argsStr = String(data: argsData, encoding: .utf8) {
                argsJSON = argsStr
            } else if let argsStr = call["arguments"] as? String {
                argsJSON = argsStr
            } else {
                argsJSON = "{}"
            }

            let id = call["id"] as? String ?? ""
            calls.append(ParsedToolCall(name: funcName, argumentsJSON: argsJSON, id: id))
        }

        return calls.isEmpty ? nil : calls
    }

    /// Parse a single tool call JSON object (fallback for non-array format).
    private func _parseSingleToolCall(_ json: String) -> ParsedToolCall? {
        guard let data = json.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let name = (obj["name"] as? String) ?? (obj["type"] as? String) else {
            return nil
        }

        let argsJSON: String
        if let argsDict = obj["arguments"] as? [String: Any],
           let argsData = try? JSONSerialization.data(withJSONObject: argsDict),
           let argsStr = String(data: argsData, encoding: .utf8) {
            argsJSON = argsStr
        } else if let argsStr = obj["arguments"] as? String {
            argsJSON = argsStr
        } else {
            argsJSON = "{}"
        }

        let id = obj["id"] as? String ?? ""
        return ParsedToolCall(name: name, argumentsJSON: argsJSON, id: id)
    }

    /// Extract all tool calls from finalized text (handles both markers).
    private func _extractAllToolCalls(_ text: String) -> [ParsedToolCall] {
        var calls: [ParsedToolCall] = []

        // Strip leading marker if present
        var stripped = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if stripped.hasPrefix(Self.botToken) {
            stripped = String(stripped.dropFirst(Self.botToken.count))
                .trimmingCharacters(in: .whitespacesAndNewlines)
        } else if stripped.hasPrefix(Self.botString) {
            stripped = String(stripped.dropFirst(Self.botString.count))
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }

        // Try JSON array
        if stripped.hasPrefix("[") {
            if let parsed = _parseToolCallArray(stripped) {
                calls.append(contentsOf: parsed)
            }
        }

        // Try single JSON object fallback
        if calls.isEmpty && stripped.hasPrefix("{") {
            if let call = _parseSingleToolCall(stripped) {
                calls.append(call)
            }
        }

        return calls
    }
}
