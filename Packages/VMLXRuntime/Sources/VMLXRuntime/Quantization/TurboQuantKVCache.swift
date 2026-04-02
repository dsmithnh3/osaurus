import Foundation
import MLX

/// Phase of the TurboQuant KV cache lifecycle.
public enum TQPhase: Sendable {
    case fill
    case compressed
}

/// TurboQuant-backed live KV cache for a single attention layer.
/// Keeps the prefill prefix compressed after the prefill boundary and only
/// accumulates new decode tokens in a small float window.
public final class TurboQuantKVCache: VMLXBaseKVCache, @unchecked Sendable {

    public private(set) var phase: TQPhase = .fill

    private var floatKeys: MLXArray?
    private var floatValues: MLXArray?

    public private(set) var compressedKeys: EncodedKeys?
    public private(set) var compressedValues: EncodedValues?

    private var decodedKeyBuffer: MLXArray?
    private var decodedValueBuffer: MLXArray?

    private var floatWindowKeys: MLXArray?
    private var floatWindowValues: MLXArray?

    public let config: TurboQuantConfig
    public let layerIndex: Int
    public let totalLayers: Int
    public let keyBits: Int?
    public let valueBits: Int?

    public init(config: TurboQuantConfig, layerIndex: Int, totalLayers: Int) {
        self.config = config
        self.layerIndex = layerIndex
        self.totalLayers = totalLayers
        self.keyBits = config.keyBits(forLayer: layerIndex, totalLayers: totalLayers)
        self.valueBits = config.valueBits(forLayer: layerIndex, totalLayers: totalLayers)
        super.init()
    }

    private func restoreEncoderState(
        encodedKeys: EncodedKeys,
        encodedValues: EncodedValues,
        options: VMLXCacheRestoreOptions
    ) -> TurboQuantEncoder.EncoderState {
        if let turboQuantState = options.turboQuantState {
            return turboQuantState
        }
        return TurboQuantEncoder.EncoderState(
            dim: encodedKeys.shape.last ?? 128,
            keyBits: encodedKeys.indexBits + 1,
            valueBits: encodedValues.indexBits,
            seed: encodedKeys.seed
        )
    }

    private func resetToEmpty() {
        phase = .fill
        floatKeys = nil
        floatValues = nil
        compressedKeys = nil
        compressedValues = nil
        decodedKeyBuffer = nil
        decodedValueBuffer = nil
        floatWindowKeys = nil
        floatWindowValues = nil
        offset = 0
    }

    private func loadFillState(keys: MLXArray, values: MLXArray) {
        phase = .fill
        floatKeys = keys
        floatValues = values
        compressedKeys = nil
        compressedValues = nil
        decodedKeyBuffer = nil
        decodedValueBuffer = nil
        floatWindowKeys = nil
        floatWindowValues = nil
        offset = keys.dim(2)
    }

    private func installCompressedState(
        encodedKeys: EncodedKeys,
        encodedValues: EncodedValues,
        offset: Int,
        state: TurboQuantEncoder.EncoderState
    ) {
        compressedKeys = encodedKeys
        compressedValues = encodedValues
        decodedKeyBuffer = TurboQuantEncoder.decodeKeys(encodedKeys, state: state)
        decodedValueBuffer = TurboQuantEncoder.decodeValues(encodedValues, state: state)
        floatKeys = nil
        floatValues = nil
        floatWindowKeys = nil
        floatWindowValues = nil
        phase = .compressed
        self.offset = offset
    }

    private func currentFloatKV() -> (MLXArray, MLXArray)? {
        guard let keys = getKeys(), let values = getValues() else { return nil }
        return (keys, values)
    }

    public override func innerState() -> [MLXArray] {
        var arrays: [MLXArray] = []
        if let floatKeys { arrays.append(floatKeys) }
        if let floatValues { arrays.append(floatValues) }
        if let compressedKeys {
            arrays.append(compressedKeys.indicesPacked)
            arrays.append(compressedKeys.qjlPacked)
            arrays.append(compressedKeys.residualNorms)
            arrays.append(compressedKeys.vectorNorms)
            if let sinkData = compressedKeys.sinkData {
                arrays.append(sinkData)
            }
        }
        if let compressedValues {
            arrays.append(compressedValues.indicesPacked)
            arrays.append(compressedValues.vectorNorms)
            if let sinkData = compressedValues.sinkData {
                arrays.append(sinkData)
            }
        }
        if let decodedKeyBuffer { arrays.append(decodedKeyBuffer) }
        if let decodedValueBuffer { arrays.append(decodedValueBuffer) }
        if let floatWindowKeys { arrays.append(floatWindowKeys) }
        if let floatWindowValues { arrays.append(floatWindowValues) }
        return arrays
    }

    public func appendFloat(keys: MLXArray, values: MLXArray) {
        precondition(phase == .fill, "Cannot append float data in compressed phase")

        if let existingKeys = floatKeys, let existingValues = floatValues {
            floatKeys = concatenated([existingKeys, keys], axis: 2)
            floatValues = concatenated([existingValues, values], axis: 2)
        } else {
            floatKeys = keys
            floatValues = values
        }

        offset += keys.shape[2]
    }

