// Copyright 2026 Amit Chorasiya. All rights reserved.
// Licensed under the Business Source License 1.1. See LICENSE file.

import Foundation

enum PlanSource: String, Codable {
    case deterministic
    case metadata
    case ai
    case customRule
    case merged

    var displayName: String {
        switch self {
        case .deterministic: return "Rule"
        case .metadata: return "Metadata"
        case .ai: return "AI"
        case .customRule: return "Custom Rule"
        case .merged: return "Merged"
        }
    }

    var badgeColor: String {
        switch self {
        case .deterministic: return "green"
        case .metadata: return "blue"
        case .ai: return "purple"
        case .customRule: return "orange"
        case .merged: return "gray"
        }
    }
}

enum ClutterActionType: String, Codable, CaseIterable {
    case delete
    case archive
    case ignore

    var displayName: String {
        switch self {
        case .delete: return "Delete"
        case .archive: return "Move to Archive"
        case .ignore: return "Ignore"
        }
    }

    var icon: String {
        switch self {
        case .delete: return "trash"
        case .archive: return "archivebox"
        case .ignore: return "eye.slash"
        }
    }
}

struct FolderSuggestion: Codable, Identifiable {
    var id: UUID = UUID()
    var path: String
    var reason: String
    var fileCount: Int
    var totalSize: Int64
    var source: PlanSource
    var accepted: Bool = true
}

struct MoveAction: Codable, Identifiable {
    var id: UUID = UUID()
    var sourcePath: String
    var destinationPath: String
    var fileName: String
    var fileSize: Int64
    var reason: String
    var source: PlanSource
    var confidence: Double
    var accepted: Bool = true
}

struct RenameSuggestion: Codable, Identifiable {
    var id: UUID = UUID()
    var filePath: String
    var originalName: String
    var suggestedName: String
    var reason: String
    var accepted: Bool = false
}

struct ClutterAction: Codable, Identifiable {
    var id: UUID = UUID()
    var path: String
    var action: ClutterActionType
    var reason: String
    var size: Int64
    var accepted: Bool = true
}

struct ReorganizePlan {
    var folderSuggestions: [FolderSuggestion] = []
    var moveActions: [MoveAction] = []
    var renameSuggestions: [RenameSuggestion] = []
    var clutterActions: [ClutterAction] = []
    var generatedAt: Date = Date()
    var aiModelUsed: String?

    var totalAcceptedMoves: Int {
        moveActions.filter(\.accepted).count
    }

    var totalAcceptedRenames: Int {
        renameSuggestions.filter(\.accepted).count
    }

    var totalAcceptedClutter: Int {
        clutterActions.filter(\.accepted).count
    }

    var totalAcceptedActions: Int {
        totalAcceptedMoves + totalAcceptedRenames + totalAcceptedClutter
    }

    var estimatedSpaceSaved: Int64 {
        clutterActions.filter { $0.accepted && $0.action == .delete }.reduce(0) { $0 + $1.size }
    }

    var isEmpty: Bool {
        folderSuggestions.isEmpty && moveActions.isEmpty && renameSuggestions.isEmpty && clutterActions.isEmpty
    }
}

struct AIOrganizeResponse: Codable {
    var folderStructure: [AIFolderSuggestion]?
    var moveRules: [AIMoveRule]?
    var fileClassifications: [AIFileClassification]?
    var renameSuggestions: [AIRenameSuggestion]?
    var clutterActions: [AIClutterAction]?
}

struct AIFolderSuggestion: Codable {
    var path: String
    var reason: String
}

struct AIMoveRule: Codable {
    var pattern: String
    var from: String?
    var to: String
    var reason: String
}

struct AIFileClassification: Codable {
    var file: String
    var category: String
    var suggestedPath: String?
    var confidence: Double?
}

struct AIRenameSuggestion: Codable {
    var from: String
    var to: String
    var reason: String
}

struct AIClutterAction: Codable {
    var path: String
    var action: String
    var reason: String
}
