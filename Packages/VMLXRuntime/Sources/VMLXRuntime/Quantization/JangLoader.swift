import Foundation

/// JANG config file names to search for (in order of priority).
public let jangConfigFileNames = [
    "jang_config.json",
    "jjqf_config.json",
    "jang_cfg.json",
    "mxq_config.json"
]

/// Parsed JANG model configuration from jang_config.json.
public struct JangConfig: Sendable {
    /// Format version: "2.0" (MLX-native) or "1.0" (legacy).
    public let formatVersion: String

    /// Whether this is v2 format (fast, MLX-native safetensors).
    public var isV2: Bool { formatVersion.hasPrefix("2") }

    /// TurboQuant settings.
    public let turboquant: TurboQuantSettings?

    /// Hybrid layer pattern (e.g., "MMM*MMM*..." for Nemotron-H).
    public let hybridOverridePattern: String?

    /// Per-layer types if specified.
    public let layerTypes: [String]?

    /// MLA settings for DeepSeek-style models.
    public let kvLoraRank: Int?
    public let qkNopeHeadDim: Int?
    public let qkRopeHeadDim: Int?
    public let vHeadDim: Int?

    public init(
        formatVersion: String = "2.0",
        turboquant: TurboQuantSettings? = nil,
        hybridOverridePattern: String? = nil,
        layerTypes: [String]? = nil,
        kvLoraRank: Int? = nil,
        qkNopeHeadDim: Int? = nil,
        qkRopeHeadDim: Int? = nil,
        vHeadDim: Int? = nil
    ) {
        self.formatVersion = formatVersion
        self.turboquant = turboquant
        self.hybridOverridePattern = hybridOverridePattern
        self.layerTypes = layerTypes
        self.kvLoraRank = kvLoraRank
        self.qkNopeHeadDim = qkNopeHeadDim
        self.qkRopeHeadDim = qkRopeHeadDim
        self.vHeadDim = vHeadDim
    }
}

/// TurboQuant settings from jang_config.json.
public struct TurboQuantSettings: Sendable {
    public let enabled: Bool
    public let defaultKeyBits: Int
    public let defaultValueBits: Int
    public let criticalLayers: [Int]
    public let criticalKeyBits: Int
    public let criticalValueBits: Int

    public init(
        enabled: Bool = true,
        defaultKeyBits: Int = 3,
        defaultValueBits: Int = 3,
        criticalLayers: [Int] = [0, 1, 2, -3, -2, -1],
        criticalKeyBits: Int = 4,
        criticalValueBits: Int = 4
    ) {
        self.enabled = enabled
        self.defaultKeyBits = defaultKeyBits
        self.defaultValueBits = defaultValueBits
        self.criticalLayers = criticalLayers
        self.criticalKeyBits = criticalKeyBits
        self.criticalValueBits = criticalValueBits
    }
}

/// JANG model loader.
/// Auto-detects JANG models, parses config, and configures TurboQuant.
public struct JangLoader: Sendable {

    /// Check if a model directory contains a JANG model.
    public static func isJangModel(at path: URL) -> Bool {
        findConfigPath(at: path) != nil
    }

    /// Find the JANG config file in a model directory.
    public static func findConfigPath(at modelPath: URL) -> URL? {
        for name in jangConfigFileNames {
            let configURL = modelPath.appendingPathComponent(name)
            if FileManager.default.fileExists(atPath: configURL.path) {
                return configURL
            }
        }
        return nil
    }

    /// Load and parse the JANG config.
    public static func loadConfig(at modelPath: URL) throws -> JangConfig {
        guard let configURL = findConfigPath(at: modelPath) else {
            throw JangLoaderError.configNotFound(modelPath.path)
        }

        let data = try Data(contentsOf: configURL)
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw JangLoaderError.invalidConfig("Failed to parse JSON")
        }

        // Parse format version
        let formatVersion = json["format_version"] as? String ?? "2.0"

