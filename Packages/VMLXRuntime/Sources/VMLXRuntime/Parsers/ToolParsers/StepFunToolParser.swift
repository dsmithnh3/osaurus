import Foundation

/// Tool call parser for StepFun Step-3.5 models.
///
/// Supports Step-3.5's XML tool call format (same as Nemotron but with type coercion):
/// ```
/// <tool_call>
///   <function=get_weather>
///     <parameter=city>Paris</parameter>
///     <parameter=temp>25</parameter>
///   </function>
/// </tool_call>
/// ```
///
/// Also supports JSON arguments inside function tags:
/// ```
/// <tool_call><function=get_weather>{"city": "Paris"}</function></tool_call>
/// ```
///
/// Features type coercion: string parameter values are converted to
/// `Int`, `Double`, or `Bool` when appropriate.
public struct StepFunToolParser: ToolCallParser {

    public static var supportedModels: [String] { ["stepfun", "step"] }

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

                    if let calls = _parseStepFunInner(inner) {
                        for call in calls {
                            results.append(.toolCall(call))
                        }
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

    /// Parse inner content of `<tool_call>...</tool_call>`.
    /// Expected: `<function=name><parameter=p>v</parameter></function>`
    /// or `<function=name>{"json": "args"}</function>`
    private func _parseStepFunInner(_ inner: String) -> [ParsedToolCall]? {
        var calls: [ParsedToolCall] = []
        var remaining = inner

        while let funcStart = remaining.range(of: "<function=") {
            let afterFuncStart = remaining[funcStart.upperBound...]
            guard let nameEnd = afterFuncStart.firstIndex(of: ">") else { break }
            let funcName = String(afterFuncStart[afterFuncStart.startIndex..<nameEnd])
                .trimmingCharacters(in: .whitespaces)

            let contentStart = remaining.index(after: nameEnd)
            guard let funcClose = remaining.range(of: "</function>", range: contentStart..<remaining.endIndex) else { break }
            let content = String(remaining[contentStart..<funcClose.lowerBound])
                .trimmingCharacters(in: .whitespacesAndNewlines)

            let argsJSON = _parseArguments(content)
            calls.append(ParsedToolCall(name: funcName, argumentsJSON: argsJSON))

            remaining = String(remaining[funcClose.upperBound...])
        }

        return calls.isEmpty ? nil : calls
    }

    /// Parse arguments from function content.
    /// First tries JSON, then falls back to `<parameter=name>value</parameter>` tags
    /// with type coercion.
    private func _parseArguments(_ content: String) -> String {
        // Try JSON first
        if content.hasPrefix("{") {
            if let data = content.data(using: .utf8),
               let _ = try? JSONSerialization.jsonObject(with: data) {
                return content
            }
        }

        // Parse <parameter=name>value</parameter> tags with type coercion
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

            // Type coercion: try Int, Double, Bool, JSON, then String
            params[paramName] = _coerceValue(rawValue)

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

    /// Coerce a string value to its natural type.
    private func _coerceValue(_ value: String) -> Any {
        // Try JSON first (handles arrays, objects, null, true, false, numbers)
        if let data = value.data(using: .utf8),
           let jsonValue = try? JSONSerialization.jsonObject(with: data) {
            return jsonValue
        }

        // Try Int
        if let intVal = Int(value) {
            return intVal
        }

        // Try Double
        if let doubleVal = Double(value) {
            return doubleVal
        }

        // Try Bool
        let lower = value.lowercased()
        if lower == "true" || lower == "yes" { return true }
        if lower == "false" || lower == "no" { return false }

        return value
    }

    private func _extractAllToolCalls(_ text: String) -> [ParsedToolCall] {
        var calls: [ParsedToolCall] = []
        var searchText = text

        while let openRange = searchText.range(of: Self.openTag),
              let closeRange = searchText.range(of: Self.closeTag, range: openRange.upperBound..<searchText.endIndex) {
            let inner = String(searchText[openRange.upperBound..<closeRange.lowerBound])
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if let parsed = _parseStepFunInner(inner) {
                calls.append(contentsOf: parsed)
            }
            searchText = String(searchText[closeRange.upperBound...])
        }
        return calls
    }
}
