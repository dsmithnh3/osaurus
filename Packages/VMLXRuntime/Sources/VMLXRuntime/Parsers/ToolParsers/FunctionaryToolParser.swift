import Foundation

/// Tool call parser for MeetKai Functionary models.
///
/// Supports multiple Functionary tool call formats:
///
/// **Functionary v3 (recipient format):**
/// ```
/// <|from|>assistant
/// <|recipient|>get_weather
/// <|content|>{"city": "Paris"}
/// ```
///
/// **Function tag format:**
/// ```
/// <function=get_weather>{"city": "Paris"}</function>
/// ```
///
/// **JSON array format (OpenAI-like):**
/// ```
/// [{"name": "get_weather", "arguments": {"city": "Paris"}}]
/// ```
public struct FunctionaryToolParser: ToolCallParser {

    public static var supportedModels: [String] { ["functionary", "meetkai"] }

    private var buffer: String = ""

    public init() {}

    public mutating func processChunk(_ text: String) -> [ToolParserResult] {
        buffer += text

        // Check for any marker that indicates tool calls might be forming
        let markers = ["<|recipient|>", "<function=", "<|from|>"]
        let hasMarker = markers.contains { buffer.contains($0) }

        if !hasMarker {
            // Check for JSON array start
            let trimmed = buffer.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.hasPrefix("[") {
                // Could be a JSON array tool call, keep buffering
                // Try to parse as complete JSON
                if let calls = _tryParseJSONArray(trimmed), !calls.isEmpty {
                    buffer = ""
                    return calls.map { .toolCall($0) }
                }
                return [.buffered]
            }

            // No markers, emit as text
            let output = buffer
            buffer = ""
            return [.text(output)]
        }

        // Has a marker — try to extract complete tool calls
        var results: [ToolParserResult] = []

        // Try recipient pattern first (Functionary v3)
        let recipientCalls = _extractRecipientCalls(&buffer)
        for call in recipientCalls {
            results.append(.toolCall(call))
        }

        // Try function tag pattern
        let functionCalls = _extractFunctionTagCalls(&buffer)
        for call in functionCalls {
            results.append(.toolCall(call))
        }

        if !results.isEmpty {
            // Emit any remaining text
            let remaining = buffer.trimmingCharacters(in: .whitespacesAndNewlines)
            if !remaining.isEmpty {
                // Strip assistant markers
                let cleaned = remaining
                    .replacingOccurrences(of: "<|from|>assistant", with: "")
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                if !cleaned.isEmpty {
                    results.insert(.text(cleaned), at: 0)
                }
            }
            buffer = ""
            return results
        }

        // Markers present but no complete tool call yet — keep buffering
        return [.buffered]
    }

    public mutating func finalize() -> [ParsedToolCall] {
        guard !buffer.isEmpty else { return [] }

        let fullText = buffer
        buffer = ""

        var calls: [ParsedToolCall] = []

        // Try recipient pattern
        var remaining = fullText
        calls.append(contentsOf: _extractRecipientCalls(&remaining))

        // Try function tag pattern
        calls.append(contentsOf: _extractFunctionTagCalls(&remaining))

        // Try JSON array (trim whitespace for clean matching)
        if calls.isEmpty {
            let trimmed = remaining.trimmingCharacters(in: .whitespacesAndNewlines)
            if let arrayCalls = _tryParseJSONArray(trimmed) {
                calls.append(contentsOf: arrayCalls)
            }
        }

        return calls
    }

    public mutating func reset() {
        buffer = ""
    }

    // MARK: - Private: Recipient Pattern (Functionary v3)

