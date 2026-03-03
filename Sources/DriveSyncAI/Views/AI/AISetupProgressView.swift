// Copyright 2026 Amit Chorasiya. All rights reserved.
// Licensed under the Business Source License 1.1. See LICENSE file.

import SwiftUI
import AppKit

/// Shows Ollama/model setup progress after accepting the AI disclaimer.
/// Presents inline within the disclaimer sheet via content swap.
struct AISetupProgressView: View {
    @StateObject private var setupService = OllamaSetupService()
    @EnvironmentObject var configManager: LLMConfigManager

    let onDone: () -> Void
    let onSkip: () -> Void

    @AppStorage("aiEnabled") private var aiEnabled = false

    @State private var adminPassword: String = ""
    @State private var showAdminSheet = false
    @State private var autoDismissTask: Task<Void, Never>? = nil

    private let accentGradient = LinearGradient(
        colors: [Color(red: 0.38, green: 0.22, blue: 0.82), Color(red: 0.25, green: 0.35, blue: 0.88)],
        startPoint: .topLeading, endPoint: .bottomTrailing
    )

    var body: some View {
        ZStack {
            Color.dsBackground.ignoresSafeArea()

            VStack(spacing: 0) {
                headerSection
                    .padding(.bottom, 32)

                stepsSection
                    .padding(.horizontal, 48)
                    .padding(.bottom, 28)

                modelInfoBadge
                    .padding(.horizontal, 48)
                    .padding(.bottom, 28)

                errorBanner
                    .padding(.horizontal, 48)
                    .padding(.bottom, 8)

                footerButtons
                    .padding(.horizontal, 48)
                    .padding(.bottom, 32)
            }
            .frame(maxWidth: 600)
        }
        .onAppear {
            Task { await setupService.run(configManager: configManager) }
        }
        .onChange(of: setupService.phase) { _, newPhase in
            if case .needsAdminPassword = newPhase {
                showAdminSheet = true
            }
            if case .done = newPhase {
                aiEnabled = true
                autoDismissTask = Task {
                    try? await Task.sleep(nanoseconds: 1_500_000_000)
                    onDone()
                }
            }
        }
        .sheet(isPresented: $showAdminSheet) {
            adminPasswordSheet
        }
    }

    // MARK: - Header

    private var headerSection: some View {
        VStack(spacing: 14) {
            ZStack {
                Circle()
                    .fill(accentGradient)
                    .frame(width: 64, height: 64)
                Image(systemName: "brain.head.profile")
                    .font(.system(size: 30, weight: .medium))
                    .foregroundStyle(.white)
                    .symbolRenderingMode(.hierarchical)
            }

            Text("Setting Up AI")
                .font(.system(size: 22, weight: .bold))
                .foregroundStyle(Color.dsPrimaryText)

            Text("DriveSyncAI Buddy will be ready in a moment.")
                .font(.system(size: 13))
                .foregroundStyle(Color.dsSecondaryText)
        }
        .padding(.top, 36)
    }

    // MARK: - Steps

    private var stepsSection: some View {
        VStack(spacing: 0) {
            stepRow(
                number: 1,
                label: "Check Ollama",
                detail: setupService.ollamaInstalled ? "Installed" : "Not found",
                stepPhase: stepStatus(for: .checkingOllama)
            )
            stepConnector
            stepRow(
                number: 2,
                label: "Validate model",
                detail: "Checking \(OllamaSetupService.targetModel)",
                stepPhase: stepStatus(for: .validatingModel)
            )
            stepConnector
            stepRow(
                number: 3,
                label: "Download model",
                detail: setupService.statusLine,
                stepPhase: stepStatus(for: .pullingModel),
                showProgress: isDownloading
            )
        }
    }

    private var stepConnector: some View {
        HStack {
            Rectangle()
                .fill(Color.dsSeparator.opacity(0.4))
                .frame(width: 1.5, height: 20)
                .padding(.leading, 19)
            Spacer()
        }
    }

