// Copyright 2026 Amit Chorasiya. All rights reserved.
// Licensed under the Business Source License 1.1. See LICENSE file.

import SwiftUI

/// Pulsing radar/sonar animation for scanning states.
/// Respects reduceAnimations and accessibilityReduceMotion.
struct RadarScanView: View {
    @AppStorage("reduceAnimations") private var reduceAnimations = false
    @Environment(\.accessibilityReduceMotion) private var accessibilityReduceMotion

    @State private var ringScale: CGFloat = 0.3
    @State private var ringOpacity: Double = 0.8

    private var shouldAnimate: Bool {
        !reduceAnimations && !accessibilityReduceMotion
    }

    var body: some View {
        ZStack {
            if shouldAnimate {
                radarRings
                centerIcon
            } else {
                reducedMotionView
            }
        }
        .frame(width: 48, height: 48)
        .onAppear {
            if shouldAnimate {
                startPulseAnimation()
            }
        }
    }

    private var radarRings: some View {
        ZStack {
            ForEach(0..<3, id: \.self) { index in
                RadarRingView(
                    baseScale: ringScale,
                    baseOpacity: ringOpacity,
                    delay: Double(index) * 0.35,
                    shouldAnimate: shouldAnimate
                )
            }
        }
    }

    private var centerIcon: some View {
        Image(systemName: "magnifyingglass")
            .font(.system(size: 20, weight: .medium))
            .foregroundStyle(Color.dsAction)
            .symbolRenderingMode(.hierarchical)
    }

    private var reducedMotionView: some View {
        ZStack {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 20, weight: .medium))
                .foregroundStyle(Color.dsAction)
                .symbolRenderingMode(.hierarchical)
            ProgressView()
                .scaleEffect(0.6)
                .offset(y: 20)
        }
    }

    private func startPulseAnimation() {
        withAnimation(
            AppTheme.Animation.respectingReducedMotion(
                .easeOut(duration: 1.2).repeatForever(autoreverses: false)
            )
        ) {
            ringScale = 1.2
            ringOpacity = 0
        }
    }
}

// MARK: - Ring View

private struct RadarRingView: View {
    let baseScale: CGFloat
    let baseOpacity: Double
    let delay: Double
    let shouldAnimate: Bool

    @State private var scale: CGFloat = 0.3
    @State private var opacity: Double = 0.8

    var body: some View {
        Circle()
            .stroke(Color.dsAction.opacity(0.5), lineWidth: 2)
            .scaleEffect(scale)
            .opacity(opacity)
            .onAppear {
                if shouldAnimate {
                    withAnimation(
                        AppTheme.Animation.respectingReducedMotion(
                            .easeOut(duration: 1.2)
                                .repeatForever(autoreverses: false)
                                .delay(delay)
                        )
                    ) {
                        scale = 1.2
                        opacity = 0
                    }
                }
            }
    }
}
