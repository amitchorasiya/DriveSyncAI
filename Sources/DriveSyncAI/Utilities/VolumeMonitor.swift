// Copyright 2026 Amit Chorasiya. All rights reserved.
// Licensed under the Business Source License 1.1. See LICENSE file.

import Foundation
import Combine
import AppKit

@MainActor
final class VolumeMonitor: ObservableObject {
    @Published var mountedVolumes: [DriveInfo] = []
    @Published var volumeIcons: [String: NSImage] = [:]
    @Published var disconnectedDriveAlert: String?

    private var cancellables = Set<AnyCancellable>()
    private let workspace = NSWorkspace.shared
    private let fileManager = FileManager.default

    init() {
        let center = workspace.notificationCenter

        center.publisher(for: NSWorkspace.didMountNotification)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                Task { @MainActor in
                    self?.refreshVolumes()
                }
            }
            .store(in: &cancellables)

        center.publisher(for: NSWorkspace.didUnmountNotification)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                Task { @MainActor in
                    self?.refreshVolumes()
                }
            }
            .store(in: &cancellables)

        refreshVolumes()
    }

    func refreshVolumes() {
        let fm = fileManager
        Task.detached(priority: .userInitiated) {
            let resourceKeys: Set<URLResourceKey> = [
                .volumeNameKey,
                .volumeTotalCapacityKey,
                .volumeAvailableCapacityForImportantUsageKey,
                .volumeIsRemovableKey,
                .volumeIsLocalKey,
                .volumeIsEjectableKey
            ]

            guard let volumeURLs = fm.mountedVolumeURLs(
                includingResourceValuesForKeys: Array(resourceKeys),
                options: [.skipHiddenVolumes]
            ) else {
                await MainActor.run {
                    self.mountedVolumes = []
                    self.volumeIcons = [:]
                }
                return
            }

            // Phase 1: Probe drive info concurrently with timeout.
            // Each resolved drive is pushed to the UI immediately (progressive).
            var drives: [DriveInfo] = []

            await withTaskGroup(of: DriveInfo?.self) { group in
                for volumeURL in volumeURLs {
                    group.addTask {
                        await self.probeDriveInfoWithTimeout(volumeURL, resourceKeys: resourceKeys)
                    }
                }

                for await info in group {
                    guard let info = info else { continue }
                    drives.append(info)
                    let sorted = drives.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
                    await MainActor.run {
                        self.mountedVolumes = sorted
                    }
                }
            }

            // Phase 2: Load icons in parallel (non-blocking — drives are already visible).
            let drivesToIcon = drives
            var icons: [String: NSImage] = [:]

            await withTaskGroup(of: (String, NSImage)?.self) { group in
                for drive in drivesToIcon {
                    let path = drive.url.path
                    group.addTask {
                        let icon = NSWorkspace.shared.icon(forFile: path)
                        return (path, icon)
                    }
                }

                for await result in group {
                    guard let (path, icon) = result else { continue }
                    icons[path] = icon
                    let currentIcons = icons
                    await MainActor.run {
                        self.volumeIcons = currentIcons
                    }
                }
            }
        }
    }

    /// Probes a single volume for drive info with a 3-second timeout.
    /// Returns nil if the volume is unresponsive within the deadline.
    private nonisolated func probeDriveInfoWithTimeout(
        _ volumeURL: URL,
        resourceKeys: Set<URLResourceKey>
    ) async -> DriveInfo? {
        let timeoutNanos: UInt64 = 3_000_000_000
        return await withTaskGroup(of: DriveInfo?.self) { group in
            group.addTask {
                self.driveInfo(for: volumeURL, resourceKeys: resourceKeys)
            }
            group.addTask {
                try? await Task.sleep(nanoseconds: timeoutNanos)
                return nil
            }
            let result = await group.next() ?? nil
            group.cancelAll()
            return result
        }
    }

    private nonisolated func driveInfo(for volumeURL: URL, resourceKeys: Set<URLResourceKey>) -> DriveInfo? {
        let resourceValues: URLResourceValues
        do {
            resourceValues = try volumeURL.resourceValues(forKeys: resourceKeys)
        } catch {
            return nil
        }

        let name = resourceValues.volumeName ?? volumeURL.lastPathComponent
        let totalCapacity = UInt64(resourceValues.volumeTotalCapacity ?? 0)
        let availableCapacity = UInt64(resourceValues.volumeAvailableCapacityForImportantUsage ?? 0)
        let isRemovable = resourceValues.volumeIsRemovable ?? false
        let isLocal = resourceValues.volumeIsLocal ?? true

        let volumeFormat = fileSystemType(for: volumeURL) ?? "Unknown"
        let isCaseSensitive = (try? FileManager.default.volumeInfo(for: volumeURL))?.isCaseSensitive ?? false
        let connectionType = detectConnectionType(for: volumeURL, isRemovable: isRemovable, isLocal: isLocal)

        return DriveInfo(
            id: UUID(),
            url: volumeURL,
            name: name,
            totalCapacity: totalCapacity,
            availableCapacity: availableCapacity,
            connectionType: connectionType,
            isRemovable: isRemovable,
            volumeFormat: volumeFormat,
            isCaseSensitive: isCaseSensitive
        )
    }

    private nonisolated func fileSystemType(for volumeURL: URL) -> String? {
        var stats = statfs()
        guard volumeURL.withUnsafeFileSystemRepresentation({ statfs($0, &stats) == 0 }) else {
            return nil
        }
        let fstypename = stats.f_fstypename
        return withUnsafePointer(to: fstypename) {
            $0.withMemoryRebound(to: CChar.self, capacity: MemoryLayout.size(ofValue: fstypename)) {
                String(cString: $0)
            }
        }
    }

    nonisolated func detectConnectionType(for volumeURL: URL, isRemovable: Bool? = nil, isLocal: Bool? = nil) -> DriveConnectionType {
        let removable: Bool
        let local: Bool

        if let r = isRemovable, let l = isLocal {
            removable = r
            local = l
        } else {
            let resourceKeys: Set<URLResourceKey> = [.volumeIsRemovableKey, .volumeIsLocalKey]
            do {
                let rv = try volumeURL.resourceValues(forKeys: resourceKeys)
                removable = isRemovable ?? rv.volumeIsRemovable ?? false
                local = isLocal ?? rv.volumeIsLocal ?? true
            } catch {
                return .unknown
            }
        }

        if !local {
            return .network
        }

        let path = volumeURL.path
        if path == "/" || path.isEmpty {
            return .internal_
        }

        if path.hasPrefix("/Volumes/") {
            if removable {
                return .usb3
            }
            return .internal_
        }

        return .unknown
    }
}
