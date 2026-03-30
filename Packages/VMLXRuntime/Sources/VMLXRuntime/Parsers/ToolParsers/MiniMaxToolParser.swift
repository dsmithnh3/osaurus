import Foundation

/// Tool call parser for MiniMax M2/M2.5 models.
///
/// Supports MiniMax's XML-based tool call format:
/// ```
/// <minimax:tool_call>
///   <invoke name="get_weather">
///     <parameter name="city">Paris</parameter>
///     <parameter name="unit">celsius</parameter>
///   </invoke>
/// </minimax:tool_call>
/// ```
///
/// Multiple invocations can appear in a single block.
/// Also supports fallback JSON format inside the block.
public struct MiniMaxToolParser: ToolCallParser {

    public static var supportedModels: [String] { ["minimax"] }

    private var buffer: String = ""
    private var state: State = .text

    private enum State {
        case text
        case potentialTag
        case inToolCall      // Between <minimax:tool_call> and </minimax:tool_call>
    }

    private static let openTag = "<minimax:tool_call>"
    private static let closeTag = "</minimax:tool_call>"

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

                    let calls = _parseInvokeBlocks(inner)
                    if !calls.isEmpty {
                        for call in calls {
                            results.append(.toolCall(call))
                        }
                    } else {
                        // Try JSON fallback inside the block
                        if let call = _parseJSONFallback(inner) {
                            results.append(.toolCall(call))
                        } else {
                            results.append(.text(Self.openTag + inner + Self.closeTag))
                        }
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

    /// Parse `<invoke name="func">...</invoke>` blocks from within a `<minimax:tool_call>` block.
    private func _parseInvokeBlocks(_ inner: String) -> [ParsedToolCall] {
        var calls: [ParsedToolCall] = []
        var remaining = inner

        while let invokeStart = remaining.range(of: "<invoke") {
            // Find the name attribute: name="..." or name='...' or name=...
            guard let nameRange = remaining.range(of: "name=", range: invokeStart.upperBound..<remaining.endIndex) else { break }
            let afterName = remaining[nameRange.upperBound...]

            // Extract the function name
            let funcName: String
            let afterFuncName: Substring

            if afterName.hasPrefix("\"") || afterName.hasPrefix("'") {
                let quote = afterName.first!
                let nameStart = afterName.index(after: afterName.startIndex)
                guard let nameEnd = afterName[nameStart...].firstIndex(of: quote) else { break }
                funcName = String(afterName[nameStart..<nameEnd])
                afterFuncName = afterName[afterName.index(after: nameEnd)...]
            } else {
                // Unquoted name (up to > or whitespace)
                let nameStart = afterName.startIndex
                let nameEnd = afterName.firstIndex(where: { $0 == ">" || $0.isWhitespace }) ?? afterName.endIndex
                funcName = String(afterName[nameStart..<nameEnd])
                afterFuncName = afterName[nameEnd...]
            }

            // Find the closing > of the invoke tag
            guard let invokeClose = afterFuncName.firstIndex(of: ">") else { break }
            let contentStart = remaining.index(after: invokeClose)

            // Find </invoke>
            guard let invokeEndRange = remaining.range(of: "</invoke>", range: contentStart..<remaining.endIndex) else { break }
            let invokeContent = String(remaining[contentStart..<invokeEndRange.lowerBound])

            // Parse <parameter name="key">value</parameter> tags
            let params = _parseParameters(invokeContent)

            let argsJSON: String
            if !params.isEmpty {
                if let data = try? JSONSerialization.data(withJSONObject: params),
                   let str = String(data: data, encoding: .utf8) {
                    argsJSON = str
                } else {
                    argsJSON = "{}"
                }
            } else {
                // Try parsing content as raw JSON
                let trimmedContent = invokeContent.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmedContent.isEmpty,
                   let data = trimmedContent.data(using: .utf8),
                   let _ = try? JSONSerialization.jsonObject(with: data) {
                    argsJSON = trimmedContent
                } else {
                    argsJSON = "{}"
                }
            }

            calls.append(ParsedToolCall(name: funcName, argumentsJSON: argsJSON))
            remaining = String(remaining[invokeEndRange.upperBound...])
        }

        return calls
    }

    /// Parse `<parameter name="key">value</parameter>` tags.
    private func _parseParameters(_ content: String) -> [String: Any] {
        var params: [String: Any] = [:]
        var remaining = content

        while let paramStart = remaining.range(of: "<parameter") {
            guard let nameRange = remaining.range(of: "name=", range: paramStart.upperBound..<remaining.endIndex) else { break }
            let afterName = remaining[nameRange.upperBound...]

            // Extract parameter name
            let paramName: String
            let afterParamName: Substring

            if afterName.hasPrefix("\"") || afterName.hasPrefix("'") {
                let quote = afterName.first!
                let start = afterName.index(after: afterName.startIndex)
                guard let end = afterName[start...].firstIndex(of: quote) else { break }
                paramName = String(afterName[start..<end])
                afterParamName = afterName[afterName.index(after: end)...]
            } else {
                let start = afterName.startIndex
                let end = afterName.firstIndex(where: { $0 == ">" || $0.isWhitespace }) ?? afterName.endIndex
                paramName = String(afterName[start..<end])
                afterParamName = afterName[end...]
            }

            // Find > closing the parameter tag
            guard let closeAngle = afterParamName.firstIndex(of: ">") else { break }
            let valueStart = remaining.index(after: closeAngle)

            // Find </parameter>
            guard let paramEnd = remaining.range(of: "</parameter>", range: valueStart..<remaining.endIndex) else { break }
            let rawValue = String(remaining[valueStart..<paramEnd.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines)

            // Try JSON parsing for typed values
            if let data = rawValue.data(using: .utf8),
               let jsonValue = try? JSONSerialization.jsonObject(with: data) {
                params[paramName] = jsonValue
            } else {
                params[paramName] = rawValue
            }

            remaining = String(remaining[paramEnd.upperBound...])
        }

        return params
    }

    /// Fallback: try parsing the block content as a JSON object with name/arguments.
    private func _parseJSONFallback(_ content: String) -> ParsedToolCall? {
        let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let data = trimmed.data(using: .utf8),
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
        } else {
            argsJSON = "{}"
        }

        return ParsedToolCall(name: name, argumentsJSON: argsJSON)
    }

    private func _extractAllToolCalls(_ text: String) -> [ParsedToolCall] {
        var calls: [ParsedToolCall] = []
        var searchText = text

        while let openRange = searchText.range(of: Self.openTag),
              let closeRange = searchText.range(of: Self.closeTag, range: openRange.upperBound..<searchText.endIndex) {
            let inner = String(searchText[openRange.upperBound..<closeRange.lowerBound])
                .trimmingCharacters(in: .whitespacesAndNewlines)
            let parsed = _parseInvokeBlocks(inner)
            if !parsed.isEmpty {
                calls.append(contentsOf: parsed)
            } else if let fallback = _parseJSONFallback(inner) {
                calls.append(fallback)
            }
            searchText = String(searchText[closeRange.upperBound...])
        }
        return calls
    }
}
