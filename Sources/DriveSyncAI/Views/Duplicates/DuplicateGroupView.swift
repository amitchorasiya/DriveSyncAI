// Copyright 2026 Amit Chorasiya. All rights reserved.
// Licensed under the Business Source License 1.1. See LICENSE file.

import SwiftUI
import AppKit
import UniformTypeIdentifiers

/// Expandable duplicate group showing files with keep/remove selection.
struct DuplicateGroupView: View {
    let group: DuplicateGroup
    let onToggle: (UUID) -> Void
    var onFileClick: ((FileInfo) -> Void)? = nil
    @State private var isExpanded = false

    private var primaryFileName: String {
        group.files.first?.fileInfo.name ?? "Unknown"
    }

    private var sizePerCopy: UInt64 {
        guard !group.files.isEmpty else { return 0 }
        return group.totalSize / UInt64(group.files.count)
    }

    var body: some View {
        GlassCard(padding: nil) {
            VStack(alignment: .leading, spacing: 0) {
                groupHeader
                if isExpanded {
                    fileList
                }
            }
        }
    }

    private var groupHeader: some View {
        Button {
            withAnimation(AppTheme.Animation.respectingReducedMotion(AppTheme.Animation.springSnappy)) {
                isExpanded.toggle()
            }
        } label: {
            HStack(spacing: AppTheme.Spacing.medium) {
                Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Color.dsSecondaryText)
                    .frame(width: 16, alignment: .center)

                Image(nsImage: iconForFile(name: primaryFileName))
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 24, height: 24)

                VStack(alignment: .leading, spacing: 2) {
                    Text(primaryFileName)
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(Color.dsPrimaryText)
                        .lineLimit(1)
                        .truncationMode(.middle)

                    Text("\(group.files.count) copies · \(ByteCountFormatter.string(fromByteCount: Int64(sizePerCopy), countStyle: .file)) each · \(group.formattedWaste) waste")
                        .font(.system(size: 12))
                        .foregroundStyle(Color.dsSecondaryText)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                Text(group.formattedWaste)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Color.dsWarning)
            }
            .padding(AppTheme.Spacing.large)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private var fileList: some View {
        Divider()
            .background(Color.dsSeparator)

        VStack(spacing: 0) {
            ForEach(group.files) { file in
                duplicateFileRow(file)
                if file.id != group.files.last?.id {
                    Divider()
                        .background(Color.dsSeparator)
                        .padding(.leading, AppTheme.Spacing.xl + 16)
                }
            }
        }
    }

    private func duplicateFileRow(_ file: DuplicateFile) -> some View {
        let isKept = !file.isSelected
        let isDimmed = file.isSelected

        return HStack(spacing: AppTheme.Spacing.medium) {
            Toggle("", isOn: Binding(
                get: { file.isSelected },
                set: { _ in onToggle(file.id) }
            ))
            .toggleStyle(.checkbox)
            .labelsHidden()

            Button {
                onFileClick?(file.fileInfo)
            } label: {
                HStack(spacing: AppTheme.Spacing.medium) {
                    Image(nsImage: iconForFile(name: file.fileInfo.name))
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 20, height: 20)

                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: AppTheme.Spacing.small) {
                            Text(file.fileInfo.relativePath)
                                .font(.system(size: 13, weight: .regular))
                                .foregroundStyle(isDimmed ? Color.dsTertiaryText : Color.dsPrimaryText)
                                .lineLimit(1)
                                .truncationMode(.middle)

                            if isKept {
                                Text("KEEP")
                                    .font(.system(size: 10, weight: .bold))
                                    .foregroundStyle(Color.dsSuccess)
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(Color.dsSuccess.opacity(0.15), in: RoundedRectangle(cornerRadius: 4, style: .continuous))
                            }
                        }

                        Text("\(file.fileInfo.formattedSize) · \(formatDate(file.fileInfo.modificationDate))")
                            .font(.system(size: 11))
                            .foregroundStyle(Color.dsTertiaryText)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)

                    Text(file.fileInfo.formattedSize)
                        .font(.system(size: 12))
                        .foregroundStyle(Color.dsSecondaryText)
                }
                .padding(.horizontal, AppTheme.Spacing.medium)
                .padding(.vertical, AppTheme.Spacing.small)
                .opacity(isDimmed ? 0.6 : 1)
            }
            .buttonStyle(.plain)
        }
        .padding(.leading, AppTheme.Spacing.medium)
    }

    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }

    private func iconForFile(name: String) -> NSImage {
        let ext = (name as NSString).pathExtension
        let contentType = UTType(filenameExtension: ext) ?? .data
        return NSWorkspace.shared.icon(for: contentType)
    }
}
