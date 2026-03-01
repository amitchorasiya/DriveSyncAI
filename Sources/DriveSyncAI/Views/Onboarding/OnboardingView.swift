// Copyright 2026 Amit Chorasiya. All rights reserved.
// Licensed under the Business Source License 1.1. See LICENSE file.

import SwiftUI

/// Fullscreen 3-step onboarding overlay shown on first launch.
struct OnboardingView: View {
    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding = false
    @AppStorage("reduceAnimations") private var reduceAnimations = false
    @Environment(\.accessibilityReduceMotion) private var accessibilityReduceMotion
    @EnvironmentObject var volumeMonitor: VolumeMonitor
    @Binding var navigation: NavigationItem?

    @State private var currentStep = 0
    @State private var appearedIndices: Set<Int> = []

    private var shouldAnimate: Bool {
        !reduceAnimations && !accessibilityReduceMotion
    }

    private let totalSteps = 3

    var body: some View {
        ZStack {
            Color.dsBackground
                .ignoresSafeArea()

            VStack(spacing: 0) {
                tabContent

                progressDots
                Spacer().frame(height: AppTheme.Spacing.xl)
            }
        }
        .onAppear {
            if shouldAnimate {
                withAnimation(AppTheme.Animation.quickFade) {
                    _ = appearedIndices.insert(0)
                }
            } else {
                _ = appearedIndices.insert(0)
            }
        }
        .gesture(
            DragGesture()
                .onEnded { value in
                    guard shouldAnimate, abs(value.translation.width) > 30 else { return }
                    if value.translation.width < 0, currentStep < totalSteps - 1 {
                        withAnimation(AppTheme.Animation.springResponse) { currentStep += 1 }
                    } else if value.translation.width > 0, currentStep > 0 {
                        withAnimation(AppTheme.Animation.springResponse) { currentStep -= 1 }
                    }
                }
        )
        .onChange(of: currentStep) { _, newStep in
            if shouldAnimate {
                withAnimation(AppTheme.Animation.quickFade) {
                    _ = appearedIndices.insert(newStep)
                }
            } else {
                _ = appearedIndices.insert(newStep)
            }
        }
    }

