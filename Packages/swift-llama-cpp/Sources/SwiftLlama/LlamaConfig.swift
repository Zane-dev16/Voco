//
//  LlamaConfig.swift
//  LlamaSwift
//
//  Created by Piotr Gorzelany on 05/11/2024.
//

public struct LlamaConfig: Equatable, Sendable {
    public let batchSize: UInt32
    public let maxTokenCount: UInt32
    public let useGPU: Bool
    public let nThreads: UInt32
    public let nThreadsBatch: UInt32

    public init(
        batchSize: UInt32,
        maxTokenCount: UInt32,
        useGPU: Bool = true,
        nThreads: UInt32 = 2,
        nThreadsBatch: UInt32 = 2
    ) {
        self.batchSize = batchSize
        self.maxTokenCount = maxTokenCount
        self.useGPU = useGPU
        self.nThreads = nThreads
        self.nThreadsBatch = nThreadsBatch
    }
}
