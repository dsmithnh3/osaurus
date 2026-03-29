import Foundation

public struct BlockTable: Sendable {
    public let requestId: String
    public private(set) var blockIds: [Int]
    public private(set) var numTokens: Int

    public init(requestId: String) {
        self.requestId = requestId
        self.blockIds = []
        self.numTokens = 0
    }

    public mutating func addBlock(blockId: Int, numTokens: Int) {
        blockIds.append(blockId)
        self.numTokens += numTokens
    }

    public func copy(newRequestId: String) -> BlockTable {
        var copy = BlockTable(requestId: newRequestId)
        copy.blockIds = self.blockIds
        copy.numTokens = self.numTokens
        return copy
    }
}