    /// Extract `<|recipient|>func_name\n<|content|>{...}` patterns.
    private func _extractRecipientCalls(_ text: inout String) -> [ParsedToolCall] {
        var calls: [ParsedToolCall] = []
        var searchText = text

        while let recipientRange = searchText.range(of: "<|recipient|>") {
            let afterRecipient = searchText[recipientRange.upperBound...]

            // Find function name (up to newline or <|content|>)
            let funcEnd: String.Index
            if let newline = afterRecipient.firstIndex(of: "\n") {
                funcEnd = newline
            } else if let contentTag = afterRecipient.range(of: "<|content|>") {
                funcEnd = contentTag.lowerBound
            } else {
                break
            }

            let funcName = String(afterRecipient[afterRecipient.startIndex..<funcEnd])
                .trimmingCharacters(in: .whitespacesAndNewlines)

            // Skip non-function recipients
            let skipRecipients = ["all", "user"]
            if skipRecipients.contains(funcName.lowercased()) {
                searchText = String(searchText[funcEnd...])
                continue
            }

            // Find content
            let afterFuncName = searchText[funcEnd...]
            guard let contentRange = afterFuncName.range(of: "<|content|>") else { break }

            let contentStart = contentRange.upperBound
            // Content goes until next <| tag or end of text
            let contentEnd: String.Index
            if let nextTag = searchText.range(of: "<|", range: contentStart..<searchText.endIndex) {
                contentEnd = nextTag.lowerBound
            } else {
                contentEnd = searchText.endIndex
            }

            let argsStr = String(searchText[contentStart..<contentEnd])
                .trimmingCharacters(in: .whitespacesAndNewlines)

            // Validate JSON (or pass through)
            let finalArgs: String
            if let data = argsStr.data(using: .utf8),
               let _ = try? JSONSerialization.jsonObject(with: data) {
                finalArgs = argsStr
            } else {
                finalArgs = argsStr.isEmpty ? "{}" : argsStr
            }

            calls.append(ParsedToolCall(name: funcName, argumentsJSON: finalArgs))
            searchText = String(searchText[contentEnd...])
        }

        if !calls.isEmpty {
            text = searchText
        }
        return calls
    }

    // MARK: - Private: Function Tag Pattern

    /// Extract `<function=name>{...}</function>` patterns.
    private func _extractFunctionTagCalls(_ text: inout String) -> [ParsedToolCall] {
        var calls: [ParsedToolCall] = []
        var searchText = text

        while let funcStart = searchText.range(of: "<function=") {
            let afterFuncStart = searchText[funcStart.upperBound...]
            guard let nameEnd = afterFuncStart.firstIndex(of: ">") else { break }
            let funcName = String(afterFuncStart[afterFuncStart.startIndex..<nameEnd])
                .trimmingCharacters(in: .whitespaces)

            let contentStart = searchText.index(after: nameEnd)
            guard let funcClose = searchText.range(of: "</function>", range: contentStart..<searchText.endIndex) else { break }

            let argsStr = String(searchText[contentStart..<funcClose.lowerBound])
                .trimmingCharacters(in: .whitespacesAndNewlines)

            // Validate JSON
            let finalArgs: String
            if let data = argsStr.data(using: .utf8),
               let _ = try? JSONSerialization.jsonObject(with: data) {
                finalArgs = argsStr
            } else {
                finalArgs = argsStr.isEmpty ? "{}" : argsStr
            }

            calls.append(ParsedToolCall(name: funcName, argumentsJSON: finalArgs))
            searchText = String(searchText[funcClose.upperBound...])
        }

        if !calls.isEmpty {
            text = searchText
        }
        return calls
    }

    // MARK: - Private: JSON Array Pattern

    /// Try to parse text as a JSON array of tool calls.
    /// Format: `[{"name": "func", "arguments": {...}}, ...]`
    private func _tryParseJSONArray(_ text: String) -> [ParsedToolCall]? {
        guard text.hasPrefix("["), text.hasSuffix("]") else { return nil }

        guard let data = text.data(using: .utf8),
              let parsed = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
            return nil
        }

        var calls: [ParsedToolCall] = []
        for item in parsed {
            guard let name = item["name"] as? String else { continue }

            let argsJSON: String
            if let argsDict = item["arguments"] as? [String: Any],
               let argsData = try? JSONSerialization.data(withJSONObject: argsDict),
               let argsStr = String(data: argsData, encoding: .utf8) {
                argsJSON = argsStr
            } else if let argsStr = item["arguments"] as? String {
                argsJSON = argsStr
            } else {
                argsJSON = "{}"
            }

            let id = item["id"] as? String ?? ""
            calls.append(ParsedToolCall(name: name, argumentsJSON: argsJSON, id: id))
        }

        return calls.isEmpty ? nil : calls
    }
}
