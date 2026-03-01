// Copyright 2026 Amit Chorasiya. All rights reserved.
// Licensed under the Business Source License 1.1. See LICENSE file.

import SwiftUI

#if os(macOS)
import AppKit
#endif

/// Lightweight confetti particle system for celebration effects.
/// Respects reduceAnimations and accessibilityReduceMotion.
struct ConfettiView: View {
    @Binding var isActive: Bool
    @AppStorage("reduceAnimations") private var reduceAnimations = false
    @Environment(\.accessibilityReduceMotion) private var accessibilityReduceMotion

    @State private var particles: [ConfettiParticle] = []
    @State private var startTime: Date?

    private var shouldAnimate: Bool {
        !reduceAnimations && !accessibilityReduceMotion
    }

    private static let confettiColors: [Color] = [
        .dsAction,
        .dsSuccess,
        .dsWarning,
        .dsDestructive,
        Color(red: 0.9, green: 0.4, blue: 0.6),
        Color(red: 0.5, green: 0.4, blue: 0.9),
        Color(red: 0.2, green: 0.7, blue: 0.8)
    ]

    var body: some View {
        ZStack {
            if isActive {
                if shouldAnimate {
                    confettiCanvas
                } else {
                    reducedMotionView
                }
            }
        }
        .onChange(of: isActive) { _, active in
            if active {
                if shouldAnimate {
                    particles = (0..<45).map { _ in ConfettiParticle.random(colors: Self.confettiColors) }
                    startTime = Date()
                    Task {
                        try? await Task.sleep(nanoseconds: 2_200_000_000)
                        await MainActor.run {
                            if isActive {
                                isActive = false
                                particles = []
                                startTime = nil
                            }
                        }
                    }
                } else {
                    Task {
                        try? await Task.sleep(nanoseconds: 1_500_000_000)
                        await MainActor.run {
                            if isActive { isActive = false }
                        }
                    }
                }
            }
        }
    }

    private var confettiCanvas: some View {
        TimelineView(.animation(minimumInterval: 1/60)) { timeline in
            Canvas { context, size in
                guard let start = startTime else { return }
                let elapsed = timeline.date.timeIntervalSince(start)
                guard elapsed >= 0, elapsed <= 2.2 else { return }

                for particle in particles {
                    let progress = min(1, elapsed / 2)
                    let yOffset = CGFloat(progress * Double(particle.speed) * size.height * 1.2)
                    let xOffset = size.width * particle.startX + CGFloat(sin(elapsed * particle.rotationSpeed) * 30)
                    let alpha = elapsed < 1.8 ? 1.0 : max(0, (2 - elapsed) / 0.2)

                    var ctx = context
                    ctx.opacity = alpha
                    ctx.translateBy(x: xOffset, y: yOffset)
                    ctx.rotate(by: .radians(elapsed * particle.rotationSpeed))

                    let rect = CGRect(
                        x: -particle.size / 2,
                        y: -particle.size / 2,
                        width: particle.size,
                        height: particle.size
                    )

                    ctx.fill(
                        confettiPath(for: particle.shape, in: rect),
                        with: .color(particle.color)
                    )
                }
            }
            .allowsHitTesting(false)
        }
    }

    private var reducedMotionView: some View {
        Image(systemName: "checkmark.circle.fill")
            .font(.system(size: 80))
            .foregroundStyle(Color.dsSuccess)
            .symbolRenderingMode(.hierarchical)
    }

    private func confettiPath(for shape: Int, in rect: CGRect) -> Path {
        switch shape {
        case 0:
            return Path(ellipseIn: rect)
        case 1:
            return Path(rect)
        default:
            var path = Path()
            path.move(to: CGPoint(x: rect.midX, y: rect.minY))
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
            path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
            path.closeSubpath()
            return path
        }
    }
}

// MARK: - Particle Model

private struct ConfettiParticle {
    let startX: CGFloat
    let speed: Double
    let color: Color
    let shape: Int
    let size: CGFloat
    let rotationSpeed: Double

    static func random(colors: [Color]) -> ConfettiParticle {
        ConfettiParticle(
            startX: CGFloat.random(in: -0.4...0.4),
            speed: Double.random(in: 0.4...0.9),
            color: colors.randomElement() ?? .dsAction,
            shape: Int.random(in: 0...2),
            size: CGFloat.random(in: 6...14),
            rotationSpeed: Double.random(in: 2...8)
        )
    }
}
