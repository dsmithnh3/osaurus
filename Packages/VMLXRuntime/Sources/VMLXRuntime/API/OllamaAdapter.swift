import Foundation

// MARK: - Ollama API Types

/// Ollama chat completion request.
///
/// Ollama uses a simpler format than OpenAI:
/// - POST /api/chat for chat completions
/// - POST /api/generate for text completions
/// - GET /api/tags for model list
/// - POST /api/show for model info
///
/// Response is NDJSON (newline-delimited JSON), not SSE.
public struct OllamaChatRequest: Sendable, Codable {
    public let model: String
    public let messages: [OllamaMessage]
    public let stream: Bool?
    public let options: OllamaOptions?
    public let format: String?       // "json" for JSON mode
    public let keepAlive: String?    // Duration to keep model loaded (e.g., "5m")
    public let tools: [OllamaTool]?

    enum CodingKeys: String, CodingKey {
        case model, messages, stream, options, format
        case keepAlive = "keep_alive"
        case tools
    }

    public init(
        model: String,
        messages: [OllamaMessage],
        stream: Bool? = true,
        options: OllamaOptions? = nil,
        format: String? = nil,
        keepAlive: String? = nil,
        tools: [OllamaTool]? = nil
    ) {
        self.model = model
        self.messages = messages
        self.stream = stream
        self.options = options
        self.format = format
        self.keepAlive = keepAlive
        self.tools = tools
    }
}

/// Ollama generate (text completion) request.
public struct OllamaGenerateRequest: Sendable, Codable {
    public let model: String
    public let prompt: String
    public let stream: Bool?
    public let options: OllamaOptions?
    public let format: String?
    public let system: String?
    public let context: [Int]?       // Conversation context (token IDs)
    public let keepAlive: String?

    enum CodingKeys: String, CodingKey {
        case model, prompt, stream, options, format, system, context
        case keepAlive = "keep_alive"
    }

    public init(
        model: String,
        prompt: String,
        stream: Bool? = true,
        options: OllamaOptions? = nil,
        format: String? = nil,
        system: String? = nil,
        context: [Int]? = nil,
        keepAlive: String? = nil
    ) {
        self.model = model
        self.prompt = prompt
        self.stream = stream
        self.options = options
        self.format = format
        self.system = system
        self.context = context
        self.keepAlive = keepAlive
    }
}

/// Ollama message format.
public struct OllamaMessage: Sendable, Codable {
    public let role: String
    public let content: String
    public let images: [String]?     // Base64-encoded images
    public let toolCalls: [OllamaToolCall]?

    enum CodingKeys: String, CodingKey {
        case role, content, images
        case toolCalls = "tool_calls"
    }

    public init(
        role: String,
        content: String,
        images: [String]? = nil,
        toolCalls: [OllamaToolCall]? = nil
    ) {
        self.role = role
        self.content = content
        self.images = images
        self.toolCalls = toolCalls
    }
}

/// Ollama sampling/generation options.
public struct OllamaOptions: Sendable, Codable {
    public let temperature: Float?
    public let topP: Float?
    public let topK: Int?
    public let seed: Int?
    public let numPredict: Int?      // Max tokens
    public let repeatPenalty: Float?
    public let stop: [String]?
    public let numCtx: Int?          // Context window size

    enum CodingKeys: String, CodingKey {
        case temperature
        case topP = "top_p"
        case topK = "top_k"
        case seed
        case numPredict = "num_predict"
        case repeatPenalty = "repeat_penalty"
        case stop
        case numCtx = "num_ctx"
    }

    public init(
        temperature: Float? = nil,
        topP: Float? = nil,
        topK: Int? = nil,
        seed: Int? = nil,
        numPredict: Int? = nil,
        repeatPenalty: Float? = nil,
        stop: [String]? = nil,
        numCtx: Int? = nil
    ) {
        self.temperature = temperature
        self.topP = topP
        self.topK = topK
        self.seed = seed
        self.numPredict = numPredict
        self.repeatPenalty = repeatPenalty
        self.stop = stop
        self.numCtx = numCtx
    }
}

/// Ollama tool definition.
public struct OllamaTool: Sendable, Codable {
    public let type: String          // "function"
    public let function: OllamaFunction

    public init(type: String = "function", function: OllamaFunction) {
        self.type = type
        self.function = function
    }
}

/// Ollama function definition.
public struct OllamaFunction: Sendable, Codable {
    public let name: String
    public let description: String?
    public let parameters: OllamaFunctionParameters?

