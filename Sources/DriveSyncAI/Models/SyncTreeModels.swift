// Copyright 2026 Amit Chorasiya. All rights reserved.
// Licensed under the Business Source License 1.1. See LICENSE file.

import Foundation

// MARK: - File Type Categories

enum FileTypeCategory: String, CaseIterable, Hashable, Identifiable {
    case photos, videos, documents, music, archives, code, other

    var id: String { rawValue }

    var label: String {
        switch self {
        case .photos: return "Photos"
        case .videos: return "Videos"
        case .documents: return "Documents"
        case .music: return "Music"
        case .archives: return "Archives"
        case .code: return "Code"
        case .other: return "Other"
        }
    }

    var icon: String {
        switch self {
        case .photos: return "photo"
        case .videos: return "film"
        case .documents: return "doc.text"
        case .music: return "music.note"
        case .archives: return "archivebox"
        case .code: return "chevron.left.forwardslash.chevron.right"
        case .other: return "doc"
        }
    }

    private static let extensionMap: [String: FileTypeCategory] = {
        let mapping: [(FileTypeCategory, [String])] = [
            (.photos, [
                "jpg", "jpeg", "png", "heic", "heif", "gif", "webp", "raw", "cr2", "nef",
                "tiff", "tif", "bmp", "svg", "ico", "arw", "dng", "orf", "rw2", "psd",
                "ai", "eps", "avif", "jxl",
            ]),
            (.videos, [
                "mp4", "mov", "avi", "mkv", "wmv", "m4v", "flv", "webm", "3gp", "mts",
                "m2ts", "ts", "vob", "mpg", "mpeg", "ogv", "rm", "rmvb", "asf",
            ]),
            (.documents, [
                "pdf", "doc", "docx", "xls", "xlsx", "ppt", "pptx", "txt", "rtf", "pages",
                "numbers", "keynote", "csv", "odt", "ods", "odp", "epub", "md", "markdown",
                "tex", "log", "ics", "vcf", "wpd", "wps", "xps",
            ]),
            (.music, [
                "mp3", "aac", "flac", "wav", "m4a", "aiff", "ogg", "wma", "opus", "alac",
                "ape", "mid", "midi", "mka", "wv", "tak", "dsf", "dff",
            ]),
            (.archives, [
                "zip", "tar", "gz", "rar", "7z", "dmg", "iso", "bz2", "xz", "tgz", "lz",
                "lzma", "zst", "cab", "cpio", "rpm", "deb", "pkg", "sit", "sitx", "lz4", "lzo",
            ]),
            (.code, [
                "swift", "py", "js", "ts", "html", "css", "json", "xml", "yaml", "yml",
                "sh", "rb", "go", "rs", "java", "kt", "c", "cpp", "h", "m", "mm", "hpp",
                "cs", "fs", "jsx", "tsx", "vue", "svelte", "php", "pl", "lua", "r",
                "scala", "zig", "nim", "dart", "sql", "toml", "ini", "cfg", "env",
                "dockerfile", "makefile", "cmake", "gradle", "ex", "exs", "erl", "hs",
            ]),
        ]
        var map: [String: FileTypeCategory] = [:]
        for (cat, exts) in mapping {
            for ext in exts { map[ext] = cat }
        }
        return map
    }()

    static func category(for ext: String) -> FileTypeCategory {
        extensionMap[ext.lowercased()] ?? .other
    }
}

// MARK: - Tree Node

final class SyncTreeNode: Identifiable {
    let id: String
    let name: String
    let path: String
    let isFolder: Bool
    let depth: Int
    var actionId: UUID?
    var children: [SyncTreeNode]

    private(set) var cachedFileCount: Int = 0
    private(set) var cachedTotalSize: UInt64 = 0
    private(set) var descendantActionIds: [UUID] = []

    var fileCategory: FileTypeCategory {
        let ext = (name as NSString).pathExtension
        return FileTypeCategory.category(for: ext)
    }

    init(name: String, path: String, isFolder: Bool, depth: Int, actionId: UUID? = nil) {
        self.id = path.isEmpty ? UUID().uuidString : path
        self.name = name
        self.path = path
        self.isFolder = isFolder
        self.depth = depth
        self.actionId = actionId
        self.children = []
    }

