// Copyright 2026 Amit Chorasiya. All rights reserved.
// Licensed under the Business Source License 1.1. See LICENSE file.

import Foundation

// MARK: - Levenshtein Distance

private func levenshteinDistance(_ s1: String, _ s2: String) -> Int {
    let a = Array(s1)
    let b = Array(s2)
    let m = a.count
    let n = b.count

    if m == 0 { return n }
    if n == 0 { return m }

    var dp = [[Int]](repeating: [Int](repeating: 0, count: n + 1), count: m + 1)

    for i in 0...m { dp[i][0] = i }
    for j in 0...n { dp[0][j] = j }

    for i in 1...m {
        for j in 1...n {
            let cost = a[i - 1] == b[j - 1] ? 0 : 1
            dp[i][j] = min(
                dp[i - 1][j] + 1,
                dp[i][j - 1] + 1,
                dp[i - 1][j - 1] + cost
            )
        }
    }
    return dp[m][n]
}

private extension String {
    var baseNameWithoutExtension: String {
        (self as NSString).deletingPathExtension
    }

    var pathExtensionLower: String {
        (self as NSString).pathExtension.lowercased()
    }

    func isSimilarName(to other: String, maxDistance: Int = 3) -> Bool {
        let b1 = baseNameWithoutExtension
        let b2 = other.baseNameWithoutExtension
        guard !b1.isEmpty || !b2.isEmpty else { return true }
        return levenshteinDistance(b1.lowercased(), b2.lowercased()) <= maxDistance
    }

    func isSameBaseNameDifferentExtension(_ other: String) -> Bool {
        let b1 = baseNameWithoutExtension
        let b2 = other.baseNameWithoutExtension
        guard !b1.isEmpty, b1.lowercased() == b2.lowercased() else { return false }
        return pathExtensionLower != other.pathExtensionLower
    }
}

private func sizeWithinPercent(_ a: UInt64, _ b: UInt64, percent: Double = 5.0) -> Bool {
    guard a > 0 || b > 0 else { return true }
    let maxSize = max(a, b)
    let minSize = min(a, b)
    let ratio = Double(minSize) / Double(maxSize)
    return ratio >= (1.0 - percent / 100.0)
}

private func datesWithinSeconds(_ d1: Date, _ d2: Date, seconds: Int = 5) -> Bool {
    abs(d1.timeIntervalSince(d2)) <= Double(seconds)
}

// MARK: - SimilarFilesService

