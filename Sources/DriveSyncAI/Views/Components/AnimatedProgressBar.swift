// Copyright 2026 Amit Chorasiya. All rights reserved.
// Licensed under the Business Source License 1.1. See LICENSE file.

import SwiftUI

/// Animated progress bar with gradient fill, percentage text, and optional labels.
/// Supports indeterminate mode with pulsing animation.
struct AnimatedProgressBar: View {
    let value: Double
    let label: String?
    let detailText: String?
    let isIndeterminate: Bool

    @State private var indeterminatePhase: CGFloat = 0

    init(
        value: Double = 0,
        label: String? = nil,
        detailText: String? = nil,
        isIndeterminate: Bool = false
    ) {
        self.value = value
        self.label = label
        self.detailText = detailText
        self.isIndeterminate = isIndeterminate
    }

    private var displayValue: Double {
        guard !isIndeterminate else { return 0.6 }
        return min(max(value, 0), 1)
    }

    private var percentageText: String {
        guard !isIndeterminate else { return "" }
        return "\(Int(displayValue * 100))%"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.small) {
            if let label = label {
                HStack {
                    Text(label)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(Color.dsPrimaryText)
                    Spacer()
                    if !isIndeterminate, !percentageText.isEmpty {
                        Text(percentageText)
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(Color.dsSecondaryText)
                    }
                }
            }

            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: AppTheme.CornerRadius.small, style: .continuous)
                        .fill(Color.dsSecondaryFill)

                    RoundedRectangle(cornerRadius: AppTheme.CornerRadius.small, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [
                                    Color.dsAction,
                                    Color.dsAction.opacity(0.8)
                                ],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .frame(width: geometry.size.width * (isIndeterminate ? indeterminatePhase : displayValue))
                }
            }
            .frame(height: 8)

            if let detail = detailText {
                Text(detail)
                    .font(.system(size: 11, weight: .regular))
                    .foregroundStyle(Color.dsTertiaryText)
            }
        }
        .animation(AppTheme.Animation.respectingReducedMotion(AppTheme.Animation.smooth), value: value)
        .onAppear {
            guard isIndeterminate else { return }
            withAnimation(
                AppTheme.Animation.respectingReducedMotion(
                    .easeInOut(duration: 1.2).repeatForever(autoreverses: true)
                )
            ) {
                indeterminatePhase = 0.85
            }
        }
    }
}