    @discardableResult
    public override func finalizePrefillIfNeeded() -> Bool {
        // Already compressed: do not re-quantize. The float decode window (if present)
        // is intentionally kept as float for low-overhead single-token accumulation.
        // Re-quantizing here would destroy the window and waste encode/decode cycles.
        if phase == .compressed {
            return false
        }

        guard let keyBits, let valueBits,
              let (keys, values) = currentFloatKV(),
              keys.ndim == 4,
              values.ndim == 4,
              offset > 0 else {
            return false
        }

        let state = TurboQuantEncoder.EncoderState(
            dim: keys.dim(keys.ndim - 1),
            keyBits: keyBits,
            valueBits: valueBits,
            seed: config.seed
        )

        let preservedSinkTokens = phase == .fill ? TurboQuantEncoder.defaultSinkTokens : 0
        let encodedKeys = TurboQuantEncoder.encodeKeys(
            keys,
            state: state,
            sinkTokens: preservedSinkTokens
        )
        let encodedValues = TurboQuantEncoder.encodeValues(
            values,
            state: state,
            sinkTokens: preservedSinkTokens
        )
        installCompressedState(
            encodedKeys: encodedKeys,
            encodedValues: encodedValues,
            offset: keys.dim(2),
            state: state
        )
        return true
    }

    public func compress() {
        _ = finalizePrefillIfNeeded()
    }

    public func appendDecodeTokens(newKeys: MLXArray, newValues: MLXArray) {
        guard phase == .compressed else {
            appendFloat(keys: newKeys, values: newValues)
            return
        }

        offset += newKeys.dim(2)
        if let existingKeys = floatWindowKeys, let existingValues = floatWindowValues {
            floatWindowKeys = concatenated([existingKeys, newKeys], axis: 2)
            floatWindowValues = concatenated([existingValues, newValues], axis: 2)
        } else {
            floatWindowKeys = newKeys
            floatWindowValues = newValues
        }
    }

    public func getKeys() -> MLXArray? {
        switch phase {
        case .compressed:
            if let decodedKeyBuffer {
                if let floatWindowKeys {
                    return concatenated([decodedKeyBuffer, floatWindowKeys], axis: 2)
                }
                return decodedKeyBuffer
            }
            return floatWindowKeys
        case .fill:
            return floatKeys
        }
    }

    public func getValues() -> MLXArray? {
        switch phase {
        case .compressed:
            if let decodedValueBuffer {
                if let floatWindowValues {
                    return concatenated([decodedValueBuffer, floatWindowValues], axis: 2)
                }
                return decodedValueBuffer
            }
            return floatWindowValues
        case .fill:
            return floatValues
        }
    }

    public var isEmpty: Bool {
        offset == 0
    }

    public override func update(keys: MLXArray, values: MLXArray) -> (MLXArray, MLXArray) {
        switch phase {
        case .fill:
            appendFloat(keys: keys, values: values)
        case .compressed:
            appendDecodeTokens(newKeys: keys, newValues: values)
        }

        guard let currentKeys = getKeys(), let currentValues = getValues() else {
            fatalError("TurboQuantKVCache has no readable KV state after update")
        }
        return (currentKeys, currentValues)
    }

    public override var state: [MLXArray] {
        get {
            guard let keys = getKeys(), let values = getValues() else { return [] }
            if offset < keys.dim(2) {
                return [
                    keys[.ellipsis, ..<offset, 0...],
                    values[.ellipsis, ..<offset, 0...],
                ]
            }
            return [keys, values]
        }
        set {
            if newValue.count >= 2 {
                loadFillState(keys: newValue[0], values: newValue[1])
            } else {
                resetToEmpty()
            }
        }
    }

    public override var isTrimmable: Bool { true }

    public override var estimatedBytes: Int {
        var total = 0
        if let floatKeys { total += floatKeys.nbytes }
        if let floatValues { total += floatValues.nbytes }
        if let compressedKeys { total += compressedKeys.estimatedBytes }
        if let compressedValues { total += compressedValues.estimatedBytes }
        if let decodedKeyBuffer { total += decodedKeyBuffer.nbytes }
        if let decodedValueBuffer { total += decodedValueBuffer.nbytes }
        if let floatWindowKeys { total += floatWindowKeys.nbytes }
        if let floatWindowValues { total += floatWindowValues.nbytes }
        return total
    }

