import Foundation

/// Tool call parser for Salesforce xLAM models.
///
/// Supports multiple xLAM tool call output formats:
/// - JSON array: `[{"name": "func", "arguments": {...}}]`
/// - Markdown code blocks: `` ```json [...] ``` ``
/// - After thinking: `</think>[...]`
/// - `[TOOL_CALLS]` marker followed by JSON array
public struct XLAMToolParser: ToolCallParser {

    public static var supportedModels: [String] { ["xlam"] }

    private var buffer: String = ""

    public init() {}

    public mutating func processChunk(_ text: String) -> [ToolParserResult] {
        buffer += text

        // Check for markers indicating tool calls might be present
        let markers = ["```", "[TOOL_CALLS]", "</think>"]
        let hasMarker = markers.contains { buffer.contains($0) }

        // Also check for JSON array start
        let trimmed = buffer.trimmingCharacters(in: .whitespacesAndNewlines)
        let looksLikeJSONArray = trimmed.hasPrefix("[") && trimmed.contains("{")

        if !hasMarker && !looksLikeJSONArray {
            let output = buffer
            buffer = ""
            return [.text(output)]
        }

        // Try to extract complete tool calls
        if let (content, calls) = _tryExtractJSON(buffer), !calls.isEmpty {
            buffer = ""
            var results: [ToolParserResult] = []
            if let content = content, !content.isEmpty {
                results.append(.text(content))
            }
            for call in calls {
                results.append(.toolCall(call))
            }
            return results
        }

        // Still accumulating
        return [.buffered]
    }

    public mutating func finalize() -> [ParsedToolCall] {
        guard !buffer.isEmpty else { return [] }

        let text = buffer
        buffer = ""

        if let (_, calls) = _tryExtractJSON(text), !calls.isEmpty {
            return calls
        }

        return []
    }

    public mutating func reset() {
        buffer = ""
    }

    // MARK: - Private

    /// Try to extract tool calls as a JSON array from various formats.
    private func _tryExtractJSON(_ text: String) -> (String?, [ParsedToolCall])? {
        // 1. Try markdown code blocks: ```json [...] ```
        if let codeBlockRange = text.range(of: "```json"),
           let codeBlockEnd = text.range(of: "```", range: codeBlockRange.upperBound..<text.endIndex) {
            let jsonStr = String(text[codeBlockRange.upperBound..<codeBlockEnd.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines)
            if let calls = _parseJSONArray(jsonStr), !calls.isEmpty {
                let before = String(text[text.startIndex..<codeBlockRange.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines)
                return (before.isEmpty ? nil : before, calls)
            }
        }

        // Also try ``` without json specifier
        if let codeBlockRange = text.range(of: "```"),
           let codeBlockEnd = text.range(of: "```", range: codeBlockRange.upperBound..<text.endIndex) {
            let jsonStr = String(text[codeBlockRange.upperBound..<codeBlockEnd.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines)
            if let calls = _parseJSONArray(jsonStr), !calls.isEmpty {
                let before = String(text[text.startIndex..<codeBlockRange.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines)
                return (before.isEmpty ? nil : before, calls)
            }
        }

        // 2. Try [TOOL_CALLS] marker
        if let markerRange = text.range(of: "[TOOL_CALLS]") {
            let afterMarker = String(text[markerRange.upperBound...]).trimmingCharacters(in: .whitespacesAndNewlines)
            if let calls = _parseJSONArray(afterMarker), !calls.isEmpty {
                let before = String(text[text.startIndex..<markerRange.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines)
                return (before.isEmpty ? nil : before, calls)
            }
        }

        // 3. Try after </think> tag
        if let thinkEnd = text.range(of: "</think>") {
            let afterThink = String(text[thinkEnd.upperBound...]).trimmingCharacters(in: .whitespacesAndNewlines)
            if let calls = _parseJSONArray(afterThink), !calls.isEmpty {
                return (nil, calls)
            }
        }

        // 4. Try entire text as JSON array
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.hasPrefix("[") {
            if let calls = _parseJSONArray(trimmed), !calls.isEmpty {
                return (nil, calls)
            }
        }

        return nil
    }

    /// Parse a JSON array of tool call objects.
    private func _parseJSONArray(_ text: String) -> [ParsedToolCall]? {
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
            } else if let paramsDict = item["parameters"] as? [String: Any],
                      let paramsData = try? JSONSerialization.data(withJSONObject: paramsDict),
                      let paramsStr = String(data: paramsData, encoding: .utf8) {
                argsJSON = paramsStr
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
