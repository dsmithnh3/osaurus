import Testing
import Foundation
@testable import VMLXRuntime

@Suite("OllamaAdapter")
struct OllamaAdapterTests {

    // MARK: - Chat Request Conversion

    @Test("Basic chat request conversion")
    func basicChat() {
        let request = OllamaChatRequest(
            model: "qwen3.5:4b",
            messages: [
                OllamaMessage(role: "user", content: "Hi"),
            ],
            stream: true
        )

        let vmlx = OllamaAdapter.chatToVMLXRequest(request)

        #expect(vmlx.messages.count == 1)
        #expect(vmlx.messages[0].role == "user")
        #expect(vmlx.messages[0].textContent == "Hi")
        #expect(vmlx.model == "qwen3.5:4b")
        #expect(vmlx.stream == true)
    }

    @Test("Chat with options")
    func chatWithOptions() {
        let request = OllamaChatRequest(
            model: "llama3:8b",
            messages: [
                OllamaMessage(role: "system", content: "Be brief"),
                OllamaMessage(role: "user", content: "Hello"),
            ],
            options: OllamaOptions(
                temperature: 0.3,
                topP: 0.8,
                numPredict: 512,
                repeatPenalty: 1.1,
                stop: ["<|eot_id|>"]
            )
        )

        let vmlx = OllamaAdapter.chatToVMLXRequest(request)

        #expect(vmlx.messages.count == 2)
        #expect(vmlx.temperature == 0.3)
        #expect(vmlx.topP == 0.8)
        #expect(vmlx.maxTokens == 512)
        #expect(vmlx.repetitionPenalty == 1.1)
        #expect(vmlx.stop == ["<|eot_id|>"])
    }

    @Test("Chat with tools")
    func chatWithTools() {
        let request = OllamaChatRequest(
            model: "qwen3.5:4b",
            messages: [
                OllamaMessage(role: "user", content: "What is the weather?")
            ],
            tools: [
                OllamaTool(function: OllamaFunction(
                    name: "get_weather",
                    description: "Get the current weather"
                ))
            ]
        )

        let vmlx = OllamaAdapter.chatToVMLXRequest(request)
        #expect(vmlx.tools != nil)
        #expect(vmlx.tools!.count == 1)
        #expect(vmlx.tools![0].function.name == "get_weather")
    }

    @Test("Non-streaming chat")
    func nonStreamingChat() {
        let request = OllamaChatRequest(
            model: "model",
            messages: [OllamaMessage(role: "user", content: "Test")],
            stream: false
        )

        let vmlx = OllamaAdapter.chatToVMLXRequest(request)
        #expect(vmlx.stream == false)
    }

    // MARK: - Generate Request Conversion

    @Test("Basic generate request")
    func basicGenerate() {
        let request = OllamaGenerateRequest(
            model: "codestral:22b",
            prompt: "Write a function"
        )

        let vmlx = OllamaAdapter.generateToVMLXRequest(request)

        #expect(vmlx.messages.count == 1)
        #expect(vmlx.messages[0].role == "user")
        #expect(vmlx.messages[0].textContent == "Write a function")
        #expect(vmlx.model == "codestral:22b")
    }

    @Test("Generate with system prompt")
    func generateWithSystem() {
        let request = OllamaGenerateRequest(
            model: "model",
            prompt: "Hello",
            system: "You are a helpful assistant"
        )

        let vmlx = OllamaAdapter.generateToVMLXRequest(request)

        #expect(vmlx.messages.count == 2)
        #expect(vmlx.messages[0].role == "system")
        #expect(vmlx.messages[0].textContent == "You are a helpful assistant")
        #expect(vmlx.messages[1].role == "user")
        #expect(vmlx.messages[1].textContent == "Hello")
    }

    @Test("Generate with options")
    func generateWithOptions() {
        let request = OllamaGenerateRequest(
            model: "model",
            prompt: "Test",
            options: OllamaOptions(
                temperature: 0.0,
                numPredict: 100,
                stop: ["```"]
            )
        )

        let vmlx = OllamaAdapter.generateToVMLXRequest(request)
        #expect(vmlx.temperature == 0.0)
        #expect(vmlx.maxTokens == 100)
        #expect(vmlx.stop == ["```"])
    }

    // MARK: - Response Building