    @discardableResult
    public override func trim(_ n: Int) -> Int {
        let trimmed = min(offset, n)
        guard trimmed > 0 else { return 0 }

        let targetOffset = offset - trimmed
        guard targetOffset > 0 else {
            resetToEmpty()
            return trimmed
        }

        // Fast path: when compressed, try to slice the compressed representation
        // directly instead of decode→truncate→re-encode (which is lossy).
        if phase == .compressed,
           let ek = compressedKeys,
           let ev = compressedValues {
            let compressedTokens = TurboQuantLayerCache.totalTokenCount(for: ek)
            let windowTokens = floatWindowKeys?.dim(2) ?? 0

            if targetOffset <= compressedTokens {
                // Target is within compressed region — slice compressed data directly
                if let sliced = TurboQuantLayerCache.sliceCompressedAttention(ek, ev, range: 0..<targetOffset) {
                    if case .compressedAttention(let sek, let sev, _) = sliced {
                        let state = TurboQuantEncoder.EncoderState(
                            dim: sek.shape.last ?? 128,
                            keyBits: sek.indexBits + 1,
                            valueBits: sev.indexBits,
                            seed: sek.seed
                        )
                        installCompressedState(
                            encodedKeys: sek,
                            encodedValues: sev,
                            offset: targetOffset,
                            state: state
                        )
                        return trimmed
                    }
                }
                // Slice failed — fall through to decode path
            } else if targetOffset <= compressedTokens + windowTokens, windowTokens > 0 {
                // Target is within float window — just truncate the window
                let windowTarget = targetOffset - compressedTokens
                floatWindowKeys = floatWindowKeys?[.ellipsis, ..<windowTarget, 0...]
                floatWindowValues = floatWindowValues?[.ellipsis, ..<windowTarget, 0...]
                offset = targetOffset
                return trimmed
            }
        }

        // Slow path: decode full KV, truncate, re-encode (lossy but always works)
        guard let (keys, values) = currentFloatKV() else {
            resetToEmpty()
            return trimmed
        }

        let wasCompressed = phase == .compressed
        let trimmedKeys = keys[.ellipsis, ..<targetOffset, 0...]
        let trimmedValues = values[.ellipsis, ..<targetOffset, 0...]
        loadFillState(keys: trimmedKeys, values: trimmedValues)
        if wasCompressed {
            _ = finalizePrefillIfNeeded()
        }
        return trimmed
    }

    public override func copy() -> any VMLXKVCache {
        let new = TurboQuantKVCache(config: config, layerIndex: layerIndex, totalLayers: totalLayers)
        new.phase = phase
        new.floatKeys = floatKeys.map { $0[.ellipsis] }
        new.floatValues = floatValues.map { $0[.ellipsis] }
        new.compressedKeys = compressedKeys
        new.compressedValues = compressedValues
        new.decodedKeyBuffer = decodedKeyBuffer.map { $0[.ellipsis] }
        new.decodedValueBuffer = decodedValueBuffer.map { $0[.ellipsis] }
        new.floatWindowKeys = floatWindowKeys.map { $0[.ellipsis] }
        new.floatWindowValues = floatWindowValues.map { $0[.ellipsis] }
        new.offset = offset
        return new
    }

    public override func exportCacheEntry() -> LayerCacheEntry? {
        if phase == .compressed,
           let compressedKeys,
           let compressedValues {
            if let floatWindowKeys, let floatWindowValues {
                let prefixEntry = LayerCacheEntry.compressedAttention(
                    compressedKeys,
                    compressedValues,
                    TurboQuantLayerCache.totalTokenCount(for: compressedKeys)
                )
                if let tailEntry = TurboQuantLayerCache.encodeAttentionLayer(
                    keys: floatWindowKeys,
                    values: floatWindowValues,
                    config: config,
                    layerIndex: layerIndex,
                    totalLayers: totalLayers,
                    sinkTokens: 0
                ),
                   let mergedEntry = TurboQuantLayerCache.mergeCompressedAttention([prefixEntry, tailEntry]) {
                    return mergedEntry
                }
                // TQ merge failed — falling back to full float export.
                // This silently destroys compression for this layer.
                #if DEBUG
                print("[TQ] exportCacheEntry: compressed merge failed for layer \(layerIndex), falling back to float (window: \(floatWindowKeys.dim(2)) tokens)")
                #endif
            } else {
                return .compressedAttention(compressedKeys, compressedValues, offset)
            }
        }

        guard let (keys, values) = currentFloatKV() else { return nil }
        return .attention(KVCacheLayer(keys: keys, values: values, offset: offset))
    }

    @discardableResult
    public override func restore(from entry: LayerCacheEntry, options: VMLXCacheRestoreOptions = .init()) -> Bool {
        switch entry {
        case .attention(let kv):
            loadFillState(keys: kv.keys, values: kv.values)
            return true
        case .compressedAttention(let encodedKeys, let encodedValues, let offset):
            let state = restoreEncoderState(
                encodedKeys: encodedKeys,
                encodedValues: encodedValues,
                options: options
            )
            installCompressedState(
                encodedKeys: encodedKeys,
                encodedValues: encodedValues,
                offset: offset,
                state: state
            )
            return true
        case .ssm, .placeholder:
            return false
        }
    }

    public func toKVCacheLayer() -> KVCacheLayer? {
        guard let (keys, values) = currentFloatKV() else { return nil }
        return KVCacheLayer(keys: keys, values: values, offset: offset)
    }

    public static func fromKVCacheLayer(
        _ layer: KVCacheLayer,
        config: TurboQuantConfig,
        layerIndex: Int,
        totalLayers: Int
    ) -> TurboQuantKVCache {
        let tqCache = TurboQuantKVCache(config: config, layerIndex: layerIndex, totalLayers: totalLayers)
        tqCache.loadFillState(keys: layer.keys, values: layer.values)
        return tqCache
    }
}
