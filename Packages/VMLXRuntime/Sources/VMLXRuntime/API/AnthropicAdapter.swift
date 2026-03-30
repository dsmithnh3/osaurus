import Foundation

// MARK: - Anthropic Messages API Types

/// Anthropic Messages API request format.
///
/// Key differences from OpenAI:
/// - `system` is a separate top-level field, not a message
/// - `thinking` is `{"type": "enabled", "budget_tokens": N}` instead of `enable_thinking: true`
/// - `max_tokens` is required
/// - Response uses content blocks with types: "text", "thinking", "tool_use", "tool_result"
public struct AnthropicMessagesRequest: Sendable, Codable {
    public let model: String?
    public let maxTokens: Int
    public let system: AnthropicSystemContent?
    public let messages: [AnthropicMessage]
    public let tools: [AnthropicTool]?
    public let toolChoice: AnthropicToolChoice?
    public let thinking: AnthropicThinkingConfig?
    public let stream: Bool?
    public let temperature: Float?
    public let topP: Float?
    public let stopSequences: [String]?

    enum CodingKeys: String, CodingKey {
        case model
        case maxTokens = "max_tokens"
        case system, messages, tools
        case toolChoice = "tool_choice"
        case thinking, stream, temperature
        case topP = "top_p"
        case stopSequences = "stop_sequences"
    }

    public init(
        model: String? = nil,
        maxTokens: Int = 1024,
        system: AnthropicSystemContent? = nil,
        messages: [AnthropicMessage] = [],
        tools: [AnthropicTool]? = nil,
        toolChoice: AnthropicToolChoice? = nil,
        thinking: AnthropicThinkingConfig? = nil,
        stream: Bool? = nil,
        temperature: Float? = nil,
        topP: Float? = nil,
        stopSequences: [String]? = nil
    ) {
        self.model = model
        self.maxTokens = maxTokens
        self.system = system
        self.messages = messages
        self.tools = tools
        self.toolChoice = toolChoice
        self.thinking = thinking
        self.stream = stream
        self.temperature = temperature
        self.topP = topP
        self.stopSequences = stopSequences
    }
}

/// Anthropic system content -- can be a string or array of content blocks.
public enum AnthropicSystemContent: Sendable, Codable {
    case text(String)
    case blocks([AnthropicContentBlock])

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let text = try? container.decode(String.self) {
            self = .text(text)
        } else {
            let blocks = try container.decode([AnthropicContentBlock].self)
            self = .blocks(blocks)
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .text(let text):
            try container.encode(text)
        case .blocks(let blocks):
            try container.encode(blocks)
        }
    }

    /// Extract the text content regardless of format.
    public var textValue: String {
        switch self {
        case .text(let text):
            return text
        case .blocks(let blocks):
            return blocks.compactMap { block -> String? in
                if case .text(let text) = block.content { return text }
                return nil
            }.joined(separator: "\n")
        }
    }
}

/// Anthropic message in the messages array.
public struct AnthropicMessage: Sendable, Codable {
    public let role: String
    public let content: AnthropicMessageContent

    public init(role: String, content: AnthropicMessageContent) {
        self.role = role
        self.content = content
    }
}

/// Anthropic message content -- string or array of content blocks.
public enum AnthropicMessageContent: Sendable, Codable {
    case text(String)
    case blocks([AnthropicContentBlock])

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let text = try? container.decode(String.self) {
            self = .text(text)
        } else {
            let blocks = try container.decode([AnthropicContentBlock].self)
            self = .blocks(blocks)
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .text(let text):
            try container.encode(text)
        case .blocks(let blocks):
            try container.encode(blocks)
        }
    }

    /// Extract text content.
    public var textValue: String {
        switch self {
        case .text(let text):
            return text
        case .blocks(let blocks):
            return blocks.compactMap { block -> String? in
                if case .text(let text) = block.content { return text }
                return nil
            }.joined()
        }
    }
}

/// A content block in Anthropic's format.
public struct AnthropicContentBlock: Sendable, Codable {
    public let type: String
    public let content: AnthropicBlockContent

    enum CodingKeys: String, CodingKey {
        case type, text, thinking, id, name, input
        case toolUseId = "tool_use_id"
    }

