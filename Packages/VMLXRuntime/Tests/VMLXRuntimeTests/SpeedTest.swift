import Testing
import Foundation
import MLX
@testable import VMLXRuntime

@Suite("Speed")
struct SpeedTest {
    @Test("MiniMax token timing")
    func miniMaxTiming() async throws {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let path = home.appendingPathComponent("jang/models/MiniMax-M2.5-JANG_2L")
        guard FileManager.default.fileExists(atPath: path.appendingPathComponent("config.json").path) else {
            print("SKIP"); return
        }

        let loaded = try await ModelLoader.load(from: path)
        let container = VMLXModelContainer.create(model: loaded)
        let cache = container.newCache()

        // Tokenize
        let msgs = [VMLXChatMessage(role: "user", content: "Hi")]
        let tokenIds = try container.applyChatTemplate(messages: msgs, addGenerationPrompt: true, enableThinking: true)
        print("Prompt tokens: \(tokenIds.count)")

        // Prefill
        let prefillStart = CFAbsoluteTimeGetCurrent()
        let input = MLXArray(tokenIds.map { Int32($0) }).reshaped(1, tokenIds.count)
        let logits = container.forward(input, cache: cache)
        MLX.eval(logits)
        let prefillTime = CFAbsoluteTimeGetCurrent() - prefillStart
        print("Prefill: \(String(format: "%.3f", prefillTime))s (\(tokenIds.count) tokens)")

        // Decode 20 tokens and time each
        var times: [Double] = []
        var nextToken = logits[0, -1].argMax().item(Int.self)
        for i in 0..<20 {
            let t0 = CFAbsoluteTimeGetCurrent()
            let nextInput = MLXArray([Int32(nextToken)]).reshaped(1, 1)
            let out = container.forward(nextInput, cache: cache)
            MLX.eval(out)
            nextToken = out[0, -1].argMax().item(Int.self)
            let dt = CFAbsoluteTimeGetCurrent() - t0
            times.append(dt)
            let tok = container.decode([nextToken])
            print("  token \(i): \(String(format: "%.3f", dt))s '\(tok.prefix(20))'")
        }

        let avgDecode = times.reduce(0, +) / Double(times.count)
        let tps = 1.0 / avgDecode
        print("\nAvg decode: \(String(format: "%.3f", avgDecode))s/token (\(String(format: "%.1f", tps)) tok/s)")
        print("First 3 decode: \(times.prefix(3).map { String(format: "%.3f", $0) })")
        print("Last 3 decode: \(times.suffix(3).map { String(format: "%.3f", $0) })")
    }
}
