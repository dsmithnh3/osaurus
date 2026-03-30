import Testing
import Foundation
@testable import VMLXRuntime

@Suite("JangLoader")
struct JangLoaderTests {

    private func createTempModelDir(with configName: String = "jang_config.json", content: [String: Any]) throws -> URL {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

        let configURL = dir.appendingPathComponent(configName)
        let data = try JSONSerialization.data(withJSONObject: content)
        try data.write(to: configURL)

        return dir
    }

    @Test("Detect JANG model")
    func detectJangModel() throws {
        let dir = try createTempModelDir(content: ["format_version": "2.0"])
        defer { try? FileManager.default.removeItem(at: dir) }

        #expect(JangLoader.isJangModel(at: dir))
    }

    @Test("Non-JANG directory returns false")
    func notJangModel() {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }

        #expect(!JangLoader.isJangModel(at: dir))
    }

    @Test("Finds alternative config names")
    func alternativeConfigNames() throws {
        for name in jangConfigFileNames {
            let dir = try createTempModelDir(with: name, content: ["format_version": "2.0"])
            defer { try? FileManager.default.removeItem(at: dir) }

            #expect(JangLoader.isJangModel(at: dir))
            let configPath = JangLoader.findConfigPath(at: dir)
            #expect(configPath?.lastPathComponent == name)
        }
    }

    @Test("Parse basic config")
    func parseBasicConfig() throws {
        let dir = try createTempModelDir(content: [
            "format_version": "2.0",
            "turboquant": [
                "enabled": true,
                "default_key_bits": 3,
                "default_value_bits": 3,
                "critical_layers": [0, 1, 2, -3, -2, -1],
                "critical_key_bits": 4,
                "critical_value_bits": 4
            ] as [String: Any]
        ])
        defer { try? FileManager.default.removeItem(at: dir) }

        let config = try JangLoader.loadConfig(at: dir)
        #expect(config.isV2)
        #expect(config.turboquant != nil)
        #expect(config.turboquant?.enabled == true)
        #expect(config.turboquant?.defaultKeyBits == 3)
    }

    @Test("Build TQ config from JANG config")
    func buildTQConfig() throws {
        let jangConfig = JangConfig(
            turboquant: TurboQuantSettings(
                enabled: true,
                defaultKeyBits: 3,
                criticalLayers: [0, -1]
            )
        )

        let tqConfig = JangLoader.buildTQConfig(from: jangConfig)
        #expect(tqConfig != nil)
        #expect(tqConfig?.defaultKeyBits == 3)
        #expect(tqConfig?.criticalLayers == [0, -1])
    }

    @Test("TQ disabled returns nil")
    func tqDisabled() {
        let config = JangConfig(turboquant: TurboQuantSettings(enabled: false))
        #expect(JangLoader.buildTQConfig(from: config) == nil)
    }

    @Test("No TQ settings returns nil")
    func noTQSettings() {
        let config = JangConfig()
        #expect(JangLoader.buildTQConfig(from: config) == nil)
    }

    @Test("Detect hybrid model from pattern")
    func detectHybridPattern() {
        let config = JangConfig(hybridOverridePattern: "MMM*MMM*MMM*MMM*")
        #expect(JangLoader.isHybridModel(config: config))
    }

    @Test("Detect hybrid model from layer types")
    func detectHybridLayerTypes() {
        let config = JangConfig(layerTypes: ["M", "M", "M", "*", "M", "M", "M", "*"])
        #expect(JangLoader.isHybridModel(config: config))
    }

    @Test("Pure attention not hybrid")
    func notHybrid() {
        let config = JangConfig(hybridOverridePattern: "********")
        #expect(!JangLoader.isHybridModel(config: config))
    }

    @Test("MLA detection")
    func mlaDetection() {
        let config = JangConfig(
            kvLoraRank: 512,
            qkNopeHeadDim: 128,
            qkRopeHeadDim: 64,
            vHeadDim: 128
        )
        #expect(JangLoader.isMLA(config: config))

        let tq = JangLoader.buildTQConfig(from: JangConfig(
            turboquant: TurboQuantSettings(),
            kvLoraRank: 512,
            qkNopeHeadDim: 128,
            qkRopeHeadDim: 64,
            vHeadDim: 128
        ))
        #expect(tq?.mlaKeyDim == 192)  // 128 + 64
        #expect(tq?.mlaValueDim == 128)
    }

    @Test("Hybrid pattern builds LayerType array")
    func hybridPatternToLayerTypes() {
        let config = JangConfig(
            turboquant: TurboQuantSettings(),
            hybridOverridePattern: "MMM*"
        )
        let tq = JangLoader.buildTQConfig(from: config)
        #expect(tq?.layerPattern == [.ssm, .ssm, .ssm, .attention])
    }

    @Test("Error descriptions")
    func errorDescriptions() {
        let errors: [JangLoaderError] = [
            .configNotFound("/path"),
            .invalidConfig("bad"),
            .unsupportedVersion("0.5"),
            .loadFailed("error")
        ]
        for error in errors {
            #expect(error.errorDescription != nil)
        }
    }
}
