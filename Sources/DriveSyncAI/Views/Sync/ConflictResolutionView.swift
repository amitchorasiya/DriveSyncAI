// Copyright 2026 Amit Chorasiya. All rights reserved.
// Licensed under the Business Source License 1.1. See LICENSE file.

import SwiftUI
import AppKit

/// Dedicated conflict resolution UI shown as a sheet when user clicks "Resolve Conflicts"
/// or taps a conflict row. Shows all conflict actions for batch or per-conflict resolution.
struct ConflictResolutionView: View {
    @EnvironmentObject var syncService: SyncService
    @Environment(\.dismiss) var dismiss

    private var conflicts: [SyncAction] {
        syncService.actions.filter { $0.actionType == .conflict }
    }

    @State private var batchStrategy: ConflictResolutionStrategy = .keepNewer
    @State private var initialConflictCount: Int = 0

    private var resolvedCount: Int {
        initialConflictCount - conflicts.count
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            batchResolutionSection
            conflictList
            footer
        }
        .frame(minWidth: 560, minHeight: 420)
        .background(Color.dsBackground)
        .onAppear {
            initialConflictCount = conflicts.count
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: AppTheme.Spacing.medium) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 24))
                .foregroundStyle(Color.dsWarning)

            Text("\(conflicts.count) conflict\(conflicts.count == 1 ? "" : "s") found")
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(Color.dsPrimaryText)
        }
        .padding(.horizontal, AppTheme.Spacing.xl)
        .padding(.vertical, AppTheme.Spacing.large)
    }

    // MARK: - Batch Resolution Section

    private var batchResolutionSection: some View {
        GlassCard(padding: AppTheme.Spacing.large) {
            VStack(alignment: .leading, spacing: AppTheme.Spacing.medium) {
                Text("Apply strategy to all conflicts")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Color.dsSecondaryText)

                HStack(spacing: AppTheme.Spacing.medium) {
                    Picker("Strategy", selection: $batchStrategy) {
                        ForEach(ConflictResolutionStrategy.allCases, id: \.self) { strategy in
                            Text(strategyDisplayName(strategy))
                                .tag(strategy)
                        }
                    }
                    .pickerStyle(.menu)
                    .frame(width: 180)

                    GlassButton("Apply to All Conflicts", icon: "checkmark.circle.fill", style: .primary, isDisabled: conflicts.isEmpty) {
                        applyBatchResolution()
                    }
                }
            }
        }
        .padding(.horizontal, AppTheme.Spacing.xl)
        .padding(.bottom, AppTheme.Spacing.medium)
    }

    // MARK: - Conflict List

    private var conflictList: some View {
        GlassCard(padding: 0) {
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(conflicts) { conflict in
                        ConflictRowView(
                            conflict: conflict,
                            onResolve: { strategy in
                                syncService.resolveConflict(actionId: conflict.id, strategy: strategy)
                            }
                        )

                        if conflict.id != conflicts.last?.id {
                            Divider()
                                .background(Color.dsSeparator)
                                .padding(.horizontal, AppTheme.Spacing.large)
                        }
                    }
                }
                .padding(.vertical, AppTheme.Spacing.small)
            }
            .frame(maxHeight: 280)
        }
        .padding(.horizontal, AppTheme.Spacing.xl)
        .padding(.bottom, AppTheme.Spacing.medium)
    }

    // MARK: - Footer

    private var footer: some View {
        HStack(spacing: AppTheme.Spacing.large) {
            Text("\(resolvedCount) of \(initialConflictCount) resolved")
                .font(.system(size: 13))
                .foregroundStyle(Color.dsSecondaryText)

            Spacer()

            GlassButton("Done", icon: "checkmark", style: .primary) {
                dismiss()
            }
        }
        .padding(.horizontal, AppTheme.Spacing.xl)
        .padding(.vertical, AppTheme.Spacing.large)
        .background(Color.dsSecondaryFill.opacity(0.3))
    }

    // MARK: - Helpers

    private func strategyDisplayName(_ strategy: ConflictResolutionStrategy) -> String {
        switch strategy {
        case .keepBoth: return "Keep Both"
        case .keepNewer: return "Keep Newer"
        case .keepLarger: return "Keep Larger"
        case .keepSource: return "Keep Source"
        case .keepTarget: return "Keep Target"
        case .skip: return "Skip"
        }
    }

    private func applyBatchResolution() {
        let ids = conflicts.map(\.id)
        for id in ids {
            syncService.resolveConflict(actionId: id, strategy: batchStrategy)
        }
    }
}