    private var tabContent: some View {
        GeometryReader { geo in
            HStack(spacing: 0) {
                step1View
                    .frame(width: geo.size.width, height: geo.size.height)
                step2View
                    .frame(width: geo.size.width, height: geo.size.height)
                step3View
                    .frame(width: geo.size.width, height: geo.size.height)
            }
            .offset(x: -CGFloat(currentStep) * geo.size.width)
            .animation(shouldAnimate ? AppTheme.Animation.springResponse : nil, value: currentStep)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .clipped()
    }

    // MARK: - Step 1: Welcome

    private var step1View: some View {
        VStack(spacing: AppTheme.Spacing.xl) {
            Spacer()

            ZStack {
                Image(systemName: "brain.head.profile")
                    .font(.system(size: 72, weight: .thin))
                    .foregroundStyle(
                        LinearGradient(
                            colors: [Color.purple, Color.blue],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .symbolRenderingMode(.hierarchical)

                Image(systemName: "sparkles")
                    .font(.system(size: 20, weight: .bold))
                    .foregroundStyle(Color.purple.opacity(0.8))
                    .offset(x: 34, y: -28)
            }
            .opacity(appearedIndices.contains(0) ? 1 : 0)
            .offset(y: appearedIndices.contains(0) ? 0 : 20)
            .animation(shouldAnimate ? AppTheme.Animation.smooth.delay(0) : nil, value: appearedIndices.contains(0))

            VStack(spacing: AppTheme.Spacing.medium) {
                Text("Welcome to DriveSyncAI")
                    .font(.system(size: 28, weight: .bold))
                    .foregroundStyle(Color.dsPrimaryText)
                    .opacity(appearedIndices.contains(0) ? 1 : 0)
                    .animation(shouldAnimate ? AppTheme.Animation.smooth.delay(0.05) : nil, value: appearedIndices.contains(0))

                Text("AI-powered drive management. Sync, deduplicate, and intelligently organize your files with confidence.")
                    .font(.system(size: 16))
                    .foregroundStyle(Color.dsSecondaryText)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, AppTheme.Spacing.xl)
                    .frame(maxWidth: 400)
                    .opacity(appearedIndices.contains(0) ? 1 : 0)
                    .animation(shouldAnimate ? AppTheme.Animation.smooth.delay(0.1) : nil, value: appearedIndices.contains(0))
            }

            Spacer().frame(height: AppTheme.Spacing.xl)

            GlassButton("Get Started", icon: "arrow.right", style: .primary) {
                advanceStep()
            }
            .opacity(appearedIndices.contains(0) ? 1 : 0)
            .animation(shouldAnimate ? AppTheme.Animation.smooth.delay(0.15) : nil, value: appearedIndices.contains(0))

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(AppTheme.Spacing.xl)
    }

    // MARK: - Step 2: Connect Drives

    private var step2View: some View {
        VStack(spacing: AppTheme.Spacing.xl) {
            Spacer()

            HStack(spacing: AppTheme.Spacing.large) {
                Image(systemName: "externaldrive.fill")
                    .font(.system(size: 48))
                    .foregroundStyle(Color.dsAction)
                    .symbolRenderingMode(.hierarchical)
                Image(systemName: "arrow.triangle.2.circlepath")
                    .font(.system(size: 24))
                    .foregroundStyle(Color.dsSecondaryText)
                Image(systemName: "externaldrive.fill")
                    .font(.system(size: 48))
                    .foregroundStyle(Color.dsAction)
                    .symbolRenderingMode(.hierarchical)
            }
            .opacity(appearedIndices.contains(1) ? 1 : 0)
            .animation(shouldAnimate ? AppTheme.Animation.smooth.delay(0) : nil, value: appearedIndices.contains(1))

            Text("Connect Drives")
                .font(.system(size: 24, weight: .semibold))
                .foregroundStyle(Color.dsPrimaryText)
                .opacity(appearedIndices.contains(1) ? 1 : 0)
                .animation(shouldAnimate ? AppTheme.Animation.smooth.delay(0.05) : nil, value: appearedIndices.contains(1))

            if volumeMonitor.mountedVolumes.isEmpty {
                Text("Connect your external drives to get started")
                    .font(.system(size: 15))
                    .foregroundStyle(Color.dsSecondaryText)
                    .padding(.vertical, AppTheme.Spacing.medium)
                    .opacity(appearedIndices.contains(1) ? 1 : 0)
                    .animation(shouldAnimate ? AppTheme.Animation.smooth.delay(0.1) : nil, value: appearedIndices.contains(1))
            } else {
                VStack(spacing: AppTheme.Spacing.small) {
                    ForEach(Array(volumeMonitor.mountedVolumes.prefix(5).enumerated()), id: \.element.id) { index, drive in
                        HStack(spacing: AppTheme.Spacing.medium) {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.system(size: 20))
                                .foregroundStyle(Color.dsSuccess)
                            Text(drive.name)
                                .font(.system(size: 14, weight: .medium))
                                .foregroundStyle(Color.dsPrimaryText)
                                .lineLimit(1)
                                .truncationMode(.middle)
                            Spacer()
                        }
                        .padding(.horizontal, AppTheme.Spacing.large)
                        .padding(.vertical, AppTheme.Spacing.medium)
                        .background(Color.dsSecondaryFill, in: RoundedRectangle(cornerRadius: AppTheme.CornerRadius.medium, style: .continuous))
                        .opacity(appearedIndices.contains(1) ? 1 : 0)
                        .animation(shouldAnimate ? AppTheme.Animation.smooth.delay(0.1 + Double(index) * 0.05) : nil, value: appearedIndices.contains(1))
                    }
                }
                .frame(maxWidth: 320)
            }

            Spacer().frame(height: AppTheme.Spacing.xl)

            GlassButton("Continue", icon: "arrow.right", style: .primary) {
                advanceStep()
            }
            .opacity(appearedIndices.contains(1) ? 1 : 0)
            .animation(shouldAnimate ? AppTheme.Animation.smooth.delay(0.2) : nil, value: appearedIndices.contains(1))

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(AppTheme.Spacing.xl)
    }

    // MARK: - Step 3: Quick Start

    private var step3View: some View {
        VStack(spacing: AppTheme.Spacing.xl) {
            Spacer()

            Text("Quick Start")
                .font(.system(size: 24, weight: .semibold))
                .foregroundStyle(Color.dsPrimaryText)
                .opacity(appearedIndices.contains(2) ? 1 : 0)
                .animation(shouldAnimate ? AppTheme.Animation.smooth.delay(0) : nil, value: appearedIndices.contains(2))

            HStack(spacing: AppTheme.Spacing.large) {
                quickStartCard(
                    icon: "arrow.triangle.2.circlepath",
                    title: "Sync Now",
                    description: "Keep two drives in perfect sync.",
                    delay: 0.05
                ) {
                    navigation = .sync
                    finishOnboarding()
                }

                quickStartCard(
                    icon: "doc.on.doc",
                    title: "Find Duplicates",
                    description: "Reclaim wasted space fast.",
                    delay: 0.1
                ) {
                    navigation = .duplicates
                    finishOnboarding()
                }

                quickStartCard(
                    icon: "brain.head.profile",
                    title: "AI Organize",
                    description: "Let AI tidy your files.",
                    delay: 0.15
                ) {
                    navigation = .aiOrganize
                    finishOnboarding()
                }
            }
            .frame(maxWidth: 720)

            Spacer().frame(height: AppTheme.Spacing.large)

            Button {
                finishOnboarding()
            } label: {
                Text("Skip and Explore")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(Color.dsSecondaryText)
            }
            .buttonStyle(.plain)
            .opacity(appearedIndices.contains(2) ? 1 : 0)
            .animation(shouldAnimate ? AppTheme.Animation.smooth.delay(0.2) : nil, value: appearedIndices.contains(2))

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(AppTheme.Spacing.xl)
    }

    private func quickStartCard(
        icon: String,
        title: String,
        description: String,
        delay: Double,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            VStack(spacing: AppTheme.Spacing.large) {
                Image(systemName: icon)
                    .font(.system(size: 40))
                    .foregroundStyle(Color.dsAction)
                    .symbolRenderingMode(.hierarchical)
                VStack(spacing: AppTheme.Spacing.small) {
                    Text(title)
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(Color.dsPrimaryText)
                    Text(description)
                        .font(.system(size: 13))
                        .foregroundStyle(Color.dsSecondaryText)
                        .multilineTextAlignment(.center)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(AppTheme.Spacing.xl)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: AppTheme.CornerRadius.large, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: AppTheme.CornerRadius.large, style: .continuous)
                    .stroke(Color.dsSeparator.opacity(0.5), lineWidth: 1)
            )
            .shadow(
                color: AppTheme.Shadow.subtle.color,
                radius: AppTheme.Shadow.subtle.radius,
                x: AppTheme.Shadow.subtle.x,
                y: AppTheme.Shadow.subtle.y
            )
        }
        .buttonStyle(.plain)
        .opacity(appearedIndices.contains(2) ? 1 : 0)
        .animation(shouldAnimate ? AppTheme.Animation.smooth.delay(delay) : nil, value: appearedIndices.contains(2))
    }

    private var progressDots: some View {
        HStack(spacing: AppTheme.Spacing.small) {
            ForEach(0..<totalSteps, id: \.self) { index in
                Circle()
                    .fill(index == currentStep ? Color.dsAction : Color.dsSeparator)
                    .frame(width: index == currentStep ? 10 : 8, height: index == currentStep ? 10 : 8)
                    .animation(shouldAnimate ? AppTheme.Animation.springResponse : nil, value: currentStep)
            }
        }
        .padding(.bottom, AppTheme.Spacing.medium)
    }

    private func advanceStep() {
        if currentStep < totalSteps - 1 {
            withAnimation(shouldAnimate ? AppTheme.Animation.springResponse : nil) {
                currentStep += 1
            }
        } else {
            finishOnboarding()
        }
    }

    private func finishOnboarding() {
        hasCompletedOnboarding = true
    }
}
