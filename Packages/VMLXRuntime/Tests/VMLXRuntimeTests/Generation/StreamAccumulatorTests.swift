import Testing
@testable import VMLXRuntime

@Suite("StreamAccumulator")
struct StreamAccumulatorTests {

    @Test("Plain text passes through")
    func plainText() {
        var acc = StreamAccumulator()
        let events = acc.process(text: "Hello world")
        let texts = events.compactMap { e -> String? in
            if case .tokens(let t) = e { return t }; return nil
        }
        #expect(texts.joined() == "Hello world")
    }

    @Test("Stop sequence detection")
    func stopSequence() {
        var acc = StreamAccumulator(stopSequences: ["<|end|>"])
        let events = acc.process(text: "output<|end|>trailing")

        let texts = events.compactMap { e -> String? in
            if case .tokens(let t) = e { return t }; return nil
        }
        #expect(texts.joined() == "output")

        let finished = events.contains { if case .finished = $0 { return true }; return false }
        #expect(finished)
    }

    @Test("Tool call detection with GenericToolParser")
    func toolCallDetection() {
        var acc = StreamAccumulator(toolParser: GenericToolParser())
        let input = "{\"name\": \"search\", \"arguments\": {\"q\": \"test\"}}"
        let events = acc.process(text: input)

        let toolCalls = events.compactMap { e -> String? in
            if case .toolInvocation(let name, _, _) = e { return name }; return nil
        }
        #expect(toolCalls.contains("search"))
    }

    @Test("Reasoning extraction with ThinkTagParser")
    func reasoningExtraction() {
        var acc = StreamAccumulator(reasoningParser: ThinkTagReasoningParser())
        let events = acc.process(text: "<think>analyzing...</think>The answer is 42.")

        let thinking = events.compactMap { e -> String? in
            if case .thinking(let t) = e { return t }; return nil
        }
        #expect(!thinking.isEmpty)
    }

    @Test("Finalize flushes buffers")
    func finalize() {
        var acc = StreamAccumulator(stopSequences: ["end"])
        _ = acc.process(text: "hello en")  // "en" held back (partial match)
        let final = acc.finalize()
        let texts = final.compactMap { e -> String? in
            if case .tokens(let t) = e { return t }; return nil
        }
        #expect(texts.joined().contains("en"))
    }

    @Test("Token IDs tracked")
    func tokenIdsTracked() {
        var acc = StreamAccumulator()
        _ = acc.process(text: "hi", tokenIds: [100, 101])
        _ = acc.process(text: " there", tokenIds: [102, 103])
        #expect(acc.generatedTokenIds == [100, 101, 102, 103])
    }

    @Test("Reset clears state")
    func reset() {
        var acc = StreamAccumulator()
        _ = acc.process(text: "hello", tokenIds: [1, 2])
        acc.reset()
        #expect(acc.generatedTokenIds.isEmpty)
        #expect(acc.totalText.isEmpty)
    }
}