    func computeAggregates(lookup: [UUID: SyncAction]) {
        if isFolder {
            for child in children {
                child.computeAggregates(lookup: lookup)
            }
            cachedFileCount = children.reduce(0) { $0 + ($1.isFolder ? $1.cachedFileCount : 1) }
            cachedTotalSize = children.reduce(0) { total, child in
                if child.isFolder {
                    return total + child.cachedTotalSize
                }
                return total + (lookup[child.actionId ?? UUID()]?.fileSize ?? 0)
            }
            descendantActionIds = children.flatMap { child in
                child.isFolder ? child.descendantActionIds : [child.actionId].compactMap { $0 }
            }
        } else {
            cachedFileCount = 1
            cachedTotalSize = lookup[actionId ?? UUID()]?.fileSize ?? 0
            descendantActionIds = [actionId].compactMap { $0 }
        }
    }
}

// MARK: - Folder Selection State

enum FolderSelectionState {
    case none, partial, all
}

// MARK: - Tree Builder

enum SyncTreeBuilder {

    static func buildTreeOffMainThread(from actions: [SyncAction]) async -> [SyncTreeNode] {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let roots = buildTree(from: actions)
                continuation.resume(returning: roots)
            }
        }
    }

    static func buildTree(from actions: [SyncAction]) -> [SyncTreeNode] {
        let virtualRoot = SyncTreeNode(name: "", path: "", isFolder: true, depth: -1)
        var folderIndex: [String: SyncTreeNode] = [:]
        folderIndex.reserveCapacity(actions.count / 4)

        for action in actions {
            let components = action.relativePath.split(separator: "/").map(String.init)
            guard !components.isEmpty else { continue }

            var current = virtualRoot
            var currentPath = ""

            for (i, component) in components.enumerated() {
                currentPath = currentPath.isEmpty ? component : currentPath + "/" + component
                let isLast = i == components.count - 1

                if isLast {
                    let leaf = SyncTreeNode(
                        name: component, path: currentPath,
                        isFolder: false, depth: i, actionId: action.id
                    )
                    current.children.append(leaf)
                } else {
                    if let existing = folderIndex[currentPath] {
                        current = existing
                    } else {
                        let folder = SyncTreeNode(
                            name: component, path: currentPath,
                            isFolder: true, depth: i
                        )
                        current.children.append(folder)
                        folderIndex[currentPath] = folder
                        current = folder
                    }
                }
            }
        }

        sortChildren(virtualRoot)

        let lookup = Dictionary(uniqueKeysWithValues: actions.map { ($0.id, $0) })
        for child in virtualRoot.children {
            child.computeAggregates(lookup: lookup)
        }

        return virtualRoot.children
    }

    static func flattenVisible(roots: [SyncTreeNode], expandedPaths: Set<String>) -> [SyncTreeNode] {
        var result: [SyncTreeNode] = []
        func visit(_ nodes: [SyncTreeNode]) {
            for node in nodes {
                result.append(node)
                if node.isFolder && expandedPaths.contains(node.path) {
                    visit(node.children)
                }
            }
        }
        visit(roots)
        return result
    }

    static func folderSelectionState(for node: SyncTreeNode, lookup: [UUID: SyncAction]) -> FolderSelectionState {
        let ids = node.descendantActionIds
        guard !ids.isEmpty else { return .none }
        let selectedCount = ids.filter { lookup[$0]?.isSelected == true }.count
        if selectedCount == 0 { return .none }
        if selectedCount == ids.count { return .all }
        return .partial
    }

    static func isNodeDimmed(_ node: SyncTreeNode, activeFileTypes: Set<FileTypeCategory>) -> Bool {
        if node.isFolder {
            return node.children.allSatisfy { isNodeDimmed($0, activeFileTypes: activeFileTypes) }
        }
        return !activeFileTypes.contains(node.fileCategory)
    }

    private static func sortChildren(_ node: SyncTreeNode) {
        node.children.sort { a, b in
            if a.isFolder != b.isFolder { return a.isFolder }
            return a.name.localizedCaseInsensitiveCompare(b.name) == .orderedAscending
        }
        for child in node.children where child.isFolder {
            sortChildren(child)
        }
    }
}
