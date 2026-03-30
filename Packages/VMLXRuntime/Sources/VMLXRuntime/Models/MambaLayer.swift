import Foundation
import MLX
import MLXNN
import MLXFast

// MARK: - MambaConfig

/// Configuration for a Mamba SSM layer.
/// Supports both Mamba-1 (selective scan) and Mamba-2 (SSD) style blocks.
public struct MambaConfig: Sendable {
    /// Hidden dimension (model width).
    public let hiddenSize: Int

    /// Inner SSM dimension (typically 2x hidden_size).
    public let intermediateSize: Int

    /// Discrete state space dimension (N in papers, typically 16).
    public let stateSize: Int

    /// 1D convolution kernel size (typically 4).
    public let convKernel: Int

    /// Rank of the time-step projection (dt_rank). Auto = ceil(hiddenSize/16).
    public let timeStepRank: Int

    /// Whether to use bias in linear projections.
    public let useBias: Bool

    /// Whether to use bias in the 1D convolution.
    public let useConvBias: Bool

    /// RMS norm epsilon for mixer normalization (Falcon-Mamba uses this).
    public let mixerRmsEps: Float

    /// Whether to apply RMS norm to B, C, dt (Falcon-Mamba style).
    public let useBCDtRms: Bool

    public init(
        hiddenSize: Int,
        intermediateSize: Int,
        stateSize: Int = 16,
        convKernel: Int = 4,
        timeStepRank: Int? = nil,
        useBias: Bool = false,
        useConvBias: Bool = true,
        mixerRmsEps: Float = 1e-6,
        useBCDtRms: Bool = false
    ) {
        self.hiddenSize = hiddenSize
        self.intermediateSize = intermediateSize
        self.stateSize = stateSize
        self.convKernel = convKernel
        self.timeStepRank = timeStepRank ?? Int(ceil(Double(hiddenSize) / 16.0))
        self.useBias = useBias
        self.useConvBias = useConvBias
        self.mixerRmsEps = mixerRmsEps
        self.useBCDtRms = useBCDtRms
    }

    /// Parse MambaConfig from a model's config.json dictionary.
    /// Checks both top-level keys and `ssm_cfg` / `mamba_config` sub-dicts.
    public static func from(config: [String: Any]) -> MambaConfig? {
        // Look for Mamba-specific keys in various locations
        let ssmCfg = config["ssm_cfg"] as? [String: Any]
            ?? config["mamba_config"] as? [String: Any]
            ?? config

        func get<T>(_ key: String, default defaultVal: T) -> T {
            (ssmCfg[key] as? T) ?? (config[key] as? T) ?? defaultVal
        }

        let hiddenSize: Int = get("hidden_size", default: 0)
        guard hiddenSize > 0 else { return nil }

        let intermediateSize: Int = get("intermediate_size", default: hiddenSize * 2)
        let stateSize: Int = get("state_size", default: get("d_state", default: 16))
        let convKernel: Int = get("conv_kernel", default: get("d_conv", default: 4))
        let useBias: Bool = get("use_bias", default: get("bias", default: false))
        let useConvBias: Bool = get("use_conv_bias", default: get("conv_bias", default: true))

        let timeStepRank: Int
        if let rank = ssmCfg["time_step_rank"] as? Int ?? config["time_step_rank"] as? Int {
            timeStepRank = rank
        } else {
            timeStepRank = Int(ceil(Double(hiddenSize) / 16.0))
        }

        let useBCDtRms: Bool = get("use_bcdt_rms", default: false)
        let mixerRmsEps: Float = get("mixer_rms_eps", default: 1e-6)

        return MambaConfig(
            hiddenSize: hiddenSize,
            intermediateSize: intermediateSize,
            stateSize: stateSize,
            convKernel: convKernel,
            timeStepRank: timeStepRank,
            useBias: useBias,
            useConvBias: useConvBias,
            mixerRmsEps: mixerRmsEps,
            useBCDtRms: useBCDtRms
        )
    }
}

// MARK: - SSM State

/// Mutable SSM state for a single Mamba layer during inference.
/// Contains the 1D convolution cache and the recurrent SSM hidden state.
///
/// - `convState`: [B, convKernel-1, intermediateSize] — sliding window for causal conv1d
/// - `ssmState`:  [B, intermediateSize, stateSize]    — discrete state space hidden state
public final class MambaState {
    public var convState: MLXArray?   // [B, K-1, D_inner]
    public var ssmState: MLXArray?    // [B, D_inner, N]

    public init() {}

    /// Reset state for a new sequence.
    public func reset() {
        convState = nil
        ssmState = nil
    }

    /// Export state as SSMStateLayer for caching.
    public func export() -> SSMStateLayer {
        var arrays: [MLXArray] = []
        if let conv = convState { arrays.append(conv) }
        if let ssm = ssmState { arrays.append(ssm) }
        return SSMStateLayer(state: arrays, isCumulative: true)
    }