    public init(type: String, content: AnthropicBlockContent) {
        self.type = type
        self.content = content
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = try container.decode(String.self, forKey: .type)
        self.type = type

        switch type {
        case "text":
            let text = try container.decode(String.self, forKey: .text)
            self.content = .text(text)
        case "thinking":
            let thinking = try container.decode(String.self, forKey: .thinking)
            self.content = .thinking(thinking)
        case "tool_use":
            let id = try container.decode(String.self, forKey: .id)
            let name = try container.decode(String.self, forKey: .name)
            let input = try container.decode(AnyCodable.self, forKey: .input)
            self.content = .toolUse(id: id, name: name, input: input)
        case "tool_result":
            let toolUseId = try container.decode(String.self, forKey: .toolUseId)
            let text = try container.decodeIfPresent(String.self, forKey: .text) ?? ""
            self.content = .toolResult(toolUseId: toolUseId, content: text)
        default:
            let text = try container.decodeIfPresent(String.self, forKey: .text) ?? ""
            self.content = .text(text)
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(type, forKey: .type)

        switch content {
        case .text(let text):
            try container.encode(text, forKey: .text)
        case .thinking(let thinking):
            try container.encode(thinking, forKey: .thinking)
        case .toolUse(let id, let name, let input):
            try container.encode(id, forKey: .id)
            try container.encode(name, forKey: .name)
            try container.encode(input, forKey: .input)
        case .toolResult(let toolUseId, let content):
            try container.encode(toolUseId, forKey: .toolUseId)
            try container.encode(content, forKey: .text)
        }
    }
}

/// Content variants within an Anthropic content block.
public enum AnthropicBlockContent: Sendable {
    case text(String)
    case thinking(String)
    case toolUse(id: String, name: String, input: AnyCodable)
    case toolResult(toolUseId: String, content: String)
}

/// Type-erased Codable wrapper for arbitrary JSON values (tool inputs/outputs).
public struct AnyCodable: @unchecked Sendable, Codable {
    public let value: Any

    public init(_ value: Any) {
        self.value = value
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let dict = try? container.decode([String: AnyCodable].self) {
            value = dict.mapValues { $0.value }
        } else if let array = try? container.decode([AnyCodable].self) {
            value = array.map { $0.value }
        } else if let string = try? container.decode(String.self) {
            value = string
        } else if let int = try? container.decode(Int.self) {
            value = int
        } else if let double = try? container.decode(Double.self) {
            value = double
        } else if let bool = try? container.decode(Bool.self) {
            value = bool
        } else if container.decodeNil() {
            value = NSNull()
        } else {
            throw DecodingError.dataCorrupted(
                .init(codingPath: decoder.codingPath, debugDescription: "Unsupported type")
            )
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch value {
        case let string as String:
            try container.encode(string)
        case let int as Int:
            try container.encode(int)
        case let double as Double:
            try container.encode(double)
        case let bool as Bool:
            try container.encode(bool)
        case let dict as [String: Any]:
            try container.encode(dict.mapValues { AnyCodable($0) })
        case let array as [Any]:
            try container.encode(array.map { AnyCodable($0) })
        case is NSNull:
            try container.encodeNil()
        default:
            try container.encodeNil()
        }
    }
}

/// Anthropic thinking configuration.
public struct AnthropicThinkingConfig: Sendable, Codable {
    public let type: String      // "enabled" or "disabled"
    public let budgetTokens: Int?

    enum CodingKeys: String, CodingKey {
        case type
        case budgetTokens = "budget_tokens"
    }

    public var isEnabled: Bool { type == "enabled" }

    public init(type: String, budgetTokens: Int? = nil) {
        self.type = type
        self.budgetTokens = budgetTokens
    }
}

/// Anthropic tool definition.
public struct AnthropicTool: Sendable, Codable {
    public let name: String
    public let description: String?
    public let inputSchema: AnyCodable?

    enum CodingKeys: String, CodingKey {
        case name, description
        case inputSchema = "input_schema"
    }

    public init(name: String, description: String? = nil, inputSchema: AnyCodable? = nil) {
        self.name = name
        self.description = description
        self.inputSchema = inputSchema
    }
}

/// Anthropic tool choice configuration.
public struct AnthropicToolChoice: Sendable, Codable {
    public let type: String      // "auto", "any", or "tool"
    public let name: String?     // Only for type == "tool"

