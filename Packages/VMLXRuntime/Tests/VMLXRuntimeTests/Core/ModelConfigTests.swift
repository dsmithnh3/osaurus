import Testing
@testable import VMLXRuntime

@Suite("ModelConfigRegistry")
struct ModelConfigRegistryTests {

    @Test("Detects by model type")
    func detectByModelType() {
        let config = ModelConfigRegistry.configForModelType("qwen3_moe")
        #expect(config != nil)
        #expect(config?.family == "qwen3")
        #expect(config?.toolCallFormat == .qwen)
        #expect(config?.reasoningFormat == .qwen3)
    }

    @Test("Detects Llama by model type")
    func detectLlamaByModelType() {
        let config = ModelConfigRegistry.configForModelType("llama4")
        #expect(config != nil)
        #expect(config?.toolCallFormat == .llama)
        #expect(config?.defaultContextWindow == 131072)
    }

    @Test("Detects Nemotron-H as hybrid")
    func detectNemotronH() {
        let config = ModelConfigRegistry.configForModelType("nemotron_h")
        #expect(config != nil)
        #expect(config?.isHybrid == true)
        #expect(config?.toolCallFormat == .nemotron)
    }

    @Test("Detects DeepSeek reasoning format")
    func detectDeepSeek() {
        let config = ModelConfigRegistry.configForModelType("deepseek_v3")
        #expect(config != nil)
        #expect(config?.toolCallFormat == .deepseek)
    }

    @Test("Detects vision models")
    func detectVision() {
        #expect(ModelConfigRegistry.configForModelType("qwen2_5_vl")?.supportsVision == true)
        #expect(ModelConfigRegistry.configForModelType("pixtral")?.supportsVision == true)
        #expect(ModelConfigRegistry.configForModelType("qwen3")?.supportsVision == false)
    }

    @Test("Unknown model type returns nil from configForModelType")
    func unknownModelType() {
        let config = ModelConfigRegistry.configForModelType("totally-unknown-model-type")
        #expect(config == nil)
    }

    @Test("configFor returns generic for unknown")
    func configForGeneric() {
        let config = ModelConfigRegistry.configFor(modelName: "unknown")
        #expect(config.family == "generic")
        #expect(config.toolCallFormat == .generic)
    }

    @Test("Registry has at least 15 entries")
    func registrySize() {
        #expect(ModelConfigRegistry.configs.count >= 15)
    }
}