    /// Import state from a cached SSMStateLayer.
    public func load(from layer: SSMStateLayer) {
        guard layer.state.count >= 2 else {
            convState = layer.state.first
            ssmState = nil
            return
        }
        convState = layer.state[0]
        ssmState = layer.state[1]
    }
}

// MARK: - MambaBlock

/// A single Mamba selective SSM block.
///
/// Implements the Mamba-1 architecture:
/// 1. Input projection: hidden_size -> 2 * intermediate_size (split into x and z/gate)
/// 2. Causal 1D convolution on x (depthwise, kernel_size typically 4)
/// 3. SSM computation: selective scan using A, B, C, D matrices
/// 4. Gated output: silu(z) * y
/// 5. Output projection: intermediate_size -> hidden_size
///
/// Weight key mapping (matches HuggingFace naming):
/// - `in_proj.weight`   — input projection
/// - `conv1d.weight`    — depthwise 1D convolution
/// - `conv1d.bias`      — convolution bias
/// - `x_proj.weight`    — projects x to (dt, B, C)
/// - `dt_proj.weight`   — time step projection
/// - `dt_proj.bias`     — time step bias
/// - `out_proj.weight`  — output projection
/// - `A_log`            — log of state transition matrix A
/// - `D`                — skip connection coefficient
public class MambaBlock: Module {

    let config: MambaConfig
    let intermediateSize: Int
    let stateSize: Int
    let timeStepRank: Int
    let convKernelSize: Int

    // Learnable parameters
    @ModuleInfo(key: "in_proj") var inProj: Linear
    @ModuleInfo(key: "conv1d") var conv1d: Conv1d
    @ModuleInfo(key: "x_proj") var xProj: Linear
    @ModuleInfo(key: "dt_proj") var dtProj: Linear
    @ModuleInfo(key: "out_proj") var outProj: Linear

    /// Log of state transition matrix A: [intermediateSize, stateSize]
    var aLog: MLXArray

    /// Skip connection coefficient D: [intermediateSize]
    var dParam: MLXArray

    public init(_ config: MambaConfig) {
        self.config = config
        self.intermediateSize = config.intermediateSize
        self.stateSize = config.stateSize
        self.timeStepRank = config.timeStepRank
        self.convKernelSize = config.convKernel

        // Input projection: hidden -> 2*inner (split into x and gate z)
        self._inProj.wrappedValue = Linear(
            config.hiddenSize, config.intermediateSize * 2,
            bias: config.useBias
        )

        // Depthwise 1D convolution
        self._conv1d.wrappedValue = Conv1d(
            inputChannels: config.intermediateSize,
            outputChannels: config.intermediateSize,
            kernelSize: config.convKernel,
            groups: config.intermediateSize,
            bias: config.useConvBias
        )

        // x -> (dt, B, C) projection
        self._xProj.wrappedValue = Linear(
            config.intermediateSize,
            config.timeStepRank + 2 * config.stateSize,
            bias: false
        )

        // dt rank -> intermediate_size projection
        self._dtProj.wrappedValue = Linear(
            config.timeStepRank, config.intermediateSize,
            bias: true
        )

        // Output projection: inner -> hidden
        self._outProj.wrappedValue = Linear(
            config.intermediateSize, config.hiddenSize,
            bias: config.useBias
        )

        // Initialize A_log: log of [1, 2, ..., stateSize] repeated for each inner dim
        // Shape: [intermediateSize, stateSize]
        let aRange = MLXArray.arange(1.0, Double(config.stateSize + 1))
            .reshaped(1, config.stateSize)
        let aRepeated = tiled(aRange, repetitions: [config.intermediateSize, 1])
        self.aLog = log(aRepeated)

        // D: skip connection coefficient, initialized to ones
        self.dParam = MLXArray.ones([config.intermediateSize])
    }