    public init(name: String, description: String? = nil, parameters: OllamaFunctionParameters? = nil) {
        self.name = name
        self.description = description
        self.parameters = parameters
    }
}

/// Ollama function parameters schema.
public struct OllamaFunctionParameters: Sendable, Codable {
    public let type: String          // "object"
    public let properties: [String: OllamaPropertySchema]?
    public let required: [String]?

    public init(type: String = "object", properties: [String: OllamaPropertySchema]? = nil, required: [String]? = nil) {
        self.type = type
        self.properties = properties
        self.required = required
    }
}

/// Ollama property schema for tool parameters.
public struct OllamaPropertySchema: Sendable, Codable {
    public let type: String
    public let description: String?

    public init(type: String, description: String? = nil) {
        self.type = type
        self.description = description
    }
}

/// Ollama tool call in response.
public struct OllamaToolCall: Sendable, Codable {
    public let function: OllamaToolCallFunction

    public init(function: OllamaToolCallFunction) {
        self.function = function
    }
}

/// Ollama tool call function details.
public struct OllamaToolCallFunction: Sendable, Codable {
    public let name: String
    public let arguments: [String: String]  // Ollama uses dict, not JSON string

    public init(name: String, arguments: [String: String]) {
        self.name = name
        self.arguments = arguments
    }
}

// MARK: - Ollama Response Types

/// Ollama chat response chunk (NDJSON format, one per line).
public struct OllamaChatResponse: Sendable, Codable {
    public let model: String
    public let createdAt: String?
    public let message: OllamaMessage?
    public let done: Bool
    public let totalDuration: Int?
    public let loadDuration: Int?
    public let promptEvalCount: Int?
    public let promptEvalDuration: Int?
    public let evalCount: Int?
    public let evalDuration: Int?

    enum CodingKeys: String, CodingKey {
        case model
        case createdAt = "created_at"
        case message, done
        case totalDuration = "total_duration"
        case loadDuration = "load_duration"
        case promptEvalCount = "prompt_eval_count"
        case promptEvalDuration = "prompt_eval_duration"
        case evalCount = "eval_count"
        case evalDuration = "eval_duration"
    }

    public init(
        model: String,
        message: OllamaMessage?,
        done: Bool,
        createdAt: String? = nil,
        promptEvalCount: Int? = nil,
        evalCount: Int? = nil,
        totalDuration: Int? = nil,
        loadDuration: Int? = nil,
        promptEvalDuration: Int? = nil,
        evalDuration: Int? = nil
    ) {
        self.model = model
        self.createdAt = createdAt
        self.message = message
        self.done = done
        self.totalDuration = totalDuration
        self.loadDuration = loadDuration
        self.promptEvalCount = promptEvalCount
        self.promptEvalDuration = promptEvalDuration
        self.evalCount = evalCount
        self.evalDuration = evalDuration
    }
}

/// Ollama generate response chunk (NDJSON).
public struct OllamaGenerateResponse: Sendable, Codable {
    public let model: String
    public let createdAt: String?
    public let response: String
    public let done: Bool
    public let context: [Int]?
    public let totalDuration: Int?
    public let promptEvalCount: Int?
    public let evalCount: Int?

    enum CodingKeys: String, CodingKey {
        case model
        case createdAt = "created_at"
        case response, done, context
        case totalDuration = "total_duration"
        case promptEvalCount = "prompt_eval_count"
        case evalCount = "eval_count"
    }

    public init(
        model: String,
        response: String,
        done: Bool,
        createdAt: String? = nil,
        context: [Int]? = nil,
        totalDuration: Int? = nil,
        promptEvalCount: Int? = nil,
        evalCount: Int? = nil
    ) {
        self.model = model
        self.createdAt = createdAt
        self.response = response
        self.done = done
        self.context = context
        self.totalDuration = totalDuration
        self.promptEvalCount = promptEvalCount
        self.evalCount = evalCount
    }
}

/// Ollama model tag (from GET /api/tags).
public struct OllamaModelTag: Sendable, Codable {
    public let name: String
    public let modifiedAt: String?
    public let size: Int?
    public let digest: String?

    enum CodingKeys: String, CodingKey {
        case name
        case modifiedAt = "modified_at"
        case size, digest
    }

    public init(name: String, modifiedAt: String? = nil, size: Int? = nil, digest: String? = nil) {
        self.name = name
        self.modifiedAt = modifiedAt
        self.size = size
        self.digest = digest
    }
}