    public init(type: String, name: String? = nil) {
        self.type = type
        self.name = name
    }
}

// MARK: - Anthropic Response Types

/// Anthropic Messages API response.
public struct AnthropicMessagesResponse: Sendable, Codable {
    public let id: String
    public let type: String      // "message"
    public let role: String      // "assistant"
    public let content: [AnthropicContentBlock]
    public let model: String
    public let stopReason: String?
    public let usage: AnthropicUsage

    enum CodingKeys: String, CodingKey {
        case id, type, role, content, model
        case stopReason = "stop_reason"
        case usage
    }

    public init(
        id: String,
        content: [AnthropicContentBlock],
        model: String,
        stopReason: String? = nil,
        usage: AnthropicUsage
    ) {
        self.id = id
        self.type = "message"
        self.role = "assistant"
        self.content = content
        self.model = model
        self.stopReason = stopReason
        self.usage = usage
    }
}

/// Anthropic usage statistics.
public struct AnthropicUsage: Sendable, Codable {
    public let inputTokens: Int
    public let outputTokens: Int
    public let cacheReadInputTokens: Int?
    public let cacheCreationInputTokens: Int?

    enum CodingKeys: String, CodingKey {
        case inputTokens = "input_tokens"
        case outputTokens = "output_tokens"
        case cacheReadInputTokens = "cache_read_input_tokens"
        case cacheCreationInputTokens = "cache_creation_input_tokens"
    }

    public init(
        inputTokens: Int,
        outputTokens: Int,
        cacheReadInputTokens: Int? = nil,
        cacheCreationInputTokens: Int? = nil
    ) {
        self.inputTokens = inputTokens
        self.outputTokens = outputTokens
        self.cacheReadInputTokens = cacheReadInputTokens
        self.cacheCreationInputTokens = cacheCreationInputTokens
    }
}

// MARK: - AnthropicAdapter

/// Translates between Anthropic Messages API format and VMLXRuntime's
/// internal `VMLXChatCompletionRequest` / response types.
///
/// Key conversions:
/// - Anthropic `system` field -> system message prepended to messages array
/// - Anthropic `thinking.type: "enabled"` -> `enableThinking: true`
/// - Anthropic `thinking.budget_tokens` -> `reasoningEffort` mapping
/// - Anthropic tool definitions -> `VMLXToolDefinition` array
/// - Anthropic tool_use/tool_result content blocks -> tool call messages
/// - Anthropic response content blocks <- VMLXEvent stream
public struct AnthropicAdapter: Sendable {

    /// Convert an Anthropic Messages API request to a VMLXChatCompletionRequest.
    public static func toVMLXRequest(_ request: AnthropicMessagesRequest) -> VMLXChatCompletionRequest {
        var messages: [VMLXChatMessage] = []

        // 1. Convert system prompt to a system message
        if let system = request.system {
            messages.append(VMLXChatMessage(role: "system", content: system.textValue))
        }

        // 2. Convert Anthropic messages
        for msg in request.messages {
            switch msg.content {
            case .text(let text):
                messages.append(VMLXChatMessage(role: msg.role, content: text))

            case .blocks(let blocks):
                for block in blocks {
                    switch block.content {
                    case .text(let text):
                        messages.append(VMLXChatMessage(role: msg.role, content: text))

                    case .toolUse(let id, let name, let input):
                        // Assistant's tool invocation -> tool_calls on assistant message
                        let argsJSON: String
                        if let data = try? JSONEncoder().encode(input),
                           let jsonStr = String(data: data, encoding: .utf8) {
                            argsJSON = jsonStr
                        } else {
                            argsJSON = "{}"
                        }
                        let toolCall = VMLXToolCall(id: id, name: name, arguments: argsJSON)
                        messages.append(VMLXChatMessage(
                            role: "assistant",
                            toolCalls: [toolCall]
                        ))

                    case .toolResult(let toolUseId, let content):
                        // Tool result -> tool message with tool_call_id
                        messages.append(VMLXChatMessage(
                            role: "tool",
                            content: content,
                            toolCallId: toolUseId
                        ))

                    case .thinking:
                        // Thinking blocks are not passed back as input
                        break
                    }
                }
            }
        }

        // 3. Convert tools
        let tools: [VMLXToolDefinition]? = request.tools?.map { tool in
            VMLXToolDefinition(name: tool.name, description: tool.description)
        }

        // 4. Convert tool choice
        let toolChoice: String?
        if let tc = request.toolChoice {
            switch tc.type {
            case "auto": toolChoice = "auto"
            case "any": toolChoice = "auto"
            case "tool": toolChoice = tc.name
            default: toolChoice = nil
            }
        } else {
            toolChoice = nil
        }

        // 5. Convert thinking config
        let enableThinking = request.thinking?.isEnabled
        let reasoningEffort: String?
        if let budget = request.thinking?.budgetTokens {
            // Map budget tokens to effort level
            if budget <= 1000 {
                reasoningEffort = "low"
            } else if budget <= 5000 {
                reasoningEffort = "medium"
            } else {
                reasoningEffort = "high"
            }
        } else {
            reasoningEffort = nil
        }

        return VMLXChatCompletionRequest(
            messages: messages,
            model: request.model,
            temperature: request.temperature,
            maxTokens: request.maxTokens,
            topP: request.topP,
            stop: request.stopSequences,
            stream: request.stream ?? false,
            tools: tools,
            toolChoice: toolChoice,
            enableThinking: enableThinking,
            reasoningEffort: reasoningEffort
        )
    }

