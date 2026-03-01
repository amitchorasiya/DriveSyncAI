// Copyright 2026 Amit Chorasiya. All rights reserved.
// Licensed under the Business Source License 1.1. See LICENSE file.

import SwiftUI
import AppKit
import UniformTypeIdentifiers

/// Volume picker dropdown showing mounted drives from VolumeMonitor.
/// Supports drag-and-drop of folders to set custom path.
struct DrivePickerView: View {
    @ObservedObject var volumeMonitor: VolumeMonitor
    @Binding var selectedURL: URL?
    let allowCustomPath: Bool

    @State private var isDropTarget = false

    init(
        volumeMonitor: VolumeMonitor,
        selectedURL: Binding<URL?>,
        allowCustomPath: Bool = true
    ) {
        self.volumeMonitor = volumeMonitor
        self._selectedURL = selectedURL
        self.allowCustomPath = allowCustomPath
    }

    private var selectedDrive: DriveInfo? {
        guard let url = selectedURL else { return nil }
        return volumeMonitor.mountedVolumes.first { $0.url == url }
    }

    private var displayName: String {
        if let drive = selectedDrive {
            return drive.name
        }
        if let url = selectedURL {
            return url.lastPathComponent
        }
        return "Select a drive..."
    }

    var body: some View {
        Menu {
            ForEach(volumeMonitor.mountedVolumes, id: \.id) { drive in
                driveButton(drive)
            }

            if allowCustomPath {
                Divider()
                Button("Choose custom folder...") {
                    selectCustomFolder()
                }
            }
        } label: {
            pickerLabel
        }
        .onDrop(of: [.folder, .fileURL], isTargeted: $isDropTarget) { providers in
            handleDrop(providers: providers)
        }
    }

    @ViewBuilder
    private func cachedDriveIcon(for drive: DriveInfo, size: CGFloat) -> some View {
        if let icon = volumeMonitor.volumeIcons[drive.url.path] {
            Image(nsImage: icon)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: size, height: size)
        } else {
            Image(systemName: "externaldrive.fill")
                .font(.system(size: size * 0.7))
                .foregroundStyle(Color.dsSecondaryText)
                .frame(width: size, height: size)
        }
    }

    private func driveButton(_ drive: DriveInfo) -> some View {
        Button {
            selectedURL = drive.url
        } label: {
            HStack {
                cachedDriveIcon(for: drive, size: 20)
                VStack(alignment: .leading, spacing: 2) {
                    Text(drive.name)
                        .font(.system(size: 13, weight: .medium))
                    Text("\(drive.formattedAvailable) free")
                        .font(.system(size: 11))
                        .foregroundStyle(Color.dsSecondaryText)
                }
                Spacer()
                Circle()
                    .fill(Color.dsSuccess)
                    .frame(width: 6, height: 6)
            }
        }
    }

    private var pickerLabel: some View {
        HStack(spacing: AppTheme.Spacing.medium) {
            if let drive = selectedDrive {
                cachedDriveIcon(for: drive, size: 24)
            } else {
                Image(systemName: "externaldrive.fill")
                    .font(.system(size: 18))
                    .foregroundStyle(Color.dsSecondaryText)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(displayName)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(selectedURL != nil ? Color.dsPrimaryText : Color.dsSecondaryText)
                if let drive = selectedDrive {
                    Text(drive.formattedAvailable + " available")
                        .font(.system(size: 11))
                        .foregroundStyle(Color.dsTertiaryText)
                }
            }

            if selectedDrive != nil {
                Circle()
                    .fill(Color.dsSuccess)
                    .frame(width: 6, height: 6)
            }

            Image(systemName: "chevron.down")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Color.dsTertiaryText)
        }
        .padding(.horizontal, AppTheme.Spacing.medium)
        .padding(.vertical, AppTheme.Spacing.small)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: AppTheme.CornerRadius.medium, style: .continuous)
                .fill(Color.dsSecondaryFill)
                .overlay(
                    RoundedRectangle(cornerRadius: AppTheme.CornerRadius.medium, style: .continuous)
                        .stroke(isDropTarget ? Color.dsAction : Color.dsSeparator, lineWidth: isDropTarget ? 2 : 1)
                )
        )
        .animation(AppTheme.Animation.respectingReducedMotion(AppTheme.Animation.quickFade), value: isDropTarget)
    }

    private func selectCustomFolder() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = true

        if panel.runModal() == .OK, let url = panel.url {
            selectedURL = url
        }
    }

    private func handleDrop(providers: [NSItemProvider]) -> Bool {
        guard let provider = providers.first else { return false }

        provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, _ in
            guard let data = item as? Data,
                  let url = URL(dataRepresentation: data, relativeTo: nil) else {
                return
            }

            var isDirectory: ObjCBool = false
            if FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory),
               isDirectory.boolValue {
                Task { @MainActor in
                    selectedURL = url
                }
            }
        }
        return true
    }
}
