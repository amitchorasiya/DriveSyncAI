// Copyright 2026 Amit Chorasiya. All rights reserved.
// Licensed under the Business Source License 1.1. See LICENSE file.

import SwiftUI

struct QuickActionsView: View {
    @Binding var navigation: NavigationItem?
    var onSyncNow: () -> Void
    var onFindDuplicates: () -> Void
    var onCompareOnly: () -> Void

    var body: some View {
        GlassCard {
            HStack(spacing: AppTheme.Spacing.large) {
                GlassButton("Sync Now", icon: "arrow.triangle.2.circlepath") {
                    navigation = .sync
                    onSyncNow()
                }

                GlassButton("Find Duplicates", icon: "doc.on.doc") {
                    navigation = .duplicates
                    onFindDuplicates()
                }

                GlassButton("AI Organize", icon: "brain.head.profile") {
                    navigation = .aiOrganize
                }

                GlassButton("Compare Only", icon: "arrow.left.arrow.right", style: .secondary) {
                    navigation = .sync
                    onCompareOnly()
                }
            }
        }
    }
}