    /// Perform one SSM step (single token).
    ///
    /// Implements selective scan for a single time step:
    /// - Project x to (delta, B, C)
    /// - Discretize A using delta: A_bar = exp(delta * A)
    /// - Update state: state = A_bar * state + delta * x * B
    /// - Output: y = state @ C + D * x
    ///
    /// - Parameters:
    ///   - x: input tensor [B, intermediateSize]
    ///   - negA: negative exponential of A_log: [intermediateSize, stateSize]
    ///   - state: current SSM state [B, intermediateSize, stateSize], or nil
    /// - Returns: (output [B, intermediateSize], newState [B, intermediateSize, stateSize])
    func ssmStep(_ x: MLXArray, negA: MLXArray, state: MLXArray?) -> (MLXArray, MLXArray) {
        // Project x to (delta, B, C)
        let deltaBC = xProj(x)
        let splitIndices = [timeStepRank, timeStepRank + stateSize]
        let parts = split(deltaBC, indices: splitIndices, axis: -1)
        var delta = parts[0]   // [B, timeStepRank]
        let bMat = parts[1]    // [B, stateSize]
        let cMat = parts[2]    // [B, stateSize]

        // Project delta to full intermediate size and apply softplus
        delta = softplus(dtProj(delta))  // [B, intermediateSize]

        // Compute new state contribution: delta * x * B
        // delta * x: [B, intermediateSize] -> expand to [B, intermediateSize, 1]
        // B: [B, stateSize] -> expand to [B, 1, stateSize]
        let deltaX = expandedDimensions(delta * x, axis: -1)  // [B, D_inner, 1]
        let bExpanded = expandedDimensions(bMat, axis: 1)      // [B, 1, N]
        var newState = deltaX * bExpanded                       // [B, D_inner, N]

        // Add decayed previous state: state * exp(delta * A)
        if let prevState = state {
            let deltaExpanded = expandedDimensions(delta, axis: -1)  // [B, D_inner, 1]
            let decay = exp(deltaExpanded * negA)                    // [B, D_inner, N] (broadcast)
            newState = newState + prevState * decay
        }

        // Output: y = state @ C + D * x
        let cExpanded = expandedDimensions(cMat, axis: -1)  // [B, N, 1]
        let y = matmul(newState, cExpanded).squeezed(axis: -1)  // [B, D_inner]
        let output = y + dParam * x

        return (output, newState)
    }

    /// Forward pass through the Mamba block.
    ///
    /// Processes an input sequence through:
    /// 1. Linear projection -> (x, z) split
    /// 2. Causal 1D convolution on x
    /// 3. Sequential SSM scan over time steps
    /// 4. Gated output: silu(z) * y
    /// 5. Output projection
    ///
    /// - Parameters:
    ///   - x: input hidden states [B, seqLen, hiddenSize]
    ///   - state: MambaState containing conv cache and SSM state
    /// - Returns: output hidden states [B, seqLen, hiddenSize]
    public func callAsFunction(_ x: MLXArray, state: MambaState) -> MLXArray {
        let seqLen = x.dim(1)

        // 1. Input projection: [B, T, hidden] -> [B, T, 2*inner]
        let xz = inProj(x)
        let xzParts = split(xz, parts: 2, axis: -1)
        var xInput = xzParts[0]  // [B, T, inner]
        let z = xzParts[1]        // [B, T, inner]

        // 2. Causal 1D convolution
        let k = convKernelSize
        let xFull: MLXArray
        if let convCache = state.convState {
            // Concatenate conv cache with new input along time axis
            xFull = concatenated([convCache, xInput], axis: 1)
        } else {
            // Pad the left with zeros for the initial sequence
            let widths: [IntOrPair] = [[0, 0], [k - 1, 0], [0, 0]]
            xFull = padded(xInput, widths: widths)
        }

        // Update conv cache: keep last (K-1) time steps
        let cacheStart = xFull.dim(1) - (k - 1)
        state.convState = xFull[0..., cacheStart..., 0...]

        // Apply convolution and activation
        let convOut = conv1d(xFull)  // [B, T, inner]
        xInput = silu(convOut)

        // 3. SSM scan: process each time step sequentially
        let negA = -exp(aLog)  // [inner, N] -> negative A for decay

        var outputs: [MLXArray] = []
        var currentState = state.ssmState  // [B, inner, N] or nil

        for t in 0..<seqLen {
            let xt = xInput[0..., t, 0...]  // [B, inner]
            let (yt, newState) = ssmStep(xt, negA: negA, state: currentState)
            outputs.append(yt)
            currentState = newState
        }

        // Update SSM state
        state.ssmState = currentState

        // Stack outputs: list of [B, inner] -> [B, T, inner]
        let y = stacked(outputs, axis: 1)

        // 4. Gated output: silu(z) * y
        let gated = silu(z) * y

        // 5. Output projection: [B, T, inner] -> [B, T, hidden]
        return outProj(gated)
    }
}

// MARK: - MambaResidualBlock

/// A Mamba block with pre-norm and residual connection.
///
/// Weight key mapping:
/// - `mixer.*` -> MambaBlock sub-module
/// - `norm.weight` -> RMS normalization
public class MambaResidualBlock: Module {

    @ModuleInfo(key: "mixer") var mixer: MambaBlock
    @ModuleInfo(key: "norm") var norm: RMSNorm

    public init(_ config: MambaConfig) {
        self._mixer.wrappedValue = MambaBlock(config)
        self._norm.wrappedValue = RMSNorm(dimensions: config.hiddenSize, eps: config.mixerRmsEps)
    }

    /// Forward pass: residual + mixer(norm(x)).
    public func callAsFunction(_ x: MLXArray, state: MambaState) -> MLXArray {
        x + mixer(norm(x), state: state)
    }
}
