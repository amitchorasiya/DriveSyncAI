// Copyright 2026 Amit Chorasiya. All rights reserved.
// Licensed under the Business Source License 1.1. See LICENSE file.

import Foundation

struct FileInfo: Identifiable, Hashable, Codable, Sendable {
    let id: UUID
    let url: URL
    let name: String
    let size: UInt64
    let modificationDate: Date
    let creationDate: Date
    let isDirectory: Bool
    let isSymlink: Bool
    let isPackage: Bool
    let relativePath: String
    let driveRoot: URL

    var formattedSize: String {
        ByteCountFormatter.string(fromByteCount: Int64(size), countStyle: .file)
    }

    init(url: URL, relativeTo driveRoot: URL) throws {
        let resourceKeys: Set<URLResourceKey> = [
            .fileSizeKey,
            .contentModificationDateKey,
            .creationDateKey,
            .isDirectoryKey,
            .isSymbolicLinkKey,
            .isPackageKey
        ]
        let resourceValues = try url.resourceValues(forKeys: resourceKeys)

        guard let modDate = resourceValues.contentModificationDate,
              let creationDate = resourceValues.creationDate,
              let isDir = resourceValues.isDirectory,
              let isSym = resourceValues.isSymbolicLink,
              let isPkg = resourceValues.isPackage else {
            throw CocoaError(.fileReadUnknown)
        }

        let sizeValue: UInt64
        if isPkg && isDir {
            sizeValue = Self.recursiveSize(of: url)
        } else {
            let fileSize = resourceValues.fileSize ?? 0
            sizeValue = fileSize >= 0 ? UInt64(fileSize) : 0
        }

        let standardizedDrive = driveRoot.standardized
        let standardizedURL = url.standardized
        let drivePath = standardizedDrive.path
        let filePath = standardizedURL.path

        let relPath: String
        if filePath == drivePath {
            relPath = ""
        } else if filePath.hasPrefix(drivePath + "/") {
            relPath = String(filePath.dropFirst((drivePath + "/").count))
        } else {
            relPath = url.lastPathComponent
        }

        self.id = UUID()
        self.url = url
        self.name = url.lastPathComponent
        self.size = sizeValue
        self.modificationDate = modDate
        self.creationDate = creationDate
        self.isDirectory = isDir
        self.isSymlink = isSym
        self.isPackage = isPkg
        self.relativePath = relPath
        self.driveRoot = driveRoot
    }

    private static func recursiveSize(of packageURL: URL) -> UInt64 {
        let fm = FileManager.default
        guard let enumerator = fm.enumerator(
            at: packageURL,
            includingPropertiesForKeys: [.fileSizeKey, .isDirectoryKey],
            options: [],
            errorHandler: { _, _ in true }
        ) else { return 0 }

        var total: UInt64 = 0
        for case let fileURL as URL in enumerator {
            guard let values = try? fileURL.resourceValues(forKeys: [.fileSizeKey, .isDirectoryKey]),
                  !(values.isDirectory ?? false) else { continue }
            total += UInt64(values.fileSize ?? 0)
        }
        return total
    }

    init(id: UUID, url: URL, name: String, size: UInt64, modificationDate: Date, creationDate: Date, isDirectory: Bool, isSymlink: Bool, isPackage: Bool, relativePath: String, driveRoot: URL) {
        self.id = id
        self.url = url
        self.name = name
        self.size = size
        self.modificationDate = modificationDate
        self.creationDate = creationDate
        self.isDirectory = isDirectory
        self.isSymlink = isSymlink
        self.isPackage = isPackage
        self.relativePath = relativePath
        self.driveRoot = driveRoot
    }
}
