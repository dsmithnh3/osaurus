/// O(1) doubly-linked list of free cache blocks. Front=LRU, Back=MRU.
public final class FreeBlockQueue: @unchecked Sendable {
    private let head: CacheBlock  // sentinel
    private let tail: CacheBlock  // sentinel
    public private(set) var count: Int = 0

    public init() {
        head = CacheBlock(blockId: -1, blockSize: 0)
        tail = CacheBlock(blockId: -2, blockSize: 0)
        head.nextFreeBlock = tail
        tail.prevFreeBlock = head
    }

    public func popleft() -> CacheBlock? {
        guard let block = head.nextFreeBlock, block !== tail else { return nil }
        unlink(block); count -= 1; return block
    }

    public func popleftN(_ n: Int) -> [CacheBlock] {
        var result: [CacheBlock] = []
        result.reserveCapacity(min(n, count))
        for _ in 0..<n { guard let b = popleft() else { break }; result.append(b) }
        return result
    }

    public func append(_ block: CacheBlock) {
        let prev = tail.prevFreeBlock!
        prev.nextFreeBlock = block
        block.prevFreeBlock = prev
        block.nextFreeBlock = tail
        tail.prevFreeBlock = block
        count += 1
    }

    public func remove(_ block: CacheBlock) {
        guard block.prevFreeBlock != nil, block.nextFreeBlock != nil else { return }
        unlink(block); count -= 1
    }

    private func unlink(_ block: CacheBlock) {
        block.prevFreeBlock?.nextFreeBlock = block.nextFreeBlock
        block.nextFreeBlock?.prevFreeBlock = block.prevFreeBlock
        block.prevFreeBlock = nil; block.nextFreeBlock = nil
    }
}
