import Testing
import Foundation
@testable import VMLXRuntime

@Suite("AnthropicAdapter")
struct AnthropicAdapterTests {

    // MARK: - Request Conversion

    @Test("Basic message conversion")
    func basicConversion() {
        let request = AnthropicMessagesRequest(
            model: "local",
            maxTokens: 1024,
            system: .text("You are helpful"),
            messages: [
                AnthropicMessage(role: "user", content: .text("Hello"))
            ]
        )

        let vmlx = AnthropicAdapter.toVMLXRequest(request)

        #expect(vmlx.messages.count == 2)
        #expect(vmlx.messages[0].role == "system")
        #expect(vmlx.messages[0].textContent == "You are helpful")
        #expect(vmlx.messages[1].role == "user")
        #expect(vmlx.messages[1].textContent == "Hello")
        #expect(vmlx.maxTokens == 1024)
        #expect(vmlx.model == "local")
    }

    @Test("System as content blocks")
    func systemBlocks() {
        let system = AnthropicSystemContent.blocks([
            AnthropicContentBlock(type: "text", content: .text("Be helpful.")),
            AnthropicContentBlock(type: "text", content: .text("Be concise.")),
        ])

        let request = AnthropicMessagesRequest(
            maxTokens: 512,
            system: system,
            messages: [
                AnthropicMessage(role: "user", content: .text("Hi"))
            ]
        )

        let vmlx = AnthropicAdapter.toVMLXRequest(request)
        #expect(vmlx.messages[0].role == "system")
        #expect(vmlx.messages[0].textContent.contains("Be helpful."))
        #expect(vmlx.messages[0].textContent.contains("Be concise."))
    }

    @Test("No system prompt")
    func noSystem() {
        let request = AnthropicMessagesRequest(
            maxTokens: 512,
            messages: [
                AnthropicMessage(role: "user", content: .text("Hello"))
            ]
        )

        let vmlx = AnthropicAdapter.toVMLXRequest(request)
        #expect(vmlx.messages.count == 1)
        #expect(vmlx.messages[0].role == "user")
    }

    @Test("Thinking enabled conversion")
    func thinkingEnabled() {
        let request = AnthropicMessagesRequest(
            maxTokens: 2048,
            messages: [
                AnthropicMessage(role: "user", content: .text("Think about this"))
            ],
            thinking: AnthropicThinkingConfig(type: "enabled", budgetTokens: 5000)
        )

        let vmlx = AnthropicAdapter.toVMLXRequest(request)
        #expect(vmlx.enableThinking == true)
        #expect(vmlx.reasoningEffort == "medium")
    }

    @Test("Thinking budget to effort mapping")
    func thinkingBudgetMapping() {
        // Low budget
        let lowReq = AnthropicMessagesRequest(
            maxTokens: 512,
            messages: [],
            thinking: AnthropicThinkingConfig(type: "enabled", budgetTokens: 500)
        )
        #expect(AnthropicAdapter.toVMLXRequest(lowReq).reasoningEffort == "low")

        // Medium budget
        let medReq = AnthropicMessagesRequest(
            maxTokens: 512,
            messages: [],
            thinking: AnthropicThinkingConfig(type: "enabled", budgetTokens: 3000)
        )
        #expect(AnthropicAdapter.toVMLXRequest(medReq).reasoningEffort == "medium")

        // High budget
        let highReq = AnthropicMessagesRequest(
            maxTokens: 512,
            messages: [],
            thinking: AnthropicThinkingConfig(type: "enabled", budgetTokens: 10000)
        )
        #expect(AnthropicAdapter.toVMLXRequest(highReq).reasoningEffort == "high")
    }

    @Test("Thinking disabled")
    func thinkingDisabled() {
        let request = AnthropicMessagesRequest(
            maxTokens: 512,
            messages: [],
            thinking: AnthropicThinkingConfig(type: "disabled")
        )

        let vmlx = AnthropicAdapter.toVMLXRequest(request)
        #expect(vmlx.enableThinking == false)
    }

    @Test("Tool choice conversion")
    func toolChoice() {
        let autoReq = AnthropicMessagesRequest(
            maxTokens: 512,
            messages: [],
            toolChoice: AnthropicToolChoice(type: "auto")
        )
        #expect(AnthropicAdapter.toVMLXRequest(autoReq).toolChoice == "auto")

        let anyReq = AnthropicMessagesRequest(
            maxTokens: 512,
            messages: [],
            toolChoice: AnthropicToolChoice(type: "any")
        )
        #expect(AnthropicAdapter.toVMLXRequest(anyReq).toolChoice == "auto")

        let specificReq = AnthropicMessagesRequest(
            maxTokens: 512,
            messages: [],
            toolChoice: AnthropicToolChoice(type: "tool", name: "get_weather")
        )
        #expect(AnthropicAdapter.toVMLXRequest(specificReq).toolChoice == "get_weather")
    }

