// Copyright 2026 Amit Chorasiya. All rights reserved.
// Licensed under the Business Source License 1.1. See LICENSE file.

import SwiftUI

/// Compact action type indicator badge for sync lists.
/// Uses colored circles with icons: create (+), update (arrow), delete (-), conflict (!), skip (=).
struct ActionBadgeView: View {
    let actionType: SyncActionType

    private var iconName: String {
        switch actionType {
        case .create: return "plus"
        case .update: return "arrow.triangle.2.circlepath"
        case .delete: return "minus"
        case .conflict: return "exclamationmark.triangle.fill"
        case .skip: return "equal"
        }
    }

    private var iconColor: Color {
        switch actionType {
        case .create: return .dsSuccess
        case .update: return .dsAction
        case .delete: return .dsDestructive
        case .conflict: return .dsWarning
        case .skip: return .dsSecondaryText
        }
    }

    private var backgroundColor: Color {
        iconColor.opacity(0.2)
    }

    var body: some View {
        Image(systemName: iconName)
            .font(.system(size: 9, weight: .bold))
            .foregroundStyle(iconColor)
            .frame(width: 20, height: 20)
            .background(backgroundColor, in: Circle())
    }
}
