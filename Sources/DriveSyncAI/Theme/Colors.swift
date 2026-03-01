// Copyright 2026 Amit Chorasiya. All rights reserved.
// Licensed under the Business Source License 1.1. See LICENSE file.

import SwiftUI

/// Color palette for DriveSyncAI using Apple system colors.
/// All colors adapt automatically to light and dark mode.
extension Color {

    // MARK: - Primary / Action

    /// Primary action color - accent blue for CTAs and links
    static let dsPrimary = Color.accentColor

    /// Primary action, explicit fallback when accent is not set
    static let dsPrimaryFallback = Color(nsColor: .systemBlue)

    /// Primary action color - prefers accent, falls back to system blue
    static var dsAction: Color {
        Color.accentColor
    }

    // MARK: - Semantic Colors

    /// Success / create - green
    static let dsSuccess = Color(nsColor: .systemGreen)

    /// Warning / conflict - orange
    static let dsWarning = Color(nsColor: .systemOrange)

    /// Destructive / delete - red
    static let dsDestructive = Color(nsColor: .systemRed)

    // MARK: - Neutral / Secondary

    /// Primary text - adapts to light/dark
    static let dsPrimaryText = Color(nsColor: .labelColor)

    /// Secondary text - for hints and captions
    static let dsSecondaryText = Color(nsColor: .secondaryLabelColor)

    /// Tertiary text - for subtle metadata
    static let dsTertiaryText = Color(nsColor: .tertiaryLabelColor)

    /// Separator - for dividers and borders
    static let dsSeparator = Color(nsColor: .separatorColor)

    /// Fill for secondary content areas
    static let dsSecondaryFill = Color(nsColor: .controlBackgroundColor)

    /// Fill for tertiary/quaternary areas
    static let dsTertiaryFill = Color(nsColor: .quaternaryLabelColor).opacity(0.5)

    /// Background - window or card background
    static let dsBackground = Color(nsColor: .windowBackgroundColor)

    /// Secondary background - for nested surfaces
    static let dsSecondaryBackground = Color(nsColor: .controlBackgroundColor)
}

#if os(macOS)
import AppKit
#endif
