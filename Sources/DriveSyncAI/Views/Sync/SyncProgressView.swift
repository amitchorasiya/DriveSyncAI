// Copyright 2026 Amit Chorasiya. All rights reserved.
// Licensed under the Business Source License 1.1. See LICENSE file.

import SwiftUI

/// Real-time sync progress with live updates
struct SyncProgressView: View {
    @EnvironmentObject var syncService: SyncService

    @State private var showErrors = false

    var body: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: AppTheme.Spacing.xl) {
                progressContent
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .sheet(isPresented: $showErrors) {
            errorSheet
        }
    }

    // MARK: - Progress Content

    private var progressContent: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.large) {
            AnimatedProgressBar(
                value: syncService.progress.bytesPercentage / 100,
                label: "Syncing",
                detailText: nil,
                isIndeterminate: syncService.progress.totalBytes == 0 && syncService.progress.totalFiles > 0
            )
            .frame(height: 56)

            if !syncService.progress.currentFileName.isEmpty {
                Text(truncatedFileName(syncService.progress.currentFileName))
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Color.dsSecondaryText)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }

            statsRow

            if syncService.progress.totalBytes > 0 {
                Text("\(ByteCountFormatter.string(fromByteCount: Int64(syncService.progress.transferredBytes), countStyle: .file)) of \(ByteCountFormatter.string(fromByteCount: Int64(syncService.progress.totalBytes), countStyle: .file))")
                    .font(.system(size: 11))
                    .foregroundStyle(Color.dsTertiaryText)
            }

            if !syncService.errors.isEmpty {
                errorCounterButton
            }

            actionButtons
        }
    }

    private var statsRow: some View {
        HStack(spacing: AppTheme.Spacing.xl) {
            statItem(
                icon: "speedometer",
                value: formattedSpeed(syncService.progress.speed),
                label: "Speed"
            )
            statItem(
                icon: "clock",
                value: formattedETA(syncService.progress.eta),
                label: "ETA"
            )
            statItem(
                icon: "doc",
                value: "\(syncService.progress.completedFiles) / \(syncService.progress.totalFiles)",
                label: "Files"
            )
        }
    }

    private func statItem(icon: String, value: String, label: String) -> some View {
        HStack(spacing: AppTheme.Spacing.small) {
            Image(systemName: icon)
                .font(.system(size: 12))
                .foregroundStyle(Color.dsSecondaryText)
            VStack(alignment: .leading, spacing: 0) {
                Text(value)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Color.dsPrimaryText)
                Text(label)
                    .font(.system(size: 10))
                    .foregroundStyle(Color.dsTertiaryText)
            }
        }
    }

    private func formattedSpeed(_ bytesPerSec: Double) -> String {
        guard bytesPerSec > 0 else { return "—" }
        let mbPerSec = bytesPerSec / (1024 * 1024)
        if mbPerSec >= 1 {
            return String(format: "%.2f MB/s", mbPerSec)
        }
        let kbPerSec = bytesPerSec / 1024
        return String(format: "%.1f KB/s", kbPerSec)
    }

    private func formattedETA(_ eta: TimeInterval) -> String {
        guard eta > 0, eta.isFinite else { return "—" }
        let formatter = DateComponentsFormatter()
        formatter.allowedUnits = [.hour, .minute, .second]
        formatter.unitsStyle = .abbreviated
        return formatter.string(from: eta) ?? "—"
    }

    private func truncatedFileName(_ name: String) -> String {
        let maxLen = 60
        guard name.count > maxLen else { return name }
        let mid = maxLen / 2
        let start = name.prefix(mid - 3)
        let end = name.suffix(mid - 3)
        return "\(start)...\(end)"
    }

    private var errorCounterButton: some View {
        Button {
            showErrors = true
        } label: {
            HStack(spacing: AppTheme.Spacing.small) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 12))
                Text("\(syncService.errors.count) error\(syncService.errors.count == 1 ? "" : "s")")
                    .font(.system(size: 13, weight: .medium))
            }
            .foregroundStyle(Color.dsDestructive)
        }
        .buttonStyle(.plain)
    }

    private var actionButtons: some View {
        HStack(spacing: AppTheme.Spacing.medium) {
            if syncService.state == .syncing {
                GlassButton("Pause", icon: "pause.fill", style: .secondary) {
                    syncService.pause()
                }
            } else if syncService.state == .paused {
                GlassButton("Resume", icon: "play.fill", style: .primary) {
                    Task { await syncService.resume() }
                }
            }

            GlassButton("Cancel", icon: "xmark", style: .destructive) {
                syncService.cancel()
            }
            .keyboardShortcut(.escape, modifiers: [])
        }
    }

    // MARK: - Error Sheet

    private var errorSheet: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.large) {
            HStack {
                Text("Sync Errors")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(Color.dsPrimaryText)
                Spacer()
                Button("Done") {
                    showErrors = false
                }
            }
            .padding()

            Divider()

            ScrollView {
                LazyVStack(alignment: .leading, spacing: AppTheme.Spacing.medium) {
                    ForEach(syncService.errors) { error in
                        VStack(alignment: .leading, spacing: 4) {
                            if !error.filePath.isEmpty {
                                Text(error.filePath)
                                    .font(.system(size: 12, weight: .medium))
                                    .foregroundStyle(Color.dsPrimaryText)
                                    .lineLimit(2)
                                    .truncationMode(.middle)
                            }
                            Text(error.message)
                                .font(.system(size: 13))
                                .foregroundStyle(Color.dsSecondaryText)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(AppTheme.Spacing.medium)
                        .background(Color.dsSecondaryFill)
                        .clipShape(RoundedRectangle(cornerRadius: AppTheme.CornerRadius.medium, style: .continuous))
                    }
                }
                .padding()
            }
        }
        .frame(minWidth: 400, minHeight: 300)
    }
}
