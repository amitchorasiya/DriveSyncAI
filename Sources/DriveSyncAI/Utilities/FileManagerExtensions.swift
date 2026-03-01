// Copyright 2026 Amit Chorasiya. All rights reserved.
// Licensed under the Business Source License 1.1. See LICENSE file.

import Foundation
import Darwin

extension FileManager {

    /// Enumerate all files in a directory recursively, respecting filters.
    /// Skips package contents (.app, .framework, .bundle) by default.
    /// Skips the "Duplicates" folder at root level.
    func enumerateFiles(
        at directoryURL: URL,
        skipPackages: Bool = true,
        skipHidden: Bool = true,
        excludedNames: Set<String> = [".DS_Store", ".Trashes", ".Spotlight-V100", ".fseventsd"]
    ) throws -> [URL] {
        var results: [URL] = []
        let resourceKeys: Set<URLResourceKey> = [.isDirectoryKey, .isPackageKey, .isHiddenKey]
        let rootPath = directoryURL.standardized.path

        guard let enumerator = enumerator(
            at: directoryURL,
            includingPropertiesForKeys: Array(resourceKeys),
            options: skipHidden ? [.skipsHiddenFiles] : [],
            errorHandler: { _, error in true }
        ) else {
            throw NSError(domain: NSCocoaErrorDomain, code: NSFileReadNoSuchFileError, userInfo: [NSLocalizedDescriptionKey: "Cannot enumerate directory at \(directoryURL.path)"])
        }

        while let itemURL = enumerator.nextObject() as? URL {
            let resourceValues: URLResourceValues
            do {
                resourceValues = try itemURL.resourceValues(forKeys: resourceKeys)
            } catch {
                continue
            }

            let isDirectory = resourceValues.isDirectory ?? false
            let isPackage = resourceValues.isPackage ?? false
            let isHidden = resourceValues.isHidden ?? itemURL.lastPathComponent.hasPrefix(".")
            let name = itemURL.lastPathComponent

            if excludedNames.contains(name) {
                enumerator.skipDescendants()
                continue
            }

            if skipHidden && isHidden {
                enumerator.skipDescendants()
                continue
            }

            if isDirectory && name == "Duplicates" {
                let parentPath = itemURL.deletingLastPathComponent().standardized.path
                if parentPath == rootPath {
                    enumerator.skipDescendants()
                    continue
                }
            }

            if skipPackages && isPackage && isDirectory {
                results.append(itemURL)
                enumerator.skipDescendants()
                continue
            }

            if !isDirectory {
                results.append(itemURL)
            }
        }

        return results
    }

    /// Check if a URL points to a macOS package bundle
    func isPackage(at url: URL) -> Bool {
        var isDirectory: ObjCBool = false
        guard fileExists(atPath: url.path, isDirectory: &isDirectory) else {
            return false
        }
        guard isDirectory.boolValue else {
            return false
        }
        return url.pathExtension.lowercased() == "app" ||
            url.pathExtension.lowercased() == "framework" ||
            url.pathExtension.lowercased() == "bundle" ||
            url.pathExtension.lowercased() == "plugin" ||
            url.pathExtension.lowercased() == "component" ||
            url.pathExtension.lowercased() == "xctemplate"
    }

    /// Safely copy a file, preserving extended attributes and permissions
    func safeCopy(from source: URL, to destination: URL) throws {
        var isDirectory: ObjCBool = false
        guard fileExists(atPath: source.path, isDirectory: &isDirectory) else {
            throw NSError(domain: NSCocoaErrorDomain, code: NSFileReadNoSuchFileError, userInfo: [NSLocalizedDescriptionKey: "Source file does not exist: \(source.path)"])
        }

        try safeCloneOrCopy(from: source, to: destination)
    }

    /// Copy with APFS clonefile optimization and transparent fallback.
    func safeCloneOrCopy(from source: URL, to destination: URL) throws {
        let destParent = destination.deletingLastPathComponent()
        if !fileExists(atPath: destParent.path) {
            try createDirectory(at: destParent, withIntermediateDirectories: true)
        }

        if fileExists(atPath: destination.path) {
            try removeItem(at: destination)
        }

        let cloneResult = source.path.withCString { src in
            destination.path.withCString { dst in
                clonefile(src, dst, 0)
            }
        }

        if cloneResult == 0 {
            return
        }

        try copyItem(at: source, to: destination)
    }

    /// Safely move a file
    func safeMove(from source: URL, to destination: URL) throws {
        var isDirectory: ObjCBool = false
        guard fileExists(atPath: source.path, isDirectory: &isDirectory) else {
            throw NSError(domain: NSCocoaErrorDomain, code: NSFileReadNoSuchFileError, userInfo: [NSLocalizedDescriptionKey: "Source file does not exist: \(source.path)"])
        }

        let destParent = destination.deletingLastPathComponent()
        if !fileExists(atPath: destParent.path) {
            try createDirectory(at: destParent, withIntermediateDirectories: true)
        }

        if fileExists(atPath: destination.path) {
            try removeItem(at: destination)
        }

        try moveItem(at: source, to: destination)
    }

    /// Get volume info for a path
    func volumeInfo(for url: URL) throws -> (isCaseSensitive: Bool, format: String) {
        var stats = statfs()
        guard url.withUnsafeFileSystemRepresentation({ statfs($0, &stats) == 0 }) else {
            throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno), userInfo: [NSLocalizedDescriptionKey: "Cannot get volume info for \(url.path)"])
        }

        let fstypename = stats.f_fstypename
        let format = withUnsafePointer(to: fstypename) {
            $0.withMemoryRebound(to: CChar.self, capacity: MemoryLayout.size(ofValue: fstypename)) {
                String(cString: $0)
            }
        }

        let path = url.path
        var capturedErrno: Int32 = 0
        let result = path.withCString { ptr in
            let r = pathconf(ptr, _PC_CASE_SENSITIVE)
            capturedErrno = errno
            return r
        }
        let isCaseSensitive: Bool
        if result == 1 {
            isCaseSensitive = true
        } else if result == 0 {
            isCaseSensitive = false
        } else {
            isCaseSensitive = (capturedErrno == EINVAL)
        }

        return (isCaseSensitive, format)
    }

    /// Check if a file is writable (not locked)
    func isFileWritable(at url: URL) -> Bool {
        isWritableFile(atPath: url.path)
    }

    /// Check available space on volume
    func availableSpace(at url: URL) throws -> UInt64 {
        let resourceKeys: Set<URLResourceKey> = [.volumeAvailableCapacityForImportantUsageKey]
        let resourceValues = try url.resourceValues(forKeys: resourceKeys)
        guard let available = resourceValues.volumeAvailableCapacityForImportantUsage else {
            throw NSError(domain: NSCocoaErrorDomain, code: NSFileReadUnknownError, userInfo: [NSLocalizedDescriptionKey: "Cannot determine available space for \(url.path)"])
        }
        return UInt64(available)
    }
}