// MARK: - Conflict Row View

private struct ConflictRowView: View {
    let conflict: SyncAction
    let onResolve: (ConflictResolutionStrategy) -> Void

    var body: some View {
        if let sourceFile = conflict.sourceFile, let targetFile = conflict.targetFile {
            conflictContent(sourceFile: sourceFile, targetFile: targetFile)
        }
    }

    private func conflictContent(sourceFile: FileInfo, targetFile: FileInfo) -> some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.medium) {
            HStack(spacing: AppTheme.Spacing.medium) {
                Image(nsImage: NSWorkspace.shared.icon(forFile: sourceFile.url.path))
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 24, height: 24)

                Text(conflict.displayName)
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(Color.dsPrimaryText)
                        .lineLimit(1)
                        .truncationMode(.middle)

                    Spacer()

                    statusBadge
                }

                sideBySideComparison(source: sourceFile, target: targetFile)
                resolutionButtons
            }
            .padding(.horizontal, AppTheme.Spacing.large)
            .padding(.vertical, AppTheme.Spacing.medium)
    }

    private var statusBadge: some View {
        Text("Unresolved")
            .font(.system(size: 10, weight: .medium))
            .foregroundStyle(Color.dsWarning)
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .background(Color.dsWarning.opacity(0.2), in: RoundedRectangle(cornerRadius: 4, style: .continuous))
    }

    private func sideBySideComparison(source: FileInfo, target: FileInfo) -> some View {
        let sourceNewer = source.modificationDate >= target.modificationDate
        let targetNewer = target.modificationDate > source.modificationDate
        let sourceLarger = source.size >= target.size
        let targetLarger = target.size > source.size

        return HStack(spacing: AppTheme.Spacing.medium) {
            // Source column
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 4) {
                    Text("Source")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Color.dsSecondaryText)
                    if sourceNewer {
                        diffBadge("Newer")
                    }
                    if sourceLarger {
                        diffBadge("Larger")
                    }
                }
                Text(formattedDate(source.modificationDate))
                    .font(.system(size: 12))
                    .foregroundStyle(Color.dsPrimaryText)
                Text(source.formattedSize)
                    .font(.system(size: 11))
                    .foregroundStyle(Color.dsTertiaryText)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(AppTheme.Spacing.medium)
            .background(Color.dsSecondaryFill.opacity(0.6), in: RoundedRectangle(cornerRadius: AppTheme.CornerRadius.small, style: .continuous))

            // VS divider
            Image(systemName: "arrow.left.arrow.right")
                .font(.system(size: 12))
                .foregroundStyle(Color.dsTertiaryText)

            // Target column
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 4) {
                    Text("Target")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Color.dsSecondaryText)
                    if targetNewer {
                        diffBadge("Newer")
                    }
                    if targetLarger {
                        diffBadge("Larger")
                    }
                }
                Text(formattedDate(target.modificationDate))
                    .font(.system(size: 12))
                    .foregroundStyle(Color.dsPrimaryText)
                Text(target.formattedSize)
                    .font(.system(size: 11))
                    .foregroundStyle(Color.dsTertiaryText)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(AppTheme.Spacing.medium)
            .background(Color.dsSecondaryFill.opacity(0.6), in: RoundedRectangle(cornerRadius: AppTheme.CornerRadius.small, style: .continuous))
        }
    }

    private func diffBadge(_ label: String) -> some View {
        Text(label)
            .font(.system(size: 9, weight: .semibold))
            .foregroundStyle(Color.dsAction)
            .padding(.horizontal, 4)
            .padding(.vertical, 2)
            .background(Color.dsAction.opacity(0.15), in: Capsule())
    }

    private var resolutionButtons: some View {
        HStack(spacing: AppTheme.Spacing.small) {
            resolutionButton("Keep Source", strategy: .keepSource)
            resolutionButton("Keep Target", strategy: .keepTarget)
            resolutionButton("Keep Newer", strategy: .keepNewer)
            resolutionButton("Keep Larger", strategy: .keepLarger)
            resolutionButton("Keep Both", strategy: .keepBoth)
            resolutionButton("Skip", strategy: .skip)
        }
    }

    private func resolutionButton(_ title: String, strategy: ConflictResolutionStrategy) -> some View {
        Button(title) {
            onResolve(strategy)
        }
        .buttonStyle(.bordered)
        .controlSize(.small)
    }

    private func formattedDate(_ date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: date, relativeTo: Date())
    }
}
