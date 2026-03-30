import Testing
import MLX
@testable import VMLXRuntime

@Suite("BatchBuilder")
struct BatchBuilderTests {

    @Test("Empty batch")
    func emptyBatch() {
        let builder = BatchBuilder()
        let batch = builder.buildPrefillBatch(requests: [])
        #expect(batch.batchSize == 0)
        #expect(batch.requestIds.isEmpty)
    }

    @Test("Single request batch")
    func singleRequest() {
        let builder = BatchBuilder()
        let req = InferenceRequest(requestId: "r1", promptTokenIds: [1, 2, 3, 4, 5])
        let batch = builder.buildPrefillBatch(requests: [req])

        #expect(batch.batchSize == 1)
        #expect(batch.requestIds == ["r1"])
        #expect(batch.sequenceLengths == [5])
        #expect(batch.maxSeqLen == 5)
    }

    @Test("Multiple requests with padding")
    func multipleWithPadding() {
        let builder = BatchBuilder(padTokenId: 0)
        let r1 = InferenceRequest(requestId: "r1", promptTokenIds: [1, 2, 3])
        let r2 = InferenceRequest(requestId: "r2", promptTokenIds: [4, 5, 6, 7, 8])
        let batch = builder.buildPrefillBatch(requests: [r1, r2])

        #expect(batch.batchSize == 2)
        #expect(batch.maxSeqLen == 5)  // Padded to longest
        #expect(batch.sequenceLengths == [3, 5])
    }

    @Test("Uses remaining tokens when cached")
    func usesRemainingTokens() {
        let builder = BatchBuilder()
        var req = InferenceRequest(requestId: "r1", promptTokenIds: [1, 2, 3, 4, 5])
        req.remainingTokenIds = [4, 5]  // Cache hit — only process last 2

        let batch = builder.buildPrefillBatch(requests: [req])
        #expect(batch.sequenceLengths == [2])
    }

    @Test("Decode batch has single token per request")
    func decodeBatch() {
        let builder = BatchBuilder()
        let batch = builder.buildDecodeBatch(
            requestIds: ["r1", "r2", "r3"],
            nextTokenIds: [100, 200, 300]
        )
        #expect(batch.batchSize == 3)
        #expect(batch.sequenceLengths == [1, 1, 1])
    }

    @Test("Split batch respects max size")
    func splitBatch() {
        let builder = BatchBuilder()
        let requests = (0..<10).map { i in
            InferenceRequest(requestId: "r\(i)", promptTokenIds: [i])
        }
        let fullBatch = builder.buildPrefillBatch(requests: requests)
        let subBatches = builder.splitBatch(fullBatch, maxBatchSize: 3)

        #expect(subBatches.count == 4)  // ceil(10/3) = 4
        #expect(subBatches[0].batchSize == 3)
        #expect(subBatches[3].batchSize == 1)
    }

    @Test("Custom pad token")
    func customPadToken() {
        let builder = BatchBuilder(padTokenId: 999)
        #expect(builder.padTokenId == 999)
    }
}