    @Test("Sampling parameters conversion")
    func samplingParams() {
        let request = AnthropicMessagesRequest(
            maxTokens: 4096,
            messages: [],
            stream: true,
            temperature: 0.5,
            topP: 0.95,
            stopSequences: ["STOP", "END"]
        )

        let vmlx = AnthropicAdapter.toVMLXRequest(request)
        #expect(vmlx.temperature == 0.5)
        #expect(vmlx.topP == 0.95)
        #expect(vmlx.maxTokens == 4096)
        #expect(vmlx.stream == true)
        #expect(vmlx.stop == ["STOP", "END"])
    }

    // MARK: - Response Conversion

    @Test("Text-only response")
    func textResponse() {
        let response = AnthropicAdapter.toAnthropicResponse(
            text: "Hello there!",
            model: "local",
            promptTokens: 10,
            completionTokens: 5,
            finishReason: .stop
        )

        #expect(response.type == "message")
        #expect(response.role == "assistant")
        #expect(response.content.count == 1)
        #expect(response.content[0].type == "text")
        #expect(response.stopReason == "end_turn")
        #expect(response.usage.inputTokens == 10)
        #expect(response.usage.outputTokens == 5)
    }

    @Test("Response with thinking")
    func thinkingResponse() {
        let response = AnthropicAdapter.toAnthropicResponse(
            text: "The answer is 42.",
            thinkingText: "Let me think about this carefully...",
            model: "local",
            promptTokens: 15,
            completionTokens: 25,
            finishReason: .stop
        )

        #expect(response.content.count == 2)
        #expect(response.content[0].type == "thinking")
        #expect(response.content[1].type == "text")
    }

    @Test("Response with tool use")
    func toolUseResponse() {
        let response = AnthropicAdapter.toAnthropicResponse(
            text: "",
            toolCalls: [(name: "get_weather", id: "call_123", argsJSON: "{\"city\":\"SF\"}")],
            model: "local",
            promptTokens: 10,
            completionTokens: 15,
            finishReason: .toolCalls
        )

        #expect(response.stopReason == "tool_use")
        let toolBlock = response.content.first { $0.type == "tool_use" }
        #expect(toolBlock != nil)
    }

    @Test("Max tokens stop reason")
    func maxTokensReason() {
        let response = AnthropicAdapter.toAnthropicResponse(
            text: "Truncated...",
            model: "local",
            promptTokens: 10,
            completionTokens: 1024,
            finishReason: .length
        )
        #expect(response.stopReason == "max_tokens")
    }

    @Test("Cache statistics in usage")
    func cacheUsage() {
        let response = AnthropicAdapter.toAnthropicResponse(
            text: "Cached!",
            model: "local",
            promptTokens: 100,
            completionTokens: 10,
            cachedTokens: 80,
            finishReason: .stop
        )
        #expect(response.usage.cacheReadInputTokens == 80)
    }

    // MARK: - Stop Reason Mapping

    @Test("Stop reason mapping")
    func stopReasonMapping() {
        #expect(AnthropicAdapter.mapStopReason("end_turn") == .stop)
        #expect(AnthropicAdapter.mapStopReason("max_tokens") == .length)
        #expect(AnthropicAdapter.mapStopReason("tool_use") == .toolCalls)
        #expect(AnthropicAdapter.mapStopReason("stop_sequence") == .stop)
        #expect(AnthropicAdapter.mapStopReason("unknown") == nil)
        #expect(AnthropicAdapter.mapStopReason(nil) == nil)
    }

    // MARK: - Codable Round-trips

    @Test("Thinking config Codable")
    func thinkingCodable() throws {
        let config = AnthropicThinkingConfig(type: "enabled", budgetTokens: 5000)
        let data = try JSONEncoder().encode(config)
        let decoded = try JSONDecoder().decode(AnthropicThinkingConfig.self, from: data)
        #expect(decoded.type == "enabled")
        #expect(decoded.budgetTokens == 5000)
        #expect(decoded.isEnabled == true)
    }

    @Test("Usage Codable")
    func usageCodable() throws {
        let usage = AnthropicUsage(
            inputTokens: 100,
            outputTokens: 50,
            cacheReadInputTokens: 80
        )
        let data = try JSONEncoder().encode(usage)
        let decoded = try JSONDecoder().decode(AnthropicUsage.self, from: data)
        #expect(decoded.inputTokens == 100)
        #expect(decoded.outputTokens == 50)
        #expect(decoded.cacheReadInputTokens == 80)
    }
}
