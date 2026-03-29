import Testing
@testable import VMLXRuntime

@Suite("ModelConfigRegistry")
struct ModelConfigRegistryTests {

    @Test("Detects Qwen3 model")
    func detectQwen3() {
        let config = ModelConfigRegistry.detect(modelName: "Qwen3-8B-JANG_2L")
        #expect(config != nil)
        #expect(config?.family == "qwen3")
        #expect(config?.toolCallFormat == .qwen)
        #expect(config?.reasoningFormat == .qwen3)
    }

    @Test("Detects Llama 4")
    func detectLlama4() {
        let config = ModelConfigRegistry.detect(modelName: "Llama-4-Scout-17B")
        #expect(config != nil)
        #expect(config?.toolCallFormat == .llama)
        #expect(config?.defaultContextWindow == 131072)
    }

    @Test("Detects Nemotron-H as hybrid")
    func detectNemotronH() {
        let config = ModelConfigRegistry.detect(modelName: "Nemotron-H-47B-JANG")
        #expect(config != nil)
        #expect(config?.isHybrid == true)
        #expect(config?.toolCallFormat == .nemotron)
    }

    @Test("Detects DeepSeek-R1 reasoning format")
    func detectDeepSeekR1() {
        let config = ModelConfigRegistry.detect(modelName: "DeepSeek-R1-0528")
        #expect(config != nil)
        #expect(config?.reasoningFormat == .deepseekR1)
    }

    @Test("Detects vision models")
    func detectVision() {
        #expect(ModelConfigRegistry.supportsVision("Qwen2.5-VL-72B"))
        #expect(ModelConfigRegistry.supportsVision("Pixtral-Large"))
        #expect(!ModelConfigRegistry.supportsVision("Qwen3-8B"))
    }

    @Test("Unknown model returns nil from detect")
    func unknownModel() {
        let config = ModelConfigRegistry.detect(modelName: "totally-unknown-model")
        #expect(config == nil)
    }

    @Test("configFor returns generic for unknown")
    func configForGeneric() {
        let config = ModelConfigRegistry.configFor(modelName: "unknown")
        #expect(config.family == "generic")
        #expect(config.toolCallFormat == .generic)
    }

    @Test("Convenience methods work")
    func convenienceMethods() {
        #expect(ModelConfigRegistry.toolFormat(for: "Mistral-7B") == .mistral)
        #expect(ModelConfigRegistry.reasoningFormat(for: "Qwen3-8B") == .qwen3)
        #expect(ModelConfigRegistry.isHybrid("Jamba-1.5"))
    }

    @Test("Underscore and space normalization")
    func normalization() {
        let c1 = ModelConfigRegistry.detect(modelName: "nemotron_h_47b")
        #expect(c1?.isHybrid == true)
        let c2 = ModelConfigRegistry.detect(modelName: "Nemotron H 47B")
        #expect(c2?.isHybrid == true)
    }

    @Test("Registry has at least 25 entries")
    func registrySize() {
        #expect(ModelConfigRegistry.configs.count >= 25)
    }
}
