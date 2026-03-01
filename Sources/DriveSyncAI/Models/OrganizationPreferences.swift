// Copyright 2026 Amit Chorasiya. All rights reserved.
// Licensed under the Business Source License 1.1. See LICENSE file.

import Foundation

enum FolderStructurePreference: String, Codable, CaseIterable {
    case byType
    case byDate
    case byProject
    case customRoot

    var displayName: String {
        switch self {
        case .byType: return "By Type"
        case .byDate: return "By Date"
        case .byProject: return "By Project"
        case .customRoot: return "Custom Root"
        }
    }
}

enum NamingConventionPreference: String, Codable, CaseIterable {
    case original
    case lowercase
    case datePrefixed
    case customPrefix

    var displayName: String {
        switch self {
        case .original: return "Original"
        case .lowercase: return "lowercase"
        case .datePrefixed: return "Date Prefix"
        case .customPrefix: return "Custom Prefix"
        }
    }
}

enum DuplicatesHandlingPreference: String, Codable, CaseIterable {
    case skipConflicts
    case renameConflicts
    case replaceExisting

    var displayName: String {
        switch self {
        case .skipConflicts: return "Skip Conflicts"
        case .renameConflicts: return "Rename Conflicts"
        case .replaceExisting: return "Replace Existing"
        }
    }
}

enum OrganizationScopePreference: String, Codable, CaseIterable {
    case fullRecursive
    case topLevelOnly
    case maxDepth3

    var displayName: String {
        switch self {
        case .fullRecursive: return "Full Recursive"
        case .topLevelOnly: return "Top-level Only"
        case .maxDepth3: return "Max Depth 3"
        }
    }

    var maxDepth: Int? {
        switch self {
        case .fullRecursive: return nil
        case .topLevelOnly: return 1
        case .maxDepth3: return 3
        }
    }
}

struct CleanupPreferences: Codable {
    var includeTempFiles: Bool = true
    var includeSystemJunk: Bool = true
    var includeEmptyFolders: Bool = true
}

struct OrganizationPreferences: Codable {
    var folderStructure: FolderStructurePreference = .byType
    var namingConvention: NamingConventionPreference = .original
    var duplicatesHandling: DuplicatesHandlingPreference = .renameConflicts
    var priorityCategories: Set<FileCategory> = []
    var cleanup: CleanupPreferences = .init()
    var scope: OrganizationScopePreference = .fullRecursive
    var customRootFolderName: String = "Organized"
    var customNamePrefix: String = ""

    static let `default` = OrganizationPreferences()
}

struct RuleCandidate: Codable, Identifiable, Hashable {
    var id: UUID = UUID()
    var name: String
    var pattern: String
    var destination: String
    var selectedForSave: Bool = true

    enum CodingKeys: String, CodingKey {
        case id, name, pattern, destination, selectedForSave
    }

    init(id: UUID = UUID(), name: String, pattern: String, destination: String, selectedForSave: Bool = true) {
        self.id = id
        self.name = name
        self.pattern = pattern
        self.destination = destination
        self.selectedForSave = selectedForSave
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = (try? container.decode(UUID.self, forKey: .id)) ?? UUID()
        name = try container.decode(String.self, forKey: .name)
        pattern = try container.decode(String.self, forKey: .pattern)
        destination = try container.decode(String.self, forKey: .destination)
        selectedForSave = (try? container.decode(Bool.self, forKey: .selectedForSave)) ?? true
    }
}

struct PlanModification: Codable {
    var action: String
    var fileName: String?
    var sourcePath: String?
    var destinationPath: String?
    var reason: String?

    static let validActions = [
        "addMove", "removeMove", "changeDestination",
        "addCleanup", "removeCleanup", "addRename"
    ]
}

struct PreferenceChange: Codable {
    var field: String
    var value: String
}

struct OrganizationRefinementResponse: Codable {
    var assistantMessage: String?
    var followUpQuestion: String?
    var ruleCandidates: [RuleCandidate]?
    var planModifications: [PlanModification]?
    var preferenceChanges: [PreferenceChange]?
    var shouldReAnalyze: Bool?

    enum CodingKeys: String, CodingKey {
        case assistantMessage, followUpQuestion, ruleCandidates
        case planModifications, preferenceChanges, shouldReAnalyze
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        assistantMessage = try? container.decode(String.self, forKey: .assistantMessage)
        followUpQuestion = try? container.decode(String.self, forKey: .followUpQuestion)
        ruleCandidates = try? container.decode([RuleCandidate].self, forKey: .ruleCandidates)
        planModifications = try? container.decode([PlanModification].self, forKey: .planModifications)
        preferenceChanges = try? container.decode([PreferenceChange].self, forKey: .preferenceChanges)
        if let boolVal = try? container.decode(Bool.self, forKey: .shouldReAnalyze) {
            shouldReAnalyze = boolVal
        } else if let strVal = try? container.decode(String.self, forKey: .shouldReAnalyze) {
            shouldReAnalyze = strVal.lowercased() == "true"
        }
    }
}