        // Parse TurboQuant settings
        var tqSettings: TurboQuantSettings?
        if let tqDict = json["turboquant"] as? [String: Any] {
            let enabled = tqDict["enabled"] as? Bool ?? true
            let keyBits = tqDict["default_key_bits"] as? Int ?? 3
            let valueBits = tqDict["default_value_bits"] as? Int ?? 3
            let criticalLayers = tqDict["critical_layers"] as? [Int] ?? [0, 1, 2, -3, -2, -1]
            let criticalKeyBits = tqDict["critical_key_bits"] as? Int ?? 4
            let criticalValueBits = tqDict["critical_value_bits"] as? Int ?? 4

            tqSettings = TurboQuantSettings(
                enabled: enabled,
                defaultKeyBits: keyBits,
                defaultValueBits: valueBits,
                criticalLayers: criticalLayers,
                criticalKeyBits: criticalKeyBits,
                criticalValueBits: criticalValueBits
            )
        }

        // Parse hybrid pattern
        let hybridPattern = json["hybrid_override_pattern"] as? String
        let layerTypes = json["layer_types"] as? [String]

        // Parse MLA settings
        let kvLoraRank = json["kv_lora_rank"] as? Int
        let qkNopeHeadDim = json["qk_nope_head_dim"] as? Int
        let qkRopeHeadDim = json["qk_rope_head_dim"] as? Int
        let vHeadDim = json["v_head_dim"] as? Int

        return JangConfig(
            formatVersion: formatVersion,
            turboquant: tqSettings,
            hybridOverridePattern: hybridPattern,
            layerTypes: layerTypes,
            kvLoraRank: kvLoraRank,
            qkNopeHeadDim: qkNopeHeadDim,
            qkRopeHeadDim: qkRopeHeadDim,
            vHeadDim: vHeadDim
        )
    }

    /// Build TurboQuantConfig from JANG config.
    public static func buildTQConfig(from jangConfig: JangConfig) -> TurboQuantConfig? {
        guard let tq = jangConfig.turboquant, tq.enabled else { return nil }

        // Detect hybrid layer pattern
        var layerPattern: [LayerType]?
        if let pattern = jangConfig.hybridOverridePattern {
            layerPattern = parseHybridPattern(pattern)
        } else if let types = jangConfig.layerTypes {
            layerPattern = types.map { type -> LayerType in
                switch type.uppercased() {
                case "M", "MAMBA", "SSM": return .ssm
                case "E", "EXPERT", "MOE": return .expert
                default: return .attention
                }
            }
        }

        // MLA dimensions
        var mlaKeyDim: Int?
        var mlaValueDim: Int?
        if let kvLoraRank = jangConfig.kvLoraRank, kvLoraRank > 0 {
            if let nope = jangConfig.qkNopeHeadDim, let rope = jangConfig.qkRopeHeadDim {
                mlaKeyDim = nope + rope
            }
            mlaValueDim = jangConfig.vHeadDim
        }

        return TurboQuantConfig(
            defaultKeyBits: tq.defaultKeyBits,
            defaultValueBits: tq.defaultValueBits,
            criticalLayers: tq.criticalLayers,
            criticalKeyBits: tq.criticalKeyBits,
            criticalValueBits: tq.criticalValueBits,
            layerPattern: layerPattern,
            mlaKeyDim: mlaKeyDim,
            mlaValueDim: mlaValueDim
        )
    }

    /// Detect if a JANG model is hybrid (has SSM layers).
    public static func isHybridModel(config: JangConfig) -> Bool {
        if let pattern = config.hybridOverridePattern {
            return pattern.contains("M")
        }
        if let types = config.layerTypes {
            let hasSSM = types.contains { $0.uppercased() == "M" || $0.uppercased() == "MAMBA" || $0.uppercased() == "SSM" }
            let hasAttn = types.contains { $0.uppercased() == "*" || $0.uppercased() == "ATTENTION" || $0.uppercased() == "ATTN" }
            return hasSSM && hasAttn
        }
        return false
    }

    /// Check if model uses MLA (Multi-head Latent Attention).
    public static func isMLA(config: JangConfig) -> Bool {
        guard let rank = config.kvLoraRank else { return false }
        return rank > 0
    }
}

// MARK: - Errors

public enum JangLoaderError: Error, LocalizedError, Sendable {
    case configNotFound(String)
    case invalidConfig(String)
    case unsupportedVersion(String)
    case loadFailed(String)

    public var errorDescription: String? {
        switch self {
        case .configNotFound(let path): return "JANG config not found at: \(path)"
        case .invalidConfig(let msg): return "Invalid JANG config: \(msg)"
        case .unsupportedVersion(let ver): return "Unsupported JANG version: \(ver)"
        case .loadFailed(let msg): return "JANG load failed: \(msg)"
        }
    }
}
