// Copyright 2026 Amit Chorasiya. All rights reserved.
// Licensed under the Business Source License 1.1. See LICENSE file.

import SwiftUI

/// Main app container with sidebar navigation and content area.
struct ContentView: View {
    @State private var selection: NavigationItem? = .dashboard
    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding = false
    @AppStorage("hasAcceptedLicense") private var hasAcceptedLicense = false
    @EnvironmentObject var syncService: SyncService
    @EnvironmentObject var duplicateService: DuplicateFinderService
    @EnvironmentObject var volumeMonitor: VolumeMonitor
    @AppStorage("appearance") private var appearance: String = "system"

    var body: some View {
        ZStack {
            mainContent
            if !hasCompletedOnboarding {
                OnboardingView(navigation: $selection)
                    .environmentObject(volumeMonitor)
                    .transition(.opacity)
                    .zIndex(1)
            }
            if !hasAcceptedLicense {
                LicenseAcceptanceView()
                    .transition(.opacity)
                    .zIndex(2)
            }
        }
    }

    private var mainContent: some View {
        NavigationSplitView {
            SidebarView(selection: $selection)
        } detail: {
            Group {
                switch selection {
                case .dashboard:
                    DashboardView(navigation: $selection)
                case .sync:
                    SyncView()
                case .duplicates:
                    DuplicateFinderView()
                case .aiOrganize:
                    AIOrganizeView()
                case .askMyDocs:
                    AskMyDocsView()
                case .locateMyStuff:
                    LocateMyStuffView()
                case .settings:
                    SettingsView()
                case nil:
                    DashboardView(navigation: $selection)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(Color.dsBackground)
        .safeAreaInset(edge: .bottom) {
            statusBar
        }
        .preferredColorScheme(preferredColorScheme)
        }

    private var preferredColorScheme: ColorScheme? {
        switch appearance {
        case "dark": return .dark
        case "light": return .light
        default: return nil
        }
    }

    private var statusBar: some View {
        HStack(spacing: AppTheme.Spacing.medium) {
            statusText
            Spacer()
        }
        .padding(.horizontal, AppTheme.Spacing.large)
        .padding(.vertical, AppTheme.Spacing.small)
        .background(.ultraThinMaterial)
    }

    @ViewBuilder
    private var statusText: some View {
        let syncState = syncService.state
        let dupState = duplicateService.state

        if syncState == .syncing || syncState == .comparing || syncState == .paused {
            Label(statusForSync(syncState), systemImage: "arrow.triangle.2.circlepath")
                .font(.system(size: 12))
                .foregroundStyle(Color.dsSecondaryText)
        } else if dupState == .scanning {
            Label("Scanning for duplicates…", systemImage: "doc.on.doc")
                .font(.system(size: 12))
                .foregroundStyle(Color.dsSecondaryText)
        } else if dupState == .moving {
            Label("Moving duplicates…", systemImage: "folder.badge.arrow.down")
                .font(.system(size: 12))
                .foregroundStyle(Color.dsSecondaryText)
        } else {
            Label("Ready", systemImage: "checkmark.circle")
                .font(.system(size: 12))
                .foregroundStyle(Color.dsTertiaryText)
        }
    }

    private func statusForSync(_ state: SyncService.SyncState) -> String {
        switch state {
        case .comparing:
            return "Comparing…"
        case .syncing:
            return "Syncing…"
        case .paused:
            return "Paused"
        default:
            return "Ready"
        }
    }
}
