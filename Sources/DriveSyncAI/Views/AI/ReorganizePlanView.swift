// Copyright 2026 Amit Chorasiya. All rights reserved.
// Licensed under the Business Source License 1.1. See LICENSE file.

import SwiftUI

struct ReorganizePlanView: View {
    @Binding var plan: ReorganizePlan
    var highlightedIds: Set<UUID> = []
    var onExecute: (Bool) -> Void

    @State private var selectedSection: PlanSection = .moves

    enum PlanSection: String, CaseIterable {
        case folders = "Folders"
        case moves = "File Moves"
        case renames = "Renames"
        case cleanup = "Cleanup"
    }

    var body: some View {
        VStack(spacing: AppTheme.Spacing.medium) {
            summaryBar
            sectionPicker
            sectionContent
                .frame(maxHeight: .infinity)
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            actionBar
                .background(.ultraThinMaterial)
        }
    }

    // MARK: - Summary

    private var summaryBar: some View {
        HStack(spacing: AppTheme.Spacing.large) {
            statBadge(count: plan.moveActions.count, label: "Moves", icon: "arrow.right.doc.on.clipboard", color: .blue)
            statBadge(count: plan.renameSuggestions.count, label: "Renames", icon: "pencil", color: .purple)
            statBadge(count: plan.clutterActions.count, label: "Cleanup", icon: "trash", color: .orange)
            Spacer()
            if plan.estimatedSpaceSaved > 0 {
                Text("Save \(ByteCountFormatter.string(fromByteCount: plan.estimatedSpaceSaved, countStyle: .file))")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.green)
            }
        }
        .padding(.horizontal, AppTheme.Spacing.medium)
    }

    private func statBadge(count: Int, label: String, icon: String, color: Color) -> some View {
        HStack(spacing: 4) {
            Image(systemName: icon)
                .foregroundStyle(color)
                .font(.system(size: 12))
            Text("\(count)")
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(Color.dsPrimaryText)
            Text(label)
                .font(.system(size: 11))
                .foregroundStyle(Color.dsSecondaryText)
        }
    }

    // MARK: - Section Picker

    private var sectionPicker: some View {
        Picker("", selection: $selectedSection) {
            ForEach(PlanSection.allCases, id: \.self) { section in
                Text(section.rawValue).tag(section)
            }
        }
        .pickerStyle(.segmented)
        .padding(.horizontal, AppTheme.Spacing.medium)
    }

    // MARK: - Section Content

    @ViewBuilder
    private var sectionContent: some View {
        switch selectedSection {
        case .folders:
            foldersSection
        case .moves:
            movesSection
        case .renames:
            renamesSection
        case .cleanup:
            cleanupSection
        }
    }

    private var foldersSection: some View {
        List {
            sectionToggleAll(
                items: plan.folderSuggestions,
                toggleAll: { val in
                    for i in plan.folderSuggestions.indices { plan.folderSuggestions[i].accepted = val }
                }
            )
            ForEach($plan.folderSuggestions) { $folder in
                HStack {
                    Toggle("", isOn: $folder.accepted)
                        .toggleStyle(.checkbox)
                        .labelsHidden()
                    Image(systemName: "folder.badge.plus")
                        .foregroundStyle(.blue)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(folder.path)
                            .font(.system(size: 13, weight: .medium))
                        HStack(spacing: 6) {
                            sourceBadge(folder.source)
                            Text(folder.reason)
                                .font(.system(size: 11))
                                .foregroundStyle(Color.dsSecondaryText)
                        }
                    }
                    Spacer()
                    Text("\(folder.fileCount) files")
                        .font(.system(size: 11))
                        .foregroundStyle(Color.dsTertiaryText)
                }
            }
        }
        .listStyle(.plain)
    }

    private var movesSection: some View {
        List {
            sectionToggleAll(
                items: plan.moveActions,
                toggleAll: { val in
                    for i in plan.moveActions.indices { plan.moveActions[i].accepted = val }
                }
            )
            ForEach($plan.moveActions) { $move in
                let isHighlighted = highlightedIds.contains(move.id)
                HStack {
                    Toggle("", isOn: $move.accepted)
                        .toggleStyle(.checkbox)
                        .labelsHidden()
                    VStack(alignment: .leading, spacing: 2) {
                        Text(move.fileName)
                            .font(.system(size: 13, weight: .medium))
                        HStack(spacing: 4) {
                            Text(move.sourcePath)
                                .font(.system(size: 10, design: .monospaced))
                                .foregroundStyle(Color.dsTertiaryText)
                                .lineLimit(1)
                            Image(systemName: "arrow.right")
                                .font(.system(size: 8))
                                .foregroundStyle(Color.dsSecondaryText)
                            Text(move.destinationPath)
                                .font(.system(size: 10, design: .monospaced))
                                .foregroundStyle(.blue)
                                .lineLimit(1)
                        }
                        HStack(spacing: 6) {
                            sourceBadge(move.source)
                            confidenceBadge(move.confidence)
                            Text(move.reason)
                                .font(.system(size: 10))
                                .foregroundStyle(Color.dsTertiaryText)
                        }
                    }
                    Spacer()
                    if isHighlighted {
                        Image(systemName: "sparkle")
                            .font(.system(size: 10))
                            .foregroundStyle(.purple)
                    }
                    Text(ByteCountFormatter.string(fromByteCount: move.fileSize, countStyle: .file))
                        .font(.system(size: 11))
                        .foregroundStyle(Color.dsTertiaryText)
                }
                .listRowBackground(
                    isHighlighted ? Color.purple.opacity(0.08) : Color.clear
                )
            }
        }
        .listStyle(.plain)
    }

    private var renamesSection: some View {
        Group {
            if plan.renameSuggestions.isEmpty {
                emptyState("No rename suggestions", icon: "pencil.slash")
            } else {
                List {
                    sectionToggleAll(
                        items: plan.renameSuggestions,
                        toggleAll: { val in
                            for i in plan.renameSuggestions.indices { plan.renameSuggestions[i].accepted = val }
                        }
                    )
                    ForEach($plan.renameSuggestions) { $rename in
                        HStack {
                            Toggle("", isOn: $rename.accepted)
                                .toggleStyle(.checkbox)
                                .labelsHidden()
                            VStack(alignment: .leading, spacing: 2) {
                                HStack(spacing: 4) {
                                    Text(rename.originalName)
                                        .font(.system(size: 12, design: .monospaced))
                                        .foregroundStyle(Color.dsSecondaryText)
                                        .strikethrough()
                                    Image(systemName: "arrow.right")
                                        .font(.system(size: 8))
                                    Text(rename.suggestedName)
                                        .font(.system(size: 12, weight: .medium, design: .monospaced))
                                        .foregroundStyle(.purple)
                                }
                                Text(rename.reason)
                                    .font(.system(size: 10))
                                    .foregroundStyle(Color.dsTertiaryText)
                            }
                            Spacer()
                        }
                    }
                }
                .listStyle(.plain)
            }
        }
    }

    private var cleanupSection: some View {
        List {
            sectionToggleAll(
                items: plan.clutterActions,
                toggleAll: { val in
                    for i in plan.clutterActions.indices { plan.clutterActions[i].accepted = val }
                }
            )
            ForEach($plan.clutterActions) { $clutter in
                HStack {
                    Toggle("", isOn: $clutter.accepted)
                        .toggleStyle(.checkbox)
                        .labelsHidden()
                    Image(systemName: clutter.action.icon)
                        .foregroundStyle(clutter.action == .delete ? Color.dsDestructive : .orange)
                        .font(.system(size: 12))
                    VStack(alignment: .leading, spacing: 2) {
                        Text(clutter.path)
                            .font(.system(size: 12, design: .monospaced))
                            .lineLimit(1)
                        Text(clutter.reason)
                            .font(.system(size: 10))
                            .foregroundStyle(Color.dsTertiaryText)
                    }
                    Spacer()
                    if clutter.size > 0 {
                        Text(ByteCountFormatter.string(fromByteCount: clutter.size, countStyle: .file))
                            .font(.system(size: 11))
                            .foregroundStyle(Color.dsTertiaryText)
                    }
                }
            }
        }
        .listStyle(.plain)
    }

    // MARK: - Action Bar

    private var actionBar: some View {
        HStack {
            HStack(spacing: 4) {
                Image(systemName: "shield.checkered")
                    .foregroundStyle(.green)
                Text("All operations are journaled and can be rolled back")
                    .font(.system(size: 11))
                    .foregroundStyle(Color.dsSecondaryText)
            }

            Spacer()

            GlassButton("Dry Run", icon: "eye", style: .secondary) {
                onExecute(true)
            }

            GlassButton("Execute Plan", icon: "play.fill", style: .primary, isDisabled: plan.totalAcceptedActions == 0) {
                onExecute(false)
            }
        }
        .padding(.horizontal, AppTheme.Spacing.medium)
        .padding(.vertical, AppTheme.Spacing.medium)
    }

    // MARK: - Helpers

    private func sourceBadge(_ source: PlanSource) -> some View {
        Text(source.displayName)
            .font(.system(size: 9, weight: .bold))
            .foregroundStyle(.white)
            .padding(.horizontal, 5)
            .padding(.vertical, 1)
            .background(badgeColor(for: source), in: Capsule())
    }

    private func badgeColor(for source: PlanSource) -> Color {
        switch source {
        case .deterministic: return .green
        case .metadata: return .blue
        case .ai: return .purple
        case .customRule: return .orange
        case .merged: return .gray
        }
    }

    private func confidenceBadge(_ confidence: Double) -> some View {
        Text("\(Int(confidence * 100))%")
            .font(.system(size: 9, weight: .medium))
            .foregroundStyle(confidence >= 0.8 ? .green : (confidence >= 0.5 ? .orange : .red))
    }

    private func sectionToggleAll<T>(items: [T], toggleAll: @escaping (Bool) -> Void) -> some View {
        HStack {
            Button("Select All") { toggleAll(true) }
                .font(.system(size: 11))
                .buttonStyle(.link)
            Text("|")
                .foregroundStyle(Color.dsTertiaryText)
            Button("Deselect All") { toggleAll(false) }
                .font(.system(size: 11))
                .buttonStyle(.link)
            Spacer()
            Text("\(items.count) items")
                .font(.system(size: 11))
                .foregroundStyle(Color.dsTertiaryText)
        }
    }

    private func emptyState(_ message: String, icon: String) -> some View {
        VStack(spacing: AppTheme.Spacing.medium) {
            Image(systemName: icon)
                .font(.system(size: 28))
                .foregroundStyle(Color.dsTertiaryText)
            Text(message)
                .font(.system(size: 13))
                .foregroundStyle(Color.dsSecondaryText)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
