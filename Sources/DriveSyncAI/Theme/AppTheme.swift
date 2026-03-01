// Copyright 2026 Amit Chorasiya. All rights reserved.
// Licensed under the Business Source License 1.1. See LICENSE file.

import SwiftUI

/// Centralized theme configuration for DriveSyncAI.
/// Defines spacing, corner radii, shadow presets, and animation curves for a premium, clean aesthetic.
enum AppTheme {

    // MARK: - Spacing

    enum Spacing {
        static let small: CGFloat = 4
        static let medium: CGFloat = 8
        static let large: CGFloat = 16
        static let xl: CGFloat = 24
    }

    // MARK: - Corner Radius

    enum CornerRadius {
        static let small: CGFloat = 6
        static let medium: CGFloat = 10
        static let large: CGFloat = 12
        static let xl: CGFloat = 16
    }

    // MARK: - Shadow Styles

    enum Shadow {
        static let subtle = ShadowStyle(
            color: .black.opacity(0.08),
            radius: 8,
            x: 0,
            y: 2
        )

        static let medium = ShadowStyle(
            color: .black.opacity(0.12),
            radius: 12,
            x: 0,
            y: 4
        )

        static let strong = ShadowStyle(
            color: .black.opacity(0.16),
            radius: 16,
            x: 0,
            y: 6
        )

        struct ShadowStyle {
            let color: Color
            let radius: CGFloat
            let x: CGFloat
            let y: CGFloat
        }
    }

    // MARK: - Animation Presets

    enum Animation {
        /// Spring with responsive feel - for button presses and interactive elements
        static let springResponse = SwiftUI.Animation.spring(response: 0.35, dampingFraction: 0.7)

        /// Spring with snappy feel - for quick feedback
        static let springSnappy = SwiftUI.Animation.spring(response: 0.3, dampingFraction: 0.8)

        /// Smooth ease - for progress and fills
        static let smooth = SwiftUI.Animation.easeInOut(duration: 0.4)

        /// Quick fade
        static let quickFade = SwiftUI.Animation.easeOut(duration: 0.2)

        /// Check if reduced motion is preferred for accessibility
        static var prefersReducedMotion: Bool {
            #if os(macOS)
            NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
            #else
            UIAccessibility.isReduceMotionEnabled
            #endif
        }

        /// Returns appropriate animation respecting reduced motion preference
        static func respectingReducedMotion(_ animation: SwiftUI.Animation) -> SwiftUI.Animation {
            prefersReducedMotion ? .linear(duration: 0) : animation
        }
    }
}

#if os(macOS)
import AppKit
#else
import UIKit
#endif
