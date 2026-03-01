// Copyright 2026 Amit Chorasiya. All rights reserved.
// Licensed under the Business Source License 1.1. See LICENSE file.

import SwiftUI

enum NavigationItem: String, Hashable, CaseIterable {
    case dashboard
    case sync
    case duplicates
    case aiOrganize
    case settings

    var label: String {
        switch self {
        case .dashboard: return "Dashboard"
        case .sync: return "Sync"
        case .duplicates: return "Duplicates"
        case .aiOrganize: return "AI Organize"
        case .settings: return "Settings"
        }
    }

    var icon: String {
        switch self {
        case .dashboard: return "square.grid.2x2"
        case .sync: return "arrow.triangle.2.circlepath"
        case .duplicates: return "doc.on.doc"
        case .aiOrganize: return "brain.head.profile"
        case .settings: return "gearshape"
        }
    }

    var keyboardShortcut: KeyEquivalent? {
        switch self {
        case .dashboard: return "1"
        case .sync: return "2"
        case .duplicates: return "3"
        case .aiOrganize: return "4"
        case .settings: return nil
        }
    }
}

struct SidebarView: View {
    @Binding var selection: NavigationItem?
    @EnvironmentObject var volumeMonitor: VolumeMonitor

    var body: some View {
        List(selection: $selection) {
            Section {
                HStack(spacing: 8) {
                    Image(systemName: "brain.head.profile")
                        .font(.system(size: 22, weight: .medium))
                        .foregroundStyle(
                            LinearGradient(
                                colors: [.purple, .blue],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .symbolRenderingMode(.hierarchical)

                    VStack(alignment: .leading, spacing: 1) {
                        Text("DriveSyncAI")
                            .font(.system(size: 15, weight: .bold))
                            .foregroundStyle(Color.dsPrimaryText)
                        Text("Intelligent Drive Management")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(Color.dsTertiaryText)
                    }
                }
                .padding(.vertical, 4)
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
            }

            Section("Navigation") {
                ForEach([NavigationItem.dashboard, .sync, .duplicates, .aiOrganize], id: \.self) { item in
                    NavigationLink(value: item) {
                        HStack(spacing: 0) {
                            Label(item.label, systemImage: item.icon)
                            if item == .aiOrganize {
                                Spacer()
                                Text("AI")
                                    .font(.system(size: 9, weight: .bold))
                                    .foregroundStyle(.white)
                                    .padding(.horizontal, 5)
                                    .padding(.vertical, 2)
                                    .background(
                                        LinearGradient(
                                            colors: [.purple, .blue],
                                            startPoint: .leading,
                                            endPoint: .trailing
                                        ),
                                        in: Capsule()
                                    )
                            }
                        }
                    }
                    .tag(item)
                }

                NavigationLink(value: NavigationItem.settings) {
                    Label(NavigationItem.settings.label, systemImage: NavigationItem.settings.icon)
                }
                .tag(NavigationItem.settings)
            }

            Section("Drives") {
                ForEach(volumeMonitor.mountedVolumes) { drive in
                    HStack(spacing: AppTheme.Spacing.small) {
                        Image(systemName: "externaldrive.fill")
                            .font(.system(size: 14))
                            .foregroundStyle(Color.dsSecondaryText)
                            .frame(width: 20, alignment: .center)

                        Circle()
                            .fill(Color.dsSuccess)
                            .frame(width: 8, height: 8)

                        Text(drive.name)
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(Color.dsPrimaryText)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                    .padding(.vertical, 2)
                }
            }
        }
        .listStyle(.sidebar)
        .overlay(keyboardShortcutButtons)
    }

    @ViewBuilder
    private var keyboardShortcutButtons: some View {
        Group {
            Button("") { selection = .dashboard }
                .keyboardShortcut("1", modifiers: .command)
            Button("") { selection = .sync }
                .keyboardShortcut("2", modifiers: .command)
            Button("") { selection = .duplicates }
                .keyboardShortcut("3", modifiers: .command)
            Button("") { selection = .aiOrganize }
                .keyboardShortcut("4", modifiers: .command)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .hidden()
        .allowsHitTesting(false)
    }
}
