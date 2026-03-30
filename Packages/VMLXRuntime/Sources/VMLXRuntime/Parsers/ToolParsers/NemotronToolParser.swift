import Foundation

/// Tool call parser for NVIDIA Nemotron models.
///
/// Supports Nemotron's XML-based tool call format:
/// ```
/// <tool_call><function=get_weather><parameter=city>Paris</parameter></function></tool_call>
/// ```
///
/// Also supports JSON arguments inside function tags:
/// ```
/// <tool_call><function=get_weather>{"city": "Paris"}</function></tool_call>
/// ```
public struct NemotronToolParser: ToolCallParser {

    public static var supportedModels: [String] { ["nemotron"] }

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

                    if let calls = _parseNemotronInner(inner) {
                        for call in calls {
                            results.append(.toolCall(call))
                        }
                    } else {
                        // Not valid, emit as text
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
    /// Expected format: `<function=name><parameter=p>v</parameter></function>`
    /// or `<function=name>{"json": "args"}</function>`
    private func _parseNemotronInner(_ inner: String) -> [ParsedToolCall]? {
        var calls: [ParsedToolCall] = []
        var remaining = inner

        // Match <function=NAME>CONTENT</function> blocks
        while let funcStart = remaining.range(of: "<function=") {
            // Find the function name (up to >)
            let afterFuncStart = remaining[funcStart.upperBound...]
            guard let nameEnd = afterFuncStart.firstIndex(of: ">") else { break }
            let funcName = String(afterFuncStart[afterFuncStart.startIndex..<nameEnd])
                .trimmingCharacters(in: .whitespaces)

            let contentStart = remaining.index(after: nameEnd)

            // Find </function>
            guard let funcClose = remaining.range(of: "</function>", range: contentStart..<remaining.endIndex) else { break }
            let content = String(remaining[contentStart..<funcClose.lowerBound])
                .trimmingCharacters(in: .whitespacesAndNewlines)

            // Parse arguments
            let argsJSON = _parseNemotronArguments(content)
            calls.append(ParsedToolCall(name: funcName, argumentsJSON: argsJSON))

            remaining = String(remaining[funcClose.upperBound...])
        }

        return calls.isEmpty ? nil : calls
    }

    /// Parse Nemotron argument content — either JSON or `<parameter=name>value</parameter>` tags.
    private func _parseNemotronArguments(_ content: String) -> String {
        // Try JSON first
        if content.hasPrefix("{") {
            if let data = content.data(using: .utf8),
               let _ = try? JSONSerialization.jsonObject(with: data) {
                return content
            }
        }

        // Parse <parameter=name>value</parameter> tags
        var params: [String: Any] = [:]
        var remaining = content

        while let paramStart = remaining.range(of: "<parameter=") {
            let afterParamStart = remaining[paramStart.upperBound...]
            guard let nameEnd = afterParamStart.firstIndex(of: ">") else { break }
            let paramName = String(afterParamStart[afterParamStart.startIndex..<nameEnd])
                .trimmingCharacters(in: .whitespaces)

            let valueStart = remaining.index(after: nameEnd)
            guard let paramClose = remaining.range(of: "</parameter>", range: valueStart..<remaining.endIndex) else { break }
            let rawValue = String(remaining[valueStart..<paramClose.lowerBound])
                .trimmingCharacters(in: .whitespacesAndNewlines)

            // Try parsing value as JSON (for nested objects/arrays/numbers)
            if let data = rawValue.data(using: .utf8),
               let jsonValue = try? JSONSerialization.jsonObject(with: data) {
                params[paramName] = jsonValue
            } else {
                params[paramName] = rawValue
            }

            remaining = String(remaining[paramClose.upperBound...])
        }

        if params.isEmpty {
            return content.isEmpty ? "{}" : content
        }

        if let data = try? JSONSerialization.data(withJSONObject: params),
           let str = String(data: data, encoding: .utf8) {
            return str
        }
        return "{}"
    }

    private func _extractAllToolCalls(_ text: String) -> [ParsedToolCall] {
        var calls: [ParsedToolCall] = []
        var searchText = text

        while let openRange = searchText.range(of: Self.openTag),
              let closeRange = searchText.range(of: Self.closeTag, range: openRange.upperBound..<searchText.endIndex) {
            let inner = String(searchText[openRange.upperBound..<closeRange.lowerBound])
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if let parsed = _parseNemotronInner(inner) {
                calls.append(contentsOf: parsed)
            }
            searchText = String(searchText[closeRange.upperBound...])
        }
        return calls
    }
}
