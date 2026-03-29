import Foundation

public final class BlockHashMap: @unchecked Sendable {
    private var map: [BlockHash: CacheBlock] = [:]
    public init() {}
    public func getBlock(hash: BlockHash) -> CacheBlock? { map[hash] }
    public func insert(hash: BlockHash, block: CacheBlock) { map[hash] = block }
    public func pop(hash: BlockHash, blockId: Int) -> CacheBlock? {
        guard let block = map[hash], block.blockId == blockId else { return nil }
        map.removeValue(forKey: hash)
        return block
    }
    public func contains(hash: BlockHash) -> Bool { map[hash] != nil }
    public var count: Int { map.count }
    public func removeAll() { map.removeAll() }
}
