// Copyright 2026 Amit Chorasiya. All rights reserved.
// Licensed under the Business Source License 1.1. See LICENSE file.

import Foundation

actor AdaptiveScheduler {
    private let cpuLimit: Int
    private var ioLimit: Int
    private var activeIOCount: Int = 0
    private var ioWaiters: [CheckedContinuation<Void, Never>] = []

    init(ioLimit: Int = 2) {
        self.cpuLimit = ProcessInfo.processInfo.processorCount
        self.ioLimit = max(1, ioLimit)
    }

    func updateIOLimit(for drives: [DriveInfo]) {
        guard !drives.isEmpty else { return }
        let minIO = drives.map(\.maxConcurrentIO).min() ?? 2
        ioLimit = max(1, minIO)
    }

    func runCPUTask<T: Sendable>(_ work: @Sendable () async throws -> T) async throws -> T {
        try await work()
    }

    func runIOTask<T: Sendable>(_ work: @Sendable () async throws -> T) async throws -> T {
        await waitForIOCapacity()
        activeIOCount += 1
        defer {
            activeIOCount -= 1
            resumeNextIOWaiterIfNeeded()
        }
        return try await work()
    }

    func waitForIOCapacity() async {
        if activeIOCount < ioLimit {
            return
        }
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            ioWaiters.append(continuation)
        }
    }

    private func resumeNextIOWaiterIfNeeded() {
        guard activeIOCount < ioLimit, !ioWaiters.isEmpty else { return }
        let waiter = ioWaiters.removeFirst()
        waiter.resume()
    }

    func runParallelCPU<Input: Sendable, Output: Sendable>(
        items: [Input],
        transform: @escaping @Sendable (Input) async throws -> Output
    ) async throws -> [Output] {
        try await withThrowingTaskGroup(of: (Int, Output).self) { group in
            var results = ContiguousArray<Output?>(repeating: nil, count: items.count)
            var nextIndex = 0

            func addNext() {
                guard nextIndex < items.count else { return }
                let idx = nextIndex
                nextIndex += 1
                let item = items[idx]
                group.addTask {
                    let output = try await transform(item)
                    return (idx, output)
                }
            }

            for _ in 0..<min(cpuLimit, items.count) {
                addNext()
            }

            while let (idx, output) = try await group.next() {
                results[idx] = output
                addNext()
            }

            return results.map { $0! }
        }
    }

    func runParallelIO<Input: Sendable, Output: Sendable>(
        items: [Input],
        transform: @escaping @Sendable (Input) async throws -> Output
    ) async throws -> [Output] {
        try await withThrowingTaskGroup(of: Output.self) { group in
            for item in items {
                group.addTask {
                    try await self.runIOTask {
                        try await transform(item)
                    }
                }
            }
            var results: [Output] = []
            for try await result in group {
                results.append(result)
            }
            return results
        }
    }
}
