// Copyright 2026 Amit Chorasiya. All rights reserved.
// Licensed under the Business Source License 1.1. See LICENSE file.

import SwiftUI

/// Glass-style button with multiple styles and press animation.
struct GlassButton: View {
    enum Style {
        case primary
        case secondary
        case destructive
    }

    let title: String
    let icon: String?
    let style: Style
    let action: () -> Void
    var isDisabled: Bool = false

    @State private var isPressed = false

    init(
        _ title: String,
        icon: String? = nil,
        style: Style = .primary,
        isDisabled: Bool = false,
        action: @escaping () -> Void
    ) {
        self.title = title
        self.icon = icon
        self.style = style
        self.isDisabled = isDisabled
        self.action = action
    }

    private var fillColor: Color {
        switch style {
        case .primary:
            return .dsAction
        case .secondary:
            return .clear
        case .destructive:
            return .dsDestructive
        }
    }

    private var foregroundColor: Color {
        switch style {
        case .primary, .destructive:
            return .white
        case .secondary:
            return .dsPrimaryText
        }
    }

    var body: some View {
        Button(action: {
            guard !isDisabled else { return }
            action()
        }) {
            HStack(spacing: AppTheme.Spacing.small) {
                if let iconName = icon {
                    Image(systemName: iconName)
                        .font(.system(size: 14, weight: .semibold))
                }
                Text(title)
                    .font(.system(size: 14, weight: .semibold))
            }
            .foregroundStyle(isDisabled ? Color.dsTertiaryText : foregroundColor)
            .padding(.horizontal, AppTheme.Spacing.large)
            .padding(.vertical, AppTheme.Spacing.medium)
            .background {
                if style == .secondary {
                    RoundedRectangle(cornerRadius: AppTheme.CornerRadius.medium, style: .continuous)
                        .fill(.ultraThinMaterial)
                        .overlay(
                            RoundedRectangle(cornerRadius: AppTheme.CornerRadius.medium, style: .continuous)
                                .stroke(Color.dsSeparator, lineWidth: 1)
                        )
                } else {
                    RoundedRectangle(cornerRadius: AppTheme.CornerRadius.medium, style: .continuous)
                        .fill(fillColor)
                }
            }
            .scaleEffect(isPressed && !isDisabled ? 0.97 : 1.0)
        }
        .buttonStyle(.plain)
        .disabled(isDisabled)
        .animation(AppTheme.Animation.respectingReducedMotion(AppTheme.Animation.springResponse), value: isPressed)
        .simultaneousGesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in
                    if !isDisabled {
                        isPressed = true
                    }
                }
                .onEnded { _ in
                    isPressed = false
                }
        )
    }
}