    /// Build an Anthropic Messages API response from generation results.
    ///
    /// - Parameters:
    ///   - text: Generated text content
    ///   - thinkingText: Generated thinking/reasoning content (if any)
    ///   - toolCalls: Tool invocations (if any)
    ///   - model: Model name
    ///   - promptTokens: Number of prompt tokens
    ///   - completionTokens: Number of completion tokens
    ///   - cachedTokens: Number of cached tokens
    ///   - finishReason: Why generation stopped
    /// - Returns: Anthropic-formatted response
    public static func toAnthropicResponse(
        text: String,
        thinkingText: String? = nil,
        toolCalls: [(name: String, id: String, argsJSON: String)] = [],
        model: String,
        promptTokens: Int,
        completionTokens: Int,
        cachedTokens: Int = 0,
        finishReason: FinishReason?
    ) -> AnthropicMessagesResponse {
        var contentBlocks: [AnthropicContentBlock] = []

        // Add thinking block first (if present)
        if let thinking = thinkingText, !thinking.isEmpty {
            contentBlocks.append(AnthropicContentBlock(
                type: "thinking",
                content: .thinking(thinking)
            ))
        }

        // Add text block
        if !text.isEmpty {
            contentBlocks.append(AnthropicContentBlock(
                type: "text",
                content: .text(text)
            ))
        }

        // Add tool_use blocks
        for call in toolCalls {
            let input: AnyCodable
            if let data = call.argsJSON.data(using: .utf8),
               let json = try? JSONSerialization.jsonObject(with: data) {
                input = AnyCodable(json)
            } else {
                input = AnyCodable([:] as [String: Any])
            }
            contentBlocks.append(AnthropicContentBlock(
                type: "tool_use",
                content: .toolUse(id: call.id, name: call.name, input: input)
            ))
        }

        // Map finish reason to Anthropic stop_reason
        let stopReason: String?
        switch finishReason {
        case .stop: stopReason = "end_turn"
        case .length: stopReason = "max_tokens"
        case .toolCalls: stopReason = "tool_use"
        case .abort: stopReason = "end_turn"
        case .none: stopReason = nil
        }

        return AnthropicMessagesResponse(
            id: "msg_\(UUID().uuidString.prefix(24))",
            content: contentBlocks,
            model: model,
            stopReason: stopReason,
            usage: AnthropicUsage(
                inputTokens: promptTokens,
                outputTokens: completionTokens,
                cacheReadInputTokens: cachedTokens > 0 ? cachedTokens : nil
            )
        )
    }

    /// Map an Anthropic stop_reason string to our internal FinishReason.
    public static func mapStopReason(_ stopReason: String?) -> FinishReason? {
        switch stopReason {
        case "end_turn": return .stop
        case "max_tokens": return .length
        case "tool_use": return .toolCalls
        case "stop_sequence": return .stop
        default: return nil
        }
    }
}
