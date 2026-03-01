// Copyright 2026 Amit Chorasiya. All rights reserved.
// Licensed under the Business Source License 1.1. See LICENSE file.

import SwiftUI
import AppKit
import UniformTypeIdentifiers

/// File list row with checkbox, action badge, file icon, name, size, and modification date.
struct FileRowView: View {
    let fileInfo: FileInfo
    let actionType: SyncActionType
    let isSelected: Bool
    let isChecked: Bool
    let onToggle: () -> Void

    @State private var isHovering = false

    private var formattedDate: String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: fileInfo.modificationDate, relativeTo: Date())
    }

    var body: some View {
        HStack(spacing: AppTheme.Spacing.medium) {
            // Checkbox
            Toggle("", isOn: Binding(
                get: { isChecked },
                set: { _ in onToggle() }
            ))
            .toggleStyle(.checkbox)
            .labelsHidden()

            // Action badge
            ActionBadgeView(actionType: actionType)

            // File icon
            FileIconView(url: fileInfo.url, isDirectory: fileInfo.isDirectory)

            // File name
            VStack(alignment: .leading, spacing: 2) {
                Text(fileInfo.name)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Color.dsPrimaryText)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            // File size
            Text(fileInfo.formattedSize)
                .font(.system(size: 12))
                .foregroundStyle(Color.dsSecondaryText)
                .frame(width: 60, alignment: .trailing)

            // Modification date
            Text(formattedDate)
                .font(.system(size: 12))
                .foregroundStyle(Color.dsTertiaryText)
                .frame(width: 70, alignment: .trailing)
        }
        .padding(.horizontal, AppTheme.Spacing.medium)
        .padding(.vertical, AppTheme.Spacing.small)
        .background(rowBackground)
        .contentShape(Rectangle())
        .onHover { hovering in
            isHovering = hovering
        }
    }

    @ViewBuilder
    private var rowBackground: some View {
        if isSelected {
            Color.dsAction.opacity(0.2)
        } else if isHovering {
            Color.dsSecondaryFill
        } else {
            Color.clear
        }
    }
}

// MARK: - File Icon from NSWorkspace

private struct FileIconView: View {
    let url: URL
    let isDirectory: Bool

    var body: some View {
        Image(nsImage: iconImage)
            .resizable()
            .aspectRatio(contentMode: .fit)
            .frame(width: 20, height: 20)
    }

    private var iconImage: NSImage {
        if isDirectory {
            return NSWorkspace.shared.icon(forFile: url.path)
        }
        let contentType = UTType(filenameExtension: url.pathExtension) ?? .data
        return NSWorkspace.shared.icon(for: contentType)
    }
}
