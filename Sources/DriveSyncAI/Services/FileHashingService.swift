// Copyright 2026 Amit Chorasiya. All rights reserved.
// Licensed under the Business Source License 1.1. See LICENSE file.

import CryptoKit
import Darwin
import Foundation

enum FileHashingService {
    private static let chunkSize = 1024 * 1024  // 1MB
    private static let partialHeadSize = 4 * 1024   // 4KB
    private static let partialTailSize = 4 * 1024   // 4KB
    private static let mmapThreshold: UInt64 = 4 * 1024 * 1024  // 4MB
    private static let mmapWindowSize: UInt64 = 64 * 1024 * 1024  // 64MB

    /// Compute full SHA256 hash of a file, reading in 1MB chunks.
    static func sha256(of url: URL) async throws -> String {
        let fileSize = try fileSize(of: url)
        if fileSize >= mmapThreshold {
            do {
                return try sha256Mmap(of: url, fileSize: fileSize)
            } catch {
                // If mmap fails on a file, gracefully fall back to the proven chunked path.
                return try sha256Chunked(of: url)
            }
        }
        return try sha256Chunked(of: url)
    }

    private static func sha256Chunked(of url: URL) throws -> String {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        var hasher = SHA256()
        while true {
            let data = try handle.read(upToCount: chunkSize)
            guard let chunk = data, !chunk.isEmpty else { break }
            hasher.update(data: chunk)
        }
        let digest = hasher.finalize()
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    private static func sha256Mmap(of url: URL, fileSize: UInt64) throws -> String {
        guard fileSize > 0 else {
            return SHA256.hash(data: Data()).map { String(format: "%02x", $0) }.joined()
        }

        let fd = open(url.path, O_RDONLY)
        guard fd >= 0 else {
            throw posixError(code: errno, context: "open failed for \(url.path)")
        }
        defer { close(fd) }

        let pageSize = UInt64(getpagesize())
        var offset: UInt64 = 0
        var hasher = SHA256()

        while offset < fileSize {
            let remaining = fileSize - offset
            let requested = min(mmapWindowSize, remaining)

            let alignedOffset = (offset / pageSize) * pageSize
            let delta = offset - alignedOffset
            let mapLength = requested + delta

            let mapped = mmap(nil, Int(mapLength), PROT_READ, MAP_PRIVATE, fd, off_t(alignedOffset))
            if mapped == MAP_FAILED {
                throw posixError(code: errno, context: "mmap failed for \(url.path)")
            }
            _ = madvise(mapped, Int(mapLength), MADV_SEQUENTIAL)

            let dataStart = mapped!.advanced(by: Int(delta))
            let chunk = Data(bytesNoCopy: dataStart, count: Int(requested), deallocator: .none)
            hasher.update(data: chunk)
            _ = munmap(mapped, Int(mapLength))

            offset += requested
        }

        let digest = hasher.finalize()
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    private static func fileSize(of url: URL) throws -> UInt64 {
        let attrs = try FileManager.default.attributesOfItem(atPath: url.path)
        return (attrs[.size] as? NSNumber)?.uint64Value ?? 0
    }

    private static func posixError(code: Int32, context: String) -> NSError {
        NSError(
            domain: NSPOSIXErrorDomain,
            code: Int(code),
            userInfo: [NSLocalizedDescriptionKey: "\(context): \(String(cString: strerror(code)))"]
        )
    }

    /// Compute partial hash: first 4KB + last 4KB + file size.
    /// Returns a composite key string for quick duplicate detection.
    static func partialHash(of url: URL, fileSize: UInt64) async throws -> String {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        var hasher = SHA256()
        let headSize = min(UInt64(partialHeadSize), fileSize)
        if headSize > 0 {
            let headData = try handle.read(upToCount: Int(headSize))
            if let head = headData {
                hasher.update(data: head)
            }
        }
        if fileSize > UInt64(partialHeadSize) + UInt64(partialTailSize) {
            try handle.seek(toOffset: fileSize - UInt64(partialTailSize))
            let tailData = try handle.read(upToCount: partialTailSize)
            if let tail = tailData {
                hasher.update(data: tail)
            }
        }
        hasher.update(data: withUnsafeBytes(of: fileSize.littleEndian) { Data($0) })
        let digest = hasher.finalize()
        return digest.map { String(format: "%02x", $0) }.joined() + "_\(fileSize)"
    }

    /// Hash multiple files in parallel using the CPU lane of the scheduler.
    static func hashFiles(_ urls: [URL], using scheduler: AdaptiveScheduler) async throws -> [URL: String] {
        let results = try await scheduler.runParallelCPU(items: urls) { url in
            (url, try await sha256(of: url))
        }
        return Dictionary(uniqueKeysWithValues: results)
    }

    /// Hash multiple files with partial hash.
    static func partialHashFiles(_ files: [FileInfo], using scheduler: AdaptiveScheduler) async throws -> [String: [FileInfo]] {
        let results = try await scheduler.runParallelCPU(items: files) { file in
            let hash = try await partialHash(of: file.url, fileSize: file.size)
            return (hash, file)
        }
        var grouped: [String: [FileInfo]] = [:]
        for (hash, file) in results {
            grouped[hash, default: []].append(file)
        }
        return grouped
    }
}
