// Copyright 2026 Amit Chorasiya. All rights reserved.
// Licensed under the Business Source License 1.1. See LICENSE file.

import Foundation

enum ConflictResolutionStrategy: String, Codable, CaseIterable {
    case keepBoth
    case keepNewer
    case keepLarger
    case keepSource
    case keepTarget
    case skip
}

struct ConflictResolver {
    /// Resolve a conflict action into concrete sync actions.
    static func resolve(
        conflict: SyncAction,
        strategy: ConflictResolutionStrategy,
        sourceRoot: URL,
        targetRoot: URL
    ) -> [SyncAction] {
        guard conflict.actionType == .conflict,
              let sourceFile = conflict.sourceFile,
              let targetFile = conflict.targetFile else {
            return []
        }

        switch strategy {
        case .keepBoth:
            let conflictName = conflictFileName(for: conflict.displayName)
            let targetConflictPath = (conflict.relativePath as NSString).deletingLastPathComponent
            let newRelativePath = targetConflictPath.isEmpty ? conflictName : "\(targetConflictPath)/\(conflictName)"
            let createAction = SyncAction(
                id: UUID(),
                actionType: .create,
                sourceFile: sourceFile,
                targetFile: nil,
                relativePath: newRelativePath,
                isSelected: true
            )
            return [createAction]

        case .keepNewer:
            if sourceFile.modificationDate >= targetFile.modificationDate {
                return [SyncAction(
                    id: UUID(),
                    actionType: .update,
                    sourceFile: sourceFile,
                    targetFile: targetFile,
                    relativePath: conflict.relativePath,
                    isSelected: true
                )]
            } else {
                return [SyncAction(
                    id: UUID(),
                    actionType: .update,
                    sourceFile: targetFile,
                    targetFile: sourceFile,
                    relativePath: conflict.relativePath,
                    isSelected: true
                )]
            }

        case .keepLarger:
            if sourceFile.size >= targetFile.size {
                return [SyncAction(
                    id: UUID(),
                    actionType: .update,
                    sourceFile: sourceFile,
                    targetFile: targetFile,
                    relativePath: conflict.relativePath,
                    isSelected: true
                )]
            } else {
                return [SyncAction(
                    id: UUID(),
                    actionType: .update,
                    sourceFile: targetFile,
                    targetFile: sourceFile,
                    relativePath: conflict.relativePath,
                    isSelected: true
                )]
            }

        case .keepSource:
            return [SyncAction(
                id: UUID(),
                actionType: .update,
                sourceFile: sourceFile,
                targetFile: targetFile,
                relativePath: conflict.relativePath,
                isSelected: true
            )]

        case .keepTarget:
            return [SyncAction(
                id: UUID(),
                actionType: .update,
                sourceFile: targetFile,
                targetFile: sourceFile,
                relativePath: conflict.relativePath,
                isSelected: true
            )]

        case .skip:
            return []
        }
    }

    /// Generate a conflict-safe filename
    static func conflictFileName(for name: String) -> String {
        let timestamp = ISO8601DateFormatter().string(from: Date())
            .replacingOccurrences(of: ":", with: "-")
        let nsName = name as NSString
        let pathExt = nsName.pathExtension
        let baseName = pathExt.isEmpty ? name : nsName.deletingPathExtension
        if pathExt.isEmpty {
            return "\(baseName)_conflict_\(timestamp)"
        }
        return "\(baseName)_conflict_\(timestamp).\(pathExt)"
    }
}
