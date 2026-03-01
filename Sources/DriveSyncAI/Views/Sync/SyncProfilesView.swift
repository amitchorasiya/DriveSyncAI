// Copyright 2026 Amit Chorasiya. All rights reserved.
// Licensed under the Business Source License 1.1. See LICENSE file.

import SwiftUI

struct SyncProfilesView: View {
    @EnvironmentObject var syncService: SyncService
    @ObservedObject var profileManager: SyncProfileManager
    @Environment(\.dismiss) private var dismiss

    @State private var showSaveSheet = false
    @State private var newProfileName = ""

    var body: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.xl) {
            headerSection

            if profileManager.profiles.isEmpty {
                emptyState
            } else {
                profileList
            }

            Spacer()
        }
        .padding(AppTheme.Spacing.xl)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .background(Color.dsBackground)
        .sheet(isPresented: $showSaveSheet) {
            saveSheet
        }
    }

    private var headerSection: some View {
        HStack {
            Text("Sync Profiles")
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(Color.dsPrimaryText)

            Spacer()

            GlassButton("Save Current", icon: "square.and.arrow.down", style: .secondary) {
                newProfileName = defaultProfileName()
                showSaveSheet = true
            }
        }
    }

    private func defaultProfileName() -> String {
        let source = syncService.sourceURL?.lastPathComponent ?? "Source"
        let target = syncService.targetURL?.lastPathComponent ?? "Target"
        return "\(source) → \(target)"
    }

    private var emptyState: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: AppTheme.Spacing.large) {
                Image(systemName: "folder.badge.plus")
                    .font(.system(size: 40))
                    .foregroundStyle(Color.dsSecondaryText)

                Text("No saved profiles")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(Color.dsPrimaryText)

                Text("Save your current sync configuration to create one.")
                    .font(.system(size: 13))
                    .foregroundStyle(Color.dsSecondaryText)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var profileList: some View {
        List {
            ForEach(profileManager.profiles) { profile in
                profileRow(profile)
                    .listRowInsets(EdgeInsets(top: AppTheme.Spacing.small, leading: 0, bottom: AppTheme.Spacing.small, trailing: 0))
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
            }
            .onDelete { indexSet in
                for idx in indexSet {
                    profileManager.delete(profileManager.profiles[idx].id)
                }
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
    }

    private func profileRow(_ profile: SyncProfile) -> some View {
        GlassCard {
            HStack(spacing: AppTheme.Spacing.medium) {
                directionIcon(profile.direction)

                VStack(alignment: .leading, spacing: 4) {
                    Text(profile.name)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(Color.dsPrimaryText)

                    Text("\(profile.sourceURL.lastPathComponent) → \(profile.targetURL.lastPathComponent)")
                        .font(.system(size: 12))
                        .foregroundStyle(Color.dsSecondaryText)
                        .lineLimit(1)
                        .truncationMode(.middle)

                    if let lastUsed = profile.lastUsedAt {
                        Text("Last used: \(formatDate(lastUsed))")
                            .font(.system(size: 11))
                            .foregroundStyle(Color.dsTertiaryText)
                    }
                }

                Spacer()

                GlassButton("Apply", icon: "checkmark.circle", style: .primary) {
                    profileManager.applyProfile(profile, to: syncService)
                    dismiss()
                }
            }
            .contentShape(Rectangle())
        }
        .contextMenu {
            Button("Apply", systemImage: "checkmark.circle") {
                profileManager.applyProfile(profile, to: syncService)
                dismiss()
            }
            Button("Delete", systemImage: "trash", role: .destructive) {
                profileManager.delete(profile.id)
            }
        }
    }

    private func directionIcon(_ direction: SyncDirection) -> some View {
        Group {
            switch direction {
            case .oneWayMirror:
                Image(systemName: "arrow.right.circle.fill")
            case .oneWayUpdate:
                Image(systemName: "arrow.right.circle")
            case .bidirectional:
                Image(systemName: "arrow.left.arrow.right.circle")
            }
        }
        .font(.system(size: 22))
        .foregroundStyle(Color.dsAction)
    }

    private func formatDate(_ date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: date, relativeTo: Date())
    }

    private var saveSheet: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.xl) {
            Text("Save as Profile")
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(Color.dsPrimaryText)

            TextField("Profile name", text: $newProfileName)
                .textFieldStyle(.roundedBorder)
                .padding(.vertical, AppTheme.Spacing.small)

            HStack {
                Spacer()
                Button("Cancel") {
                    showSaveSheet = false
                }
                .keyboardShortcut(.cancelAction)

                GlassButton("Save", icon: "square.and.arrow.down") {
                    guard !newProfileName.trimmingCharacters(in: .whitespaces).isEmpty else { return }
                    _ = profileManager.createProfileFromCurrent(newProfileName.trimmingCharacters(in: .whitespaces), syncService: syncService)
                    showSaveSheet = false
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(AppTheme.Spacing.xl)
        .frame(minWidth: 360)
    }
}
