// Copyright 2026 Amit Chorasiya. All rights reserved.
// Licensed under the Business Source License 1.1. See LICENSE file.

import Foundation

enum FileCategory: String, CaseIterable, Codable, Identifiable {
    case photos
    case videos
    case documents
    case music
    case code
    case archives
    case installers
    case fonts
    case databases
    case ebooks
    case design
    case other

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .photos: return "Photos"
        case .videos: return "Videos"
        case .documents: return "Documents"
        case .music: return "Music"
        case .code: return "Code"
        case .archives: return "Archives"
        case .installers: return "Installers"
        case .fonts: return "Fonts"
        case .databases: return "Databases"
        case .ebooks: return "E-Books"
        case .design: return "Design"
        case .other: return "Other"
        }
    }

    var icon: String {
        switch self {
        case .photos: return "photo"
        case .videos: return "film"
        case .documents: return "doc.text"
        case .music: return "music.note"
        case .code: return "chevron.left.forwardslash.chevron.right"
        case .archives: return "archivebox"
        case .installers: return "arrow.down.app"
        case .fonts: return "textformat"
        case .databases: return "cylinder"
        case .ebooks: return "book"
        case .design: return "paintbrush"
        case .other: return "questionmark.folder"
        }
    }

    var suggestedFolder: String {
        switch self {
        case .photos: return "Photos"
        case .videos: return "Videos"
        case .documents: return "Documents"
        case .music: return "Music"
        case .code: return "Code"
        case .archives: return "Archives"
        case .installers: return "Installers"
        case .fonts: return "Fonts"
        case .databases: return "Databases"
        case .ebooks: return "Books"
        case .design: return "Design"
        case .other: return "Other"
        }
    }

    static let extensionMap: [String: FileCategory] = {
        var map = [String: FileCategory]()
        let photo = ["jpg", "jpeg", "png", "gif", "bmp", "tiff", "tif", "webp", "heic", "heif",
                     "raw", "cr2", "cr3", "nef", "arw", "dng", "orf", "rw2", "pef", "sr2", "svg", "ico"]
        let video = ["mp4", "mov", "avi", "mkv", "wmv", "flv", "webm", "m4v", "mpg", "mpeg",
                     "3gp", "vob", "ts", "mts", "m2ts", "ogv"]
        let doc = ["pdf", "doc", "docx", "xls", "xlsx", "ppt", "pptx", "txt", "rtf", "odt",
                   "ods", "odp", "csv", "tsv", "pages", "numbers", "keynote", "md", "tex", "log"]
        let audio = ["mp3", "wav", "aac", "flac", "ogg", "wma", "m4a", "aiff", "aif", "alac",
                     "opus", "mid", "midi"]
        let codeExts = ["swift", "py", "js", "ts", "jsx", "tsx", "java", "kt", "c", "cpp", "h",
                        "hpp", "cs", "go", "rs", "rb", "php", "html", "css", "scss", "less",
                        "json", "xml", "yaml", "yml", "toml", "ini", "sh", "bash", "zsh",
                        "sql", "r", "m", "mm", "dart", "lua", "pl", "scala", "groovy",
                        "vue", "svelte", "astro"]
        let archive = ["zip", "tar", "gz", "bz2", "7z", "rar", "xz", "lz", "zst", "tgz", "tbz2"]
        let installer = ["dmg", "pkg", "app", "iso", "msi", "exe", "deb", "rpm", "snap", "flatpak"]
        let font = ["ttf", "otf", "woff", "woff2", "eot"]
        let db = ["db", "sqlite", "sqlite3", "mdb", "accdb", "realm"]
        let ebook = ["epub", "mobi", "azw", "azw3", "fb2", "djvu", "cbr", "cbz"]
        let designExt = ["psd", "ai", "sketch", "fig", "xd", "indd", "afdesign", "afphoto",
                         "blend", "obj", "fbx", "stl", "3ds", "dae"]

        for ext in photo { map[ext] = .photos }
        for ext in video { map[ext] = .videos }
        for ext in doc { map[ext] = .documents }
        for ext in audio { map[ext] = .music }
        for ext in codeExts { map[ext] = .code }
        for ext in archive { map[ext] = .archives }
        for ext in installer { map[ext] = .installers }
        for ext in font { map[ext] = .fonts }
        for ext in db { map[ext] = .databases }
        for ext in ebook { map[ext] = .ebooks }
        for ext in designExt { map[ext] = .design }
        return map
    }()
}

struct CategoryStats: Codable {
    var fileCount: Int = 0
    var totalSize: Int64 = 0
    var extensions: Set<String> = []
    var oldestDate: Date?
    var newestDate: Date?

    mutating func addFile(size: Int64, ext: String, modified: Date?) {
        fileCount += 1
        totalSize += size
        extensions.insert(ext)
        if let d = modified {
            if oldestDate == nil || d < oldestDate! { oldestDate = d }
            if newestDate == nil || d > newestDate! { newestDate = d }
        }
    }
}

enum ClutterReason: String, Codable {
    case systemJunk
    case tempFile
    case emptyFolder
    case oldDownload
    case duplicateInstaller
    case orphanedFile
    case cacheFile

    var displayName: String {
        switch self {
        case .systemJunk: return "System Junk"
        case .tempFile: return "Temporary File"
        case .emptyFolder: return "Empty Folder"
        case .oldDownload: return "Old Download"
        case .duplicateInstaller: return "Duplicate Installer"
        case .orphanedFile: return "Orphaned File"
        case .cacheFile: return "Cache File"
        }
    }
}

struct ClutterItem: Identifiable {
    let id = UUID()
    var relativePath: String
    var reason: ClutterReason
    var size: Int64
}

enum InstallerPlatform: String, Codable, CaseIterable {
    case windows
    case mac
    case other

    var displayName: String {
        switch self {
        case .windows: return "Windows"
        case .mac: return "Mac"
        case .other: return "Other"
        }
    }

    static let extensionMap: [String: InstallerPlatform] = [
        "exe": .windows, "msi": .windows,
        "dmg": .mac, "pkg": .mac, "app": .mac,
        "iso": .other, "deb": .other, "rpm": .other,
        "snap": .other, "flatpak": .other
    ]
}

struct FileMetadataHint: Identifiable, Sendable {
    let id = UUID()
    var relativePath: String
    var fileName: String
    var size: Int64
    var modifiedDate: Date?
    var category: FileCategory?
    var confidence: Double = 0
    var exifDate: Date?
    var exifLocation: String?
    var eventName: String?
    var installerPlatform: InstallerPlatform?
    var pdfTitle: String?
    var pdfAuthor: String?
    var spotlightContentType: String?
    var firstLineHint: String?
    var parentFolder: String
}

struct MixedFolderInfo: Identifiable {
    let id = UUID()
    var folderName: String
    var relativePath: String
    var totalFiles: Int
    var categoryBreakdown: [FileCategory: Int]
    var totalSize: Int64
}

struct DriveAnalysis {
    var rootPath: URL
    var totalFiles: Int = 0
    var totalSize: Int64 = 0
    var totalFolders: Int = 0
    var categories: [FileCategory: CategoryStats] = [:]
    var folderTree: [String] = []
    var clutterItems: [ClutterItem] = []
    var categorizedFiles: [FileMetadataHint] = []
    var ambiguousFiles: [FileMetadataHint] = []
    var mixedFolders: [MixedFolderInfo] = []
    var scanDuration: TimeInterval = 0
}