/// Ollama tags response (GET /api/tags).
public struct OllamaTagsResponse: Sendable, Codable {
    public let models: [OllamaModelTag]

    public init(models: [OllamaModelTag]) {
        self.models = models
    }
}

// MARK: - OllamaAdapter

/// Translates between Ollama API format and VMLXRuntime's internal types.
///
/// Key conversions:
/// - Ollama `/api/chat` -> `VMLXChatCompletionRequest`
/// - Ollama `/api/generate` -> `VMLXChatCompletionRequest` (system + user prompt)
/// - Ollama options -> `SamplingParams` + request fields
/// - Ollama NDJSON response <- `VMLXEvent` stream
/// - Ollama `/api/tags` response <- loaded model info
public struct OllamaAdapter: Sendable {

    // MARK: - Request Conversion

    /// Convert an Ollama chat request to a VMLXChatCompletionRequest.
    public static func chatToVMLXRequest(_ request: OllamaChatRequest) -> VMLXChatCompletionRequest {
        let messages = request.messages.map { msg in
            VMLXChatMessage(role: msg.role, content: msg.content)
        }

        let tools: [VMLXToolDefinition]? = request.tools?.map { tool in
            VMLXToolDefinition(
                name: tool.function.name,
                description: tool.function.description
            )
        }

        return VMLXChatCompletionRequest(
            messages: messages,
            model: request.model,
            temperature: request.options?.temperature,
            maxTokens: request.options?.numPredict,
            topP: request.options?.topP,
            repetitionPenalty: request.options?.repeatPenalty,
            stop: request.options?.stop,
            stream: request.stream ?? true,
            tools: tools
        )
    }

    /// Convert an Ollama generate request to a VMLXChatCompletionRequest.
    public static func generateToVMLXRequest(_ request: OllamaGenerateRequest) -> VMLXChatCompletionRequest {
        var messages: [VMLXChatMessage] = []

        if let system = request.system {
            messages.append(VMLXChatMessage(role: "system", content: system))
        }

        messages.append(VMLXChatMessage(role: "user", content: request.prompt))

        return VMLXChatCompletionRequest(
            messages: messages,
            model: request.model,
            temperature: request.options?.temperature,
            maxTokens: request.options?.numPredict,
            topP: request.options?.topP,
            repetitionPenalty: request.options?.repeatPenalty,
            stop: request.options?.stop,
            stream: request.stream ?? true
        )
    }

    // MARK: - Response Conversion

    /// Build an Ollama chat response chunk from a text delta.
    /// Used during streaming (done=false for content, done=true for final).
    public static func toChatChunk(
        model: String,
        text: String,
        done: Bool = false,
        promptEvalCount: Int? = nil,
        evalCount: Int? = nil
    ) -> OllamaChatResponse {
        OllamaChatResponse(
            model: model,
            message: OllamaMessage(role: "assistant", content: text),
            done: done,
            promptEvalCount: done ? promptEvalCount : nil,
            evalCount: done ? evalCount : nil
        )
    }

    /// Build an Ollama generate response chunk from a text delta.
    public static func toGenerateChunk(
        model: String,
        text: String,
        done: Bool = false,
        promptEvalCount: Int? = nil,
        evalCount: Int? = nil
    ) -> OllamaGenerateResponse {
        OllamaGenerateResponse(
            model: model,
            response: text,
            done: done,
            promptEvalCount: done ? promptEvalCount : nil,
            evalCount: done ? evalCount : nil
        )
    }

    /// Encode an Ollama response chunk as NDJSON (a single JSON line).
    public static func encodeNDJSON<T: Encodable>(_ value: T) -> String? {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [] // Compact, no pretty-print
        guard let data = try? encoder.encode(value),
              let line = String(data: data, encoding: .utf8) else {
            return nil
        }
        return line
    }

    /// Build a tags response from loaded model information.
    public static func toTagsResponse(
        modelNames: [String],
        modelSizes: [String: Int] = [:]
    ) -> OllamaTagsResponse {
        let tags = modelNames.map { name in
            OllamaModelTag(
                name: name,
                size: modelSizes[name]
            )
        }
        return OllamaTagsResponse(models: tags)
    }

    /// Convert an OpenAI-style chat completion chunk to an Ollama NDJSON line.
    public static func openAIChunkToOllama(
        model: String,
        text: String,
        done: Bool
    ) -> String? {
        let chunk = toChatChunk(model: model, text: text, done: done)
        return encodeNDJSON(chunk)
    }
}
