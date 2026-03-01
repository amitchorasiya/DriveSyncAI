// Copyright 2026 Amit Chorasiya. All rights reserved.
// Licensed under the Business Source License 1.1. See LICENSE file.

import SwiftUI
import AppKit
import UniformTypeIdentifiers

struct SimilarFilesView: View {
    @Binding var groups: [SimilarGroup]
    let onToggle: (UUID, UUID) -> Void
    let onMoveSelected: () -> Void
    let onFileClick: (FileInfo) -> Void

    @State private var expandedGroupIds: Set<UUID> = []

    private var selectedCount: Int {
        groups.reduce(0) { $0 + $1.similarFiles.filter(\.isSelected).count }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: AppTheme.Spacing.xl) {
                headerSection
                groupsList
                footerSection
            }
            .padding(AppTheme.Spacing.xl)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(Color.dsBackground)
    }

    private var headerSection: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: AppTheme.Spacing.small) {
                Text("\(groups.count) similar file groups found")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(Color.dsPrimaryText)
                Text("Files that may be related but are not exact duplicates")
                    .font(.system(size: 14))
                    .foregroundStyle(Color.dsSecondaryText)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var groupsList: some View {
        LazyVStack(spacing: AppTheme.Spacing.medium) {
            ForEach(groups) { group in
                SimilarGroupRow(
                    group: group,
                    isExpanded: expandedGroupIds.contains(group.id),
                    onToggleExpand: {
                        withAnimation(AppTheme.Animation.respectingReducedMotion(AppTheme.Animation.springSnappy)) {
                            if expandedGroupIds.contains(group.id) {
                                expandedGroupIds.remove(group.id)
                            } else {
                                expandedGroupIds.insert(group.id)
                            }
                        }
                    },
                    onToggle: { fileId in onToggle(group.id, fileId) },
                    onFileClick: onFileClick
                )
            }
        }
    }

    private var footerSection: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.medium) {
            HStack(spacing: AppTheme.Spacing.large) {
                Text("Selected: \(selectedCount) files")
                    .font(.system(size: 13))
                    .foregroundStyle(Color.dsSecondaryText)

                GlassButton("Move Selected", icon: "folder.badge.arrow.down", isDisabled: selectedCount == 0) {
                    onMoveSelected()
                }
            }
        }
    }
}

// MARK: - SimilarGroupRow

private struct SimilarGroupRow: View {
    let group: SimilarGroup
    let isExpanded: Bool
    let onToggleExpand: () -> Void
    let onToggle: (UUID) -> Void
    let onFileClick: (FileInfo) -> Void

    private var reasonColor: Color {
        switch group.similarityReason {
        case .similarName: return .dsAction
        case .similarSize: return .dsWarning
        case .sameNameDiffExt: return .dsSuccess
        case .nearbyDate: return Color.dsPrimaryFallback
        }
    }

    var body: some View {
        GlassCard(padding: nil) {
            VStack(alignment: .leading, spacing: 0) {
                Button {
                    onToggleExpand()
                } label: {
                    HStack(spacing: AppTheme.Spacing.medium) {
                        Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(Color.dsSecondaryText)
                            .frame(width: 16, alignment: .center)

                        Image(nsImage: iconForFile(name: group.referenceFile.name))
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(width: 24, height: 24)

                        VStack(alignment: .leading, spacing: 2) {
                            Text(group.referenceFile.name)
                                .font(.system(size: 14, weight: .medium))
                                .foregroundStyle(Color.dsPrimaryText)
                                .lineLimit(1)
                                .truncationMode(.middle)
                            Text("\(group.similarFiles.count) similar · \(group.formattedWaste)")
                                .font(.system(size: 12))
                                .foregroundStyle(Color.dsSecondaryText)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)

                        Text(group.similarityReason.displayName)
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(reasonColor)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(reasonColor.opacity(0.15), in: RoundedRectangle(cornerRadius: 6, style: .continuous))

                        Text(group.formattedWaste)
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(Color.dsWarning)
                    }
                    .padding(AppTheme.Spacing.large)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)

                if isExpanded {
                    Divider()
                        .background(Color.dsSeparator)
                    VStack(spacing: 0) {
                        referenceFileRow
                        ForEach(group.similarFiles) { similar in
                            Divider()
                                .background(Color.dsSeparator)
                                .padding(.leading, AppTheme.Spacing.xl + 16)
                            similarFileRow(similar)
                        }
                    }
                }
            }
        }
    }

    private var referenceFileRow: some View {
        HStack(spacing: AppTheme.Spacing.medium) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 14))
                .foregroundStyle(Color.dsSuccess)
            Button {
                onFileClick(group.referenceFile)
            } label: {
                HStack(spacing: AppTheme.Spacing.medium) {
                    Image(nsImage: iconForFile(name: group.referenceFile.name))
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 20, height: 20)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(group.referenceFile.relativePath)
                            .font(.system(size: 13))
                            .foregroundStyle(Color.dsPrimaryText)
                            .lineLimit(1)
                            .truncationMode(.middle)
                        Text("\(group.referenceFile.formattedSize) · Reference")
                            .font(.system(size: 11))
                            .foregroundStyle(Color.dsTertiaryText)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding(.horizontal, AppTheme.Spacing.medium)
                .padding(.vertical, AppTheme.Spacing.small)
            }
            .buttonStyle(.plain)
        }
        .padding(.leading, AppTheme.Spacing.medium)
    }

    private func similarFileRow(_ similar: SimilarFile) -> some View {
        HStack(spacing: AppTheme.Spacing.medium) {
            Toggle("", isOn: Binding(
                get: { similar.isSelected },
                set: { _ in onToggle(similar.id) }
            ))
            .toggleStyle(.checkbox)
            .labelsHidden()

            Button {
                onFileClick(similar.fileInfo)
            } label: {
                HStack(spacing: AppTheme.Spacing.medium) {
                    Image(nsImage: iconForFile(name: similar.fileInfo.name))
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 20, height: 20)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(similar.fileInfo.relativePath)
                            .font(.system(size: 13))
                            .foregroundStyle(similar.isSelected ? Color.dsTertiaryText : Color.dsPrimaryText)
                            .lineLimit(1)
                            .truncationMode(.middle)
                        Text("\(similar.fileInfo.formattedSize) · \(Int(similar.similarity * 100))% similar")
                            .font(.system(size: 11))
                            .foregroundStyle(Color.dsTertiaryText)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    Text(similar.fileInfo.formattedSize)
                        .font(.system(size: 12))
                        .foregroundStyle(Color.dsSecondaryText)
                }
                .padding(.horizontal, AppTheme.Spacing.medium)
                .padding(.vertical, AppTheme.Spacing.small)
                .opacity(similar.isSelected ? 0.6 : 1)
            }
            .buttonStyle(.plain)
        }
        .padding(.leading, AppTheme.Spacing.medium)
    }

    private func iconForFile(name: String) -> NSImage {
        let ext = (name as NSString).pathExtension
        let contentType = UTType(filenameExtension: ext) ?? .data
        return NSWorkspace.shared.icon(for: contentType)
    }
}
