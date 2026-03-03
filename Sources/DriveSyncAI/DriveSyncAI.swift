// Copyright 2026 Amit Chorasiya. All rights reserved.
// Licensed under the Business Source License 1.1. See LICENSE file.

import SwiftUI
import AppKit

@main
struct DriveSyncAI: App {
    @StateObject private var volumeMonitor = VolumeMonitor()
    @StateObject private var achievementService: AchievementService
    @StateObject private var syncService: SyncService
    @StateObject private var duplicateService: DuplicateFinderService
    @StateObject private var profileManager: SyncProfileManager
    @StateObject private var reorganizeService: ReorganizeService
    @StateObject private var llmConfigManager = LLMConfigManager()
    @StateObject private var customRulesService = CustomRulesService()

    init() {
        NSApplication.shared.setActivationPolicy(.regular)

        let safety = SafetyService()
        let sched = AdaptiveScheduler()
        let ach = AchievementService()
        _achievementService = StateObject(wrappedValue: ach)
        _syncService = StateObject(wrappedValue: SyncService(safetyService: safety, scheduler: sched, achievementService: ach))
        _duplicateService = StateObject(wrappedValue: DuplicateFinderService(safetyService: safety, scheduler: sched, achievementService: ach))
        _profileManager = StateObject(wrappedValue: SyncProfileManager(achievementService: ach))
        _reorganizeService = StateObject(wrappedValue: ReorganizeService(safetyService: safety, scheduler: sched))
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(volumeMonitor)
                .environmentObject(achievementService)
                .environmentObject(syncService)
                .environmentObject(duplicateService)
                .environmentObject(profileManager)
                .environmentObject(reorganizeService)
                .environmentObject(llmConfigManager)
                .environmentObject(customRulesService)
                .onAppear {
                    NSApplication.shared.activate(ignoringOtherApps: true)
                    reorganizeService.setConfigManager(llmConfigManager)
                    reorganizeService.setCustomRulesService(customRulesService)
                    // Auto-start built-in AI engine if it was previously set up
                    if llmConfigManager.activeProvider == .llamaCpp
                        && LlamaCppServerManager.shared.isReady {
                        Task { await LlamaCppServerManager.shared.start() }
                    }
                }
        }
        .windowStyle(.titleBar)
        .defaultSize(width: 1100, height: 700)
    }
}
