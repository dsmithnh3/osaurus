import Testing
@testable import VMLXRuntime

@Suite("BlockHashMap")
struct BlockHashMapTests {
    @Test("Insert and retrieve")
    func insertRetrieve() {
        let map = BlockHashMap()
        let block = CacheBlock(blockId: 5, blockSize: 64)
        let hash = CacheBlock.computeBlockHash(parentHash: nil, tokenIds: [1, 2, 3])
        map.insert(hash: hash, block: block)
        #expect(map.getBlock(hash: hash)?.blockId == 5)
        #expect(map.count == 1)
    }

    @Test("Pop removes")
    func pop() {
        let map = BlockHashMap()
        let block = CacheBlock(blockId: 7, blockSize: 64)
        let hash = CacheBlock.computeBlockHash(parentHash: nil, tokenIds: [10])
        map.insert(hash: hash, block: block)
        let popped = map.pop(hash: hash, blockId: 7)
        #expect(popped?.blockId == 7)
        #expect(map.getBlock(hash: hash) == nil)
    }

    @Test("Missing returns nil")
    func missing() {
        let map = BlockHashMap()
        let hash = CacheBlock.computeBlockHash(parentHash: nil, tokenIds: [99])
        #expect(map.getBlock(hash: hash) == nil)
    }

    @Test("Pop wrong blockId returns nil")
    func popWrongId() {
        let map = BlockHashMap()
        let block = CacheBlock(blockId: 3, blockSize: 64)
        let hash = CacheBlock.computeBlockHash(parentHash: nil, tokenIds: [1])
        map.insert(hash: hash, block: block)
        #expect(map.pop(hash: hash, blockId: 999) == nil)
        #expect(map.count == 1)  // Not removed
    }
}

@Suite("BlockTable")
struct BlockTableTests {
    @Test("Track blocks")
    func track() {
        var t = BlockTable(requestId: "req-1")
        t.addBlock(blockId: 0, numTokens: 64)
        t.addBlock(blockId: 1, numTokens: 30)
        #expect(t.blockIds == [0, 1])
        #expect(t.numTokens == 94)
    }

    @Test("Copy is independent")
    func copyIndependent() {
        var orig = BlockTable(requestId: "req-1")
        orig.addBlock(blockId: 0, numTokens: 64)
        let cp = orig.copy(newRequestId: "req-2")
        #expect(cp.requestId == "req-2")
        #expect(cp.blockIds == [0])
        orig.addBlock(blockId: 1, numTokens: 32)
        #expect(cp.blockIds.count == 1)
    }
}