    @Test("Chat chunk building")
    func chatChunk() {
        let chunk = OllamaAdapter.toChatChunk(
            model: "qwen3.5:4b",
            text: "Hello",
            done: false
        )

        #expect(chunk.model == "qwen3.5:4b")
        #expect(chunk.message?.content == "Hello")
        #expect(chunk.message?.role == "assistant")
        #expect(chunk.done == false)
    }

    @Test("Chat final chunk with stats")
    func chatFinalChunk() {
        let chunk = OllamaAdapter.toChatChunk(
            model: "model",
            text: "",
            done: true,
            promptEvalCount: 50,
            evalCount: 100
        )

        #expect(chunk.done == true)
        #expect(chunk.promptEvalCount == 50)
        #expect(chunk.evalCount == 100)
    }

    @Test("Generate chunk building")
    func generateChunk() {
        let chunk = OllamaAdapter.toGenerateChunk(
            model: "model",
            text: "def ",
            done: false
        )

        #expect(chunk.response == "def ")
        #expect(chunk.done == false)
    }

    // MARK: - NDJSON Encoding

    @Test("NDJSON encoding of chat response")
    func ndjsonChat() {
        let chunk = OllamaChatResponse(
            model: "model",
            message: OllamaMessage(role: "assistant", content: "Hi"),
            done: false
        )

        let line = OllamaAdapter.encodeNDJSON(chunk)
        #expect(line != nil)
        #expect(line!.contains("\"model\":\"model\""))
        #expect(line!.contains("\"done\":false"))
        #expect(!line!.contains("\n"))  // NDJSON: no embedded newlines
    }

    @Test("NDJSON encoding of generate response")
    func ndjsonGenerate() {
        let chunk = OllamaGenerateResponse(
            model: "test",
            response: "hello",
            done: false
        )

        let line = OllamaAdapter.encodeNDJSON(chunk)
        #expect(line != nil)
        #expect(line!.contains("\"response\":\"hello\""))
    }

    // MARK: - Tags Response

    @Test("Tags response building")
    func tagsResponse() {
        let tags = OllamaAdapter.toTagsResponse(
            modelNames: ["qwen3.5:4b", "llama3:8b"],
            modelSizes: ["qwen3.5:4b": 2_500_000_000]
        )

        #expect(tags.models.count == 2)
        #expect(tags.models[0].name == "qwen3.5:4b")
        #expect(tags.models[0].size == 2_500_000_000)
        #expect(tags.models[1].name == "llama3:8b")
        #expect(tags.models[1].size == nil)
    }

    // MARK: - Codable Round-trips

    @Test("OllamaOptions Codable")
    func optionsCodable() throws {
        let options = OllamaOptions(
            temperature: 0.7,
            topP: 0.9,
            topK: 40,
            numPredict: 256,
            repeatPenalty: 1.1,
            stop: ["<end>"],
            numCtx: 4096
        )

        let data = try JSONEncoder().encode(options)
        let decoded = try JSONDecoder().decode(OllamaOptions.self, from: data)

        #expect(decoded.temperature == 0.7)
        #expect(decoded.topP == 0.9)
        #expect(decoded.topK == 40)
        #expect(decoded.numPredict == 256)
        #expect(decoded.repeatPenalty == 1.1)
        #expect(decoded.stop == ["<end>"])
        #expect(decoded.numCtx == 4096)
    }

    @Test("OllamaChatRequest Codable")
    func chatRequestCodable() throws {
        let request = OllamaChatRequest(
            model: "qwen3.5:4b",
            messages: [
                OllamaMessage(role: "user", content: "Hello")
            ],
            stream: true
        )

        let data = try JSONEncoder().encode(request)
        let decoded = try JSONDecoder().decode(OllamaChatRequest.self, from: data)

        #expect(decoded.model == "qwen3.5:4b")
        #expect(decoded.messages.count == 1)
        #expect(decoded.messages[0].content == "Hello")
        #expect(decoded.stream == true)
    }

    @Test("OpenAI chunk to Ollama conversion")
    func openAIToOllama() {
        let line = OllamaAdapter.openAIChunkToOllama(
            model: "local",
            text: "Hello",
            done: false
        )
        #expect(line != nil)
        #expect(line!.contains("\"done\":false"))
        #expect(line!.contains("Hello"))
    }
}