actor SimilarFilesService {
    private let scheduler: AdaptiveScheduler

    init(scheduler: AdaptiveScheduler) {
        self.scheduler = scheduler
    }

    /// Find files that are similar but not exact duplicates.
    /// This runs AFTER exact duplicate detection and looks at the remaining unique files.
    func findSimilarFiles(
        in files: [FileInfo],
        exactDuplicateHashes: Set<String> = []
    ) async throws -> [SimilarGroup] {
        guard files.count >= 2 else { return [] }

        var allGroups: [SimilarGroup] = []
        var usedFileIds = Set<UUID>()
        let workingFiles = files

        // Strategy 1: Same name, different extension
        let sameNameDiffExtGroups = await findSameNameDiffExt(in: workingFiles)
        for group in sameNameDiffExtGroups {
            allGroups.append(group)
            usedFileIds.formUnion(group.similarFiles.map(\.fileInfo.id))
            usedFileIds.insert(group.referenceFile.id)
        }

        var remaining = workingFiles.filter { !usedFileIds.contains($0.id) }
        guard remaining.count >= 2 else { return deduplicateAndSort(allGroups) }

        // Strategy 2: Similar names (Levenshtein <= 3)
        let similarNameGroups = await findSimilarNames(in: remaining)
        for group in similarNameGroups {
            allGroups.append(group)
            usedFileIds.formUnion(group.similarFiles.map(\.fileInfo.id))
            usedFileIds.insert(group.referenceFile.id)
        }

        remaining = remaining.filter { !usedFileIds.contains($0.id) }
        guard remaining.count >= 2 else { return deduplicateAndSort(allGroups) }

        // Strategy 3: Similar size + similar name
        let similarSizeGroups = await findSimilarSize(in: remaining)
        for group in similarSizeGroups {
            if !allGroups.contains(where: { $0.id == group.id }) {
                allGroups.append(group)
                usedFileIds.formUnion(group.similarFiles.map(\.fileInfo.id))
                usedFileIds.insert(group.referenceFile.id)
            }
        }

        remaining = remaining.filter { !usedFileIds.contains($0.id) }
        guard remaining.count >= 2 else { return deduplicateAndSort(allGroups) }

        // Strategy 4: Nearby dates + similar size
        let nearbyDateGroups = await findNearbyDate(in: remaining)
        for group in nearbyDateGroups {
            allGroups.append(group)
        }

        return deduplicateAndSort(allGroups)
    }

    private func findSameNameDiffExt(in files: [FileInfo]) async -> [SimilarGroup] {
        var baseNameToFiles: [String: [FileInfo]] = [:]
        for f in files {
            let base = f.name.baseNameWithoutExtension.lowercased()
            guard !base.isEmpty else { continue }
            baseNameToFiles[base, default: []].append(f)
        }

        var groups: [SimilarGroup] = []
        for (_, filesWithSameBase) in baseNameToFiles {
            let byExt = Dictionary(grouping: filesWithSameBase, by: { $0.name.pathExtensionLower })
            guard byExt.count >= 2 else { continue }

            let allFiles = Array(byExt.values.joined())
            guard allFiles.count >= 2 else { continue }

            let reference = allFiles[0]
            let similar = allFiles.dropFirst().map { f in
                let sim = f.name.baseNameWithoutExtension.lowercased() == reference.name.baseNameWithoutExtension.lowercased() ? 1.0 : 0.8
                return SimilarFile(id: f.id, fileInfo: f, isSelected: false, similarity: sim)
            }

            groups.append(SimilarGroup(
                id: UUID(),
                referenceFile: reference,
                similarFiles: similar,
                similarityReason: .sameNameDiffExt
            ))
        }
        return groups
    }

    private func findSimilarNames(in files: [FileInfo]) async -> [SimilarGroup] {
        var groups: [SimilarGroup] = []
        var processed = Set<UUID>()

        for i in 0..<files.count {
            guard !processed.contains(files[i].id) else { continue }
            var similar: [SimilarFile] = []
            for j in 0..<files.count where i != j {
                guard !processed.contains(files[j].id) else { continue }
                if files[i].name.isSimilarName(to: files[j].name) {
                    let dist = levenshteinDistance(
                        files[i].name.baseNameWithoutExtension.lowercased(),
                        files[j].name.baseNameWithoutExtension.lowercased()
                    )
                    let sim = 1.0 - (Double(dist) / 10.0)
                    let similarity = max(0.0, min(1.0, sim))
                    similar.append(SimilarFile(id: files[j].id, fileInfo: files[j], isSelected: false, similarity: similarity))
                }
            }
            guard !similar.isEmpty else { continue }
            groups.append(SimilarGroup(
                id: UUID(),
                referenceFile: files[i],
                similarFiles: similar,
                similarityReason: .similarName
            ))
            processed.insert(files[i].id)
            for s in similar { processed.insert(s.fileInfo.id) }
        }
        return groups
    }

    private func findSimilarSize(in files: [FileInfo]) async -> [SimilarGroup] {
        var groups: [SimilarGroup] = []
        var processed = Set<UUID>()

        for i in 0..<files.count {
            guard !processed.contains(files[i].id) else { continue }
            var similar: [SimilarFile] = []
            for j in 0..<files.count where i != j {
                guard !processed.contains(files[j].id) else { continue }
                if sizeWithinPercent(files[i].size, files[j].size) && files[i].name.isSimilarName(to: files[j].name) {
                    let ratio = files[i].size > 0 ? min(Double(files[j].size), Double(files[i].size)) / max(Double(files[j].size), Double(files[i].size)) : 1.0
                    similar.append(SimilarFile(id: files[j].id, fileInfo: files[j], isSelected: false, similarity: ratio))
                }
            }
            guard !similar.isEmpty else { continue }
            groups.append(SimilarGroup(
                id: UUID(),
                referenceFile: files[i],
                similarFiles: similar,
                similarityReason: .similarSize
            ))
            processed.insert(files[i].id)
            for s in similar { processed.insert(s.fileInfo.id) }
        }
        return groups
    }

    private func findNearbyDate(in files: [FileInfo]) async -> [SimilarGroup] {
        var groups: [SimilarGroup] = []
        var processed = Set<UUID>()

        for i in 0..<files.count {
            guard !processed.contains(files[i].id) else { continue }
            var similar: [SimilarFile] = []
            for j in 0..<files.count where i != j {
                guard !processed.contains(files[j].id) else { continue }
                let dateClose = datesWithinSeconds(files[i].creationDate, files[j].creationDate)
                    || datesWithinSeconds(files[i].modificationDate, files[j].modificationDate)
                if dateClose && sizeWithinPercent(files[i].size, files[j].size) {
                    let sizeSim = sizeWithinPercent(files[i].size, files[j].size, percent: 1) ? 1.0 : 0.85
                    similar.append(SimilarFile(id: files[j].id, fileInfo: files[j], isSelected: false, similarity: sizeSim))
                }
            }
            guard !similar.isEmpty else { continue }
            groups.append(SimilarGroup(
                id: UUID(),
                referenceFile: files[i],
                similarFiles: similar,
                similarityReason: .nearbyDate
            ))
            processed.insert(files[i].id)
            for s in similar { processed.insert(s.fileInfo.id) }
        }
        return groups
    }

    private func deduplicateAndSort(_ groups: [SimilarGroup]) -> [SimilarGroup] {
        var seen = Set<UUID>()
        var result: [SimilarGroup] = []
        for g in groups {
            if seen.contains(g.id) { continue }
            let fileIds = [g.referenceFile.id] + g.similarFiles.map(\.fileInfo.id)
            if fileIds.contains(where: { seen.contains($0) }) { continue }
            result.append(g)
            for id in fileIds { seen.insert(id) }
        }
        return result.sorted { $0.totalWaste > $1.totalWaste }
    }
}
