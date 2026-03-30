import Foundation

/// Tool call parser for GLM-4.7 and GLM-4 models.
///
/// Supports two GLM tool call formats:
///
/// **XML arg format (GLM-4.7 native):**
/// ```
/// <tool_call>get_weather
/// <arg_key>city</arg_key><arg_value>Paris</arg_value>
/// </tool_call>
/// ```
///
/// **JSON format (Harmony/GPT-OSS variant):**
/// ```
/// <tool_call>{"name": "get_weather", "arguments": {"city": "Paris"}}</tool_call>
/// ```
public struct GLMToolParser: ToolCallParser {

    public static var supportedModels: [String] { ["glm"] }

    private var buffer: String = ""
    private var state: State = .text

    private enum State {
        case text
        case potentialTag
        case inToolCall      // Between <tool_call> and </tool_call>
    }

    private static let openTag = "<tool_call>"
    private static let closeTag = "</tool_call>"

    public init() {}

    public mutating func processChunk(_ text: String) -> [ToolParserResult] {
        var results: [ToolParserResult] = []
        buffer += text

        while !buffer.isEmpty {
            switch state {
            case .text:
                if let tagRange = buffer.range(of: Self.openTag) {
                    let prefix = String(buffer[buffer.startIndex..<tagRange.lowerBound])
                    if !prefix.isEmpty {
                        results.append(.text(prefix))
                    }
                    buffer = String(buffer[tagRange.upperBound...])
                    state = .inToolCall
                } else if _hasPotentialTagPrefix(buffer) {
                    state = .potentialTag
                    results.append(.buffered)
                    return results
                } else {
                    results.append(.text(buffer))
                    buffer = ""
                }

            case .potentialTag:
                if buffer.hasPrefix(Self.openTag) || buffer.contains(Self.openTag) {
                    state = .text
                    continue
                } else if Self.openTag.hasPrefix(buffer) {
                    results.append(.buffered)
                    return results
                } else {
                    state = .text
                    continue
                }

            case .inToolCall:
                if let closeRange = buffer.range(of: Self.closeTag) {
                    let inner = String(buffer[buffer.startIndex..<closeRange.lowerBound])
                        .trimmingCharacters(in: .whitespacesAndNewlines)
                    buffer = String(buffer[closeRange.upperBound...])
                    state = .text

                    if let call = _parseGLMInner(inner) {
                        results.append(.toolCall(call))
                    } else {
                        results.append(.text(Self.openTag + inner + Self.closeTag))
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
        for i in 1..<Self.openTag.count {
            let prefix = String(Self.openTag.prefix(i))
            if text.hasSuffix(prefix) { return true }
        }
        return false
    }

    /// Parse the inner content of a `<tool_call>...</tool_call>` block.
    ///
    /// GLM-4.7 XML arg format:
    /// ```
    /// func_name
    /// <arg_key>param</arg_key><arg_value>value</arg_value>
    /// ```
    ///
    /// JSON format:
    /// ```
    /// {"name": "func", "arguments": {...}}
    /// ```
    private func _parseGLMInner(_ inner: String) -> ParsedToolCall? {
        let trimmed = inner.trimmingCharacters(in: .whitespacesAndNewlines)

        // Try JSON format first
        if trimmed.hasPrefix("{") {
            return _parseJSONToolCall(trimmed)
        }

        // GLM-4.7 XML arg format: func_name\n<arg_key>...</arg_key><arg_value>...</arg_value>
        return _parseXMLArgFormat(trimmed)
    }

    /// Parse JSON-format tool call: `{"name": "func", "arguments": {...}}`
    private func _parseJSONToolCall(_ json: String) -> ParsedToolCall? {
        guard let data = json.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let name = obj["name"] as? String else {
            return nil
        }

        let argsJSON: String
        if let argsDict = obj["arguments"] as? [String: Any],
           let argsData = try? JSONSerialization.data(withJSONObject: argsDict),
           let argsStr = String(data: argsData, encoding: .utf8) {
            argsJSON = argsStr
        } else if let paramsDict = obj["parameters"] as? [String: Any],
                  let paramsData = try? JSONSerialization.data(withJSONObject: paramsDict),
                  let paramsStr = String(data: paramsData, encoding: .utf8) {
            argsJSON = paramsStr
        } else if let argsStr = obj["arguments"] as? String {
            argsJSON = argsStr
        } else {
            argsJSON = "{}"
        }

        return ParsedToolCall(name: name, argumentsJSON: argsJSON)
    }

    /// Parse GLM-4.7 XML arg format:
    /// ```
    /// func_name
    /// <arg_key>param</arg_key><arg_value>value</arg_value>
    /// ```
    private func _parseXMLArgFormat(_ text: String) -> ParsedToolCall? {
        let lines = text.components(separatedBy: "\n")
        guard !lines.isEmpty else { return nil }

        let funcName = lines[0].trimmingCharacters(in: .whitespacesAndNewlines)
        guard !funcName.isEmpty, !funcName.hasPrefix("<") else { return nil }

        // Parse <arg_key>...</arg_key><arg_value>...</arg_value> pairs
        var params: [String: Any] = [:]
        let rest = lines.dropFirst().joined(separator: "\n")
        var remaining = rest

        while let keyStart = remaining.range(of: "<arg_key>") {
            guard let keyEnd = remaining.range(of: "</arg_key>", range: keyStart.upperBound..<remaining.endIndex) else { break }
            let key = String(remaining[keyStart.upperBound..<keyEnd.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines)

            let afterKey = remaining[keyEnd.upperBound...]
            guard let valStart = afterKey.range(of: "<arg_value>") else { break }
            guard let valEnd = afterKey.range(of: "</arg_value>", range: valStart.upperBound..<afterKey.endIndex) else { break }
            let rawValue = String(afterKey[valStart.upperBound..<valEnd.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines)

            // Try parsing value as JSON for nested types
            if let data = rawValue.data(using: .utf8),
               let jsonValue = try? JSONSerialization.jsonObject(with: data) {
                params[key] = jsonValue
            } else {
                params[key] = rawValue
            }

            remaining = String(afterKey[valEnd.upperBound...])
        }

        let argsJSON: String
        if params.isEmpty {
            argsJSON = "{}"
        } else if let data = try? JSONSerialization.data(withJSONObject: params),
                  let str = String(data: data, encoding: .utf8) {
            argsJSON = str
        } else {
            argsJSON = "{}"
        }

        return ParsedToolCall(name: funcName, argumentsJSON: argsJSON)
    }

    private func _extractAllToolCalls(_ text: String) -> [ParsedToolCall] {
        var calls: [ParsedToolCall] = []
        var searchText = text

        while let openRange = searchText.range(of: Self.openTag),
              let closeRange = searchText.range(of: Self.closeTag, range: openRange.upperBound..<searchText.endIndex) {
            let inner = String(searchText[openRange.upperBound..<closeRange.lowerBound])
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if let call = _parseGLMInner(inner) {
                calls.append(call)
            }
            searchText = String(searchText[closeRange.upperBound...])
        }
        return calls
    }
}
