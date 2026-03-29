import Foundation
import Testing
@testable import VMLXRuntime

@Suite("ChatMessageMapper")
struct ChatMessageMapperTests {

    @Test("Text message extracts content")
    func textContent() {
        let msg = VMLXChatMessage(role: "user", content: "Hello")
        #expect(msg.textContent == "Hello")
        #expect(!msg.hasImages)
    }

    @Test("Multimodal message extracts images")
    func multimodalImages() {
        let msg = VMLXChatMessage(role: "user", contentParts: [
            .text("What's this?"),
            .imageURL(url: "data:image/png;base64,abc123", detail: "auto")
        ])
        #expect(msg.hasImages)
        #expect(msg.imageURLs.count == 1)
        #expect(msg.textContent == "What's this?")
    }

    @Test("Request to SamplingParams")
    func requestToParams() {
        let request = VMLXChatCompletionRequest(
            messages: [VMLXChatMessage(role: "user", content: "Hi")],
            temperature: 0.5,
            maxTokens: 1024,
            topP: 0.95
        )
        let params = request.toSamplingParams()
        #expect(params.temperature == 0.5)
        #expect(params.maxTokens == 1024)
        #expect(params.topP == 0.95)
    }

    @Test("Default SamplingParams when not specified")
    func defaultParams() {
        let request = VMLXChatCompletionRequest(
            messages: [VMLXChatMessage(role: "user", content: "Hi")]
        )
        let params = request.toSamplingParams()
        #expect(params.temperature == 0.7)
        #expect(params.maxTokens == 2048)
    }

    @Test("Multimodal detection")
    func multimodalDetection() {
        let textOnly = VMLXChatCompletionRequest(
            messages: [VMLXChatMessage(role: "user", content: "text")]
        )
        #expect(!textOnly.isMultimodal)

        let withImage = VMLXChatCompletionRequest(
            messages: [VMLXChatMessage(role: "user", contentParts: [
                .imageURL(url: "https://example.com/img.jpg", detail: nil)
            ])]
        )
        #expect(withImage.isMultimodal)
    }

    @Test("Tool call message")
    func toolCallMessage() {
        let call = VMLXToolCall(id: "call_123", name: "search", arguments: "{\"q\":\"test\"}")
        #expect(call.function.name == "search")
        #expect(call.type == "function")
    }

    @Test("Streaming chunk creation")
    func streamingChunk() {
        let chunk = VMLXChatCompletionChunk(
            id: "chatcmpl-123",
            model: "local",
            delta: VMLXDelta(content: "Hello")
        )
        #expect(chunk.object == "chat.completion.chunk")
        #expect(chunk.choices[0].delta.content == "Hello")
        #expect(chunk.choices[0].finishReason == nil)
    }

    @Test("Reasoning content in delta")
    func reasoningDelta() {
        let delta = VMLXDelta(reasoningContent: "Let me think...")
        #expect(delta.reasoningContent == "Let me think...")
        #expect(delta.content == nil)
    }

    @Test("ContentPart Codable roundtrip")
    func contentPartCodable() throws {
        let parts: [VMLXContentPart] = [
            .text("What is this?"),
            .imageURL(url: "https://img.jpg", detail: "high")
        ]
        let data = try JSONEncoder().encode(parts)
        let decoded = try JSONDecoder().decode([VMLXContentPart].self, from: data)
        #expect(decoded.count == 2)
    }
}
