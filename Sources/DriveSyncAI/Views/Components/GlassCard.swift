// Copyright 2026 Amit Chorasiya. All rights reserved.
// Licensed under the Business Source License 1.1. See LICENSE file.

import SwiftUI

/// A translucent card component with ultraThinMaterial background.
/// A translucent card with ultraThinMaterial background for a premium glass aesthetic.
struct GlassCard<Content: View>: View {
    private let content: Content
    private let padding: CGFloat?

    init(
        padding: CGFloat? = AppTheme.Spacing.large,
        @ViewBuilder content: () -> Content
    ) {
        self.padding = padding
        self.content = content()
    }

    var body: some View {
        content
            .padding(padding ?? 0)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: AppTheme.CornerRadius.large, style: .continuous))
            .clipShape(RoundedRectangle(cornerRadius: AppTheme.CornerRadius.large, style: .continuous))
            .shadow(
                color: AppTheme.Shadow.subtle.color,
                radius: AppTheme.Shadow.subtle.radius,
                x: AppTheme.Shadow.subtle.x,
                y: AppTheme.Shadow.subtle.y
            )
    }
}