    private func stepRow(number: Int, label: String, detail: String, stepPhase: StepStatus, showProgress: Bool = false) -> some View {
        HStack(alignment: .top, spacing: 14) {
            stepIndicator(number: number, status: stepPhase)

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    Text(label)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Color.dsPrimaryText)

                    if case .retrying(let n) = setupService.phase, number == 3 {
                        Text("Retrying… (\(n)/\(OllamaSetupService.maxRetries == 3 ? 3 : 3))")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(.orange)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(Color.orange.opacity(0.1), in: RoundedRectangle(cornerRadius: 6))
                    }
                }

                if showProgress {
                    VStack(alignment: .leading, spacing: 4) {
                        GeometryReader { geo in
                            ZStack(alignment: .leading) {
                                RoundedRectangle(cornerRadius: 4)
                                    .fill(Color.dsSecondaryFill)
                                    .frame(height: 6)
                                RoundedRectangle(cornerRadius: 4)
                                    .fill(accentGradient)
                                    .frame(width: geo.size.width * setupService.progress, height: 6)
                                    .animation(.linear(duration: 0.3), value: setupService.progress)
                            }
                        }
                        .frame(height: 6)

                        Text("\(Int(setupService.progress * 100))% complete")
                            .font(.system(size: 11))
                            .foregroundStyle(Color.dsSecondaryText)
                    }
                } else {
                    Text(detail)
                        .font(.system(size: 12))
                        .foregroundStyle(Color.dsTertiaryText)
                        .lineLimit(1)
                }
            }

            Spacer()
        }
        .padding(.vertical, 6)
    }

    private func stepIndicator(number: Int, status: StepStatus) -> some View {
        ZStack {
            Circle()
                .fill(status.bgColor)
                .frame(width: 28, height: 28)

            switch status {
            case .pending:
                Text("\(number)")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Color.dsSecondaryText)
            case .active:
                ProgressView()
                    .controlSize(.small)
                    .tint(.white)
            case .done:
                Image(systemName: "checkmark")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(.white)
            case .error:
                Image(systemName: "xmark")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(.white)
            }
        }
    }

    // MARK: - Model Info Badge

    private var modelInfoBadge: some View {
        HStack(spacing: 12) {
            Image(systemName: "cpu")
                .font(.system(size: 14))
                .foregroundStyle(Color.dsSecondaryText)
            VStack(alignment: .leading, spacing: 2) {
                Text(OllamaSetupService.targetModel)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Color.dsPrimaryText)
                Text("~986 MB  ·  Apache 2.0  ·  Runs 100% on your Mac")
                    .font(.system(size: 11))
                    .foregroundStyle(Color.dsTertiaryText)
            }
            Spacer()
        }
        .padding(12)
        .background(Color.dsSecondaryFill.opacity(0.4), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(Color.dsSeparator.opacity(0.3), lineWidth: 0.5)
        )
    }

    // MARK: - Error Banner

    @ViewBuilder
    private var errorBanner: some View {
        if case .failed(let msg) = setupService.phase, msg != "ollamaNotFound" {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 14))
                    .foregroundStyle(.red)
                Text(msg)
                    .font(.system(size: 12))
                    .foregroundStyle(Color.dsPrimaryText)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer()
            }
            .padding(12)
            .background(Color.red.opacity(0.08), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(Color.red.opacity(0.25), lineWidth: 0.5)
            )
        } else if case .failed(let msg) = setupService.phase, msg == "ollamaNotFound" {
            ollamaNotFoundBanner
        }
    }

    private var ollamaNotFoundBanner: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                Text("Ollama not installed")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Color.dsPrimaryText)
            }
            Text("Ollama is required to run AI locally on your Mac. Download and install it, then tap Retry.")
                .font(.system(size: 12))
                .foregroundStyle(Color.dsSecondaryText)
                .fixedSize(horizontal: false, vertical: true)
            Button {
                NSWorkspace.shared.open(URL(string: "https://ollama.com/download/mac")!)
            } label: {
                HStack(spacing: 5) {
                    Image(systemName: "arrow.down.circle")
                        .font(.system(size: 11, weight: .semibold))
                    Text("Download Ollama")
                        .font(.system(size: 12, weight: .semibold))
                }
                .foregroundStyle(Color.dsAction)
            }
            .buttonStyle(.plain)
        }
        .padding(14)
        .background(Color.orange.opacity(0.07), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(Color.orange.opacity(0.3), lineWidth: 0.5)
        )
    }

    // MARK: - Footer Buttons

    @ViewBuilder
    private var footerButtons: some View {
        switch setupService.phase {
        case .done:
            HStack(spacing: 8) {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                Text("AI setup complete!")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.green)
            }

        case .failed:
            HStack(spacing: 12) {
                Button {
                    Task { await setupService.retry(configManager: configManager) }
                } label: {
                    Label("Retry", systemImage: "arrow.clockwise")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 18)
                        .padding(.vertical, 9)
                        .background(accentGradient, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                }
                .buttonStyle(.plain)

                Button("Skip for now") { onSkip() }
                    .font(.system(size: 13))
                    .foregroundStyle(Color.dsSecondaryText)
                    .buttonStyle(.plain)
            }

        default:
            Button("Skip for now") { onSkip() }
                .font(.system(size: 13))
                .foregroundStyle(Color.dsSecondaryText)
                .buttonStyle(.plain)
        }
    }

    // MARK: - Admin Password Sheet

    private var adminPasswordSheet: some View {
        VStack(spacing: 24) {
            VStack(spacing: 12) {
                Image(systemName: "lock.shield.fill")
                    .font(.system(size: 36))
                    .foregroundStyle(.purple)
                Text("Admin Permission Required")
                    .font(.system(size: 17, weight: .bold))
                    .foregroundStyle(Color.dsPrimaryText)
                Text("Ollama needs administrator access to complete the model download on your system.")
                    .font(.system(size: 13))
                    .foregroundStyle(Color.dsSecondaryText)
                    .multilineTextAlignment(.center)
            }

            SecureField("Enter your Mac admin password", text: $adminPassword)
                .textFieldStyle(.roundedBorder)
                .frame(maxWidth: 340)

            HStack(spacing: 16) {
                Button("Skip") {
                    showAdminSheet = false
                    onSkip()
                }
                .font(.system(size: 13))
                .foregroundStyle(Color.dsSecondaryText)
                .buttonStyle(.plain)

                Button {
                    let pw = adminPassword
                    adminPassword = ""
                    showAdminSheet = false
                    Task { await setupService.retryWithAdminPassword(pw, configManager: configManager) }
                } label: {
                    Text("Authorize & Continue")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 18)
                        .padding(.vertical, 9)
                        .background(accentGradient, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                }
                .buttonStyle(.plain)
                .disabled(adminPassword.isEmpty)
            }
        }
        .padding(32)
        .frame(minWidth: 420)
        .background(Color.dsBackground)
    }

    // MARK: - Helpers

    private var isDownloading: Bool {
        switch setupService.phase {
        case .pullingModel, .retrying: return true
        default: return false
        }
    }

    private func stepStatus(for targetPhase: OllamaSetupService.Phase) -> StepStatus {
        let current = setupService.phase

        switch targetPhase {
        case .checkingOllama:
            switch current {
            case .checkingOllama: return .active
            case .idle: return .pending
            default: return setupService.ollamaInstalled ? .done : .error
            }

        case .validatingModel:
            switch current {
            case .idle, .checkingOllama: return .pending
            case .validatingModel: return .active
            case .failed: return .error
            default: return .done
            }

        case .pullingModel:
            switch current {
            case .idle, .checkingOllama, .validatingModel: return .pending
            case .pullingModel, .retrying: return .active
            case .done: return .done
            case .failed: return .error
            default: return .pending
            }

        default: return .pending
        }
    }

    enum StepStatus {
        case pending, active, done, error

        var bgColor: Color {
            switch self {
            case .pending: return Color.dsSecondaryFill
            case .active: return Color(red: 0.38, green: 0.22, blue: 0.82)
            case .done: return .green
            case .error: return .red
            }
        }
    }
}

