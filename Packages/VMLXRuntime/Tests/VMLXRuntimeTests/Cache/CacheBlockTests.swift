import Testing
import MLX
@testable import VMLXRuntime

@Suite("CacheBlock")
struct CacheBlockTests {
    @Test("Block lifecycle")
    func blockLifecycle() {
        let block = CacheBlock(blockId: 1, blockSize: 64)
        #expect(block.refCount == 0)
        #expect(!block.isFull(blockSize: 64))
        block.refCount = 1; block.tokenCount = 64
        #expect(block.isFull(blockSize: 64))
        #expect(!block.isShared)
        block.refCount = 2
        #expect(block.isShared)
    }

    @Test("Block hash chain determinism")
    func hashChain() {
        let h1 = CacheBlock.computeBlockHash(parentHash: nil, tokenIds: [1,2,3])
        let h2 = CacheBlock.computeBlockHash(parentHash: h1, tokenIds: [4,5,6])
        #expect(h1 != h2)
        #expect(h1.count == 32)
        let h1b = CacheBlock.computeBlockHash(parentHash: nil, tokenIds: [1,2,3])
        #expect(h1 == h1b)
        let h2b = CacheBlock.computeBlockHash(parentHash: nil, tokenIds: [4,5,6])
        #expect(h2 != h2b)  // different parent
    }

    @Test("Block reset clears state")
    func resetBlock() {
        let block = CacheBlock(blockId: 5, blockSize: 64)
        block.refCount = 3; block.tokenCount = 50
        block.blockHash = CacheBlock.computeBlockHash(parentHash: nil, tokenIds: [1])
        block.reset()
        #expect(block.refCount == 0)
        #expect(block.tokenCount == 0)
        #expect(block.blockHash == nil)
    }
}

@Suite("FreeBlockQueue")
struct FreeBlockQueueTests {
    @Test("FIFO order")
    func fifo() {
        let q = FreeBlockQueue()
        let b1 = CacheBlock(blockId: 1, blockSize: 64)
        let b2 = CacheBlock(blockId: 2, blockSize: 64)
        let b3 = CacheBlock(blockId: 3, blockSize: 64)
        q.append(b1); q.append(b2); q.append(b3)
        #expect(q.count == 3)
        #expect(q.popleft()?.blockId == 1)
        #expect(q.count == 2)
    }

    @Test("Remove from middle")
    func removeMiddle() {
        let q = FreeBlockQueue()
        let b1 = CacheBlock(blockId: 1, blockSize: 64)
        let b2 = CacheBlock(blockId: 2, blockSize: 64)
        let b3 = CacheBlock(blockId: 3, blockSize: 64)
        q.append(b1); q.append(b2); q.append(b3)
        q.remove(b2)
        #expect(q.count == 2)
        #expect(q.popleft()?.blockId == 1)
        #expect(q.popleft()?.blockId == 3)
    }

    @Test("Batch allocate")
    func batchAllocate() {
        let q = FreeBlockQueue()
        for i in 0..<10 { q.append(CacheBlock(blockId: i, blockSize: 64)) }
        let batch = q.popleftN(5)
        #expect(batch.count == 5)
        #expect(batch[0].blockId == 0)
        #expect(batch[4].blockId == 4)
        #expect(q.count == 5)
    }

    @Test("Empty queue returns nil")
    func emptyQueue() {
        let q = FreeBlockQueue()
        #expect(q.popleft() == nil)
    }
}
