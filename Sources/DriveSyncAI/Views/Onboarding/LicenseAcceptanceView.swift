// Copyright 2026 Amit Chorasiya. All rights reserved.
// Licensed under the Business Source License 1.1. See LICENSE file.

import SwiftUI
import AppKit

struct LicenseAcceptanceView: View {
    @AppStorage("hasAcceptedLicense") private var hasAcceptedLicense = false
    @State private var hasAgreed = false
    @State private var scrolledToBottom = false

    var body: some View {
        ZStack {
            Color.dsBackground.ignoresSafeArea()

            VStack(spacing: 0) {
                header
                licenseContent
                agreementFooter
            }
            .frame(maxWidth: 700)
            .padding(.vertical, AppTheme.Spacing.xl)
        }
    }

    // MARK: - Header

    private var header: some View {
        VStack(spacing: AppTheme.Spacing.medium) {
            Image(systemName: "doc.text.fill")
                .font(.system(size: 44))
                .foregroundStyle(Color.dsAction)
                .symbolRenderingMode(.hierarchical)

            Text("License Agreement")
                .font(.system(size: 24, weight: .bold))
                .foregroundStyle(Color.dsPrimaryText)

            Text("Please read and accept the following terms before using DriveSyncAI.")
                .font(.system(size: 14))
                .foregroundStyle(Color.dsSecondaryText)
                .multilineTextAlignment(.center)
        }
        .padding(.bottom, AppTheme.Spacing.large)
    }

    // MARK: - License Content

    private var licenseContent: some View {
        GlassCard(padding: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: AppTheme.Spacing.large) {
                    licenseSummarySection
                    Divider()
                    disclaimerSection
                    Divider()
                    dataRiskSection

                    GeometryReader { geo in
                        Color.clear
                            .preference(key: ScrollBottomKey.self, value: geo.frame(in: .named("scroll")).maxY)
                    }
                    .frame(height: 1)
                }
                .padding(AppTheme.Spacing.large)
            }
            .coordinateSpace(name: "scroll")
            .onPreferenceChange(ScrollBottomKey.self) { maxY in
                if maxY < 500 {
                    scrolledToBottom = true
                }
            }
            .frame(maxHeight: 380)
        }
        .padding(.horizontal, AppTheme.Spacing.xl)
    }

    private var licenseSummarySection: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.medium) {
            sectionHeader("Business Source License 1.1")

            bulletPoint("This software is copyright \u{00A9} 2026 Amit Chorasiya. All rights reserved.")
            bulletPoint("You may use this software for personal, educational, evaluation, development, and testing purposes at no cost.")
            bulletPoint("Production use or commercial distribution requires a separate commercial license from the copyright holder.")
            bulletPoint("You may not sell, sublicense, or redistribute this software for commercial purposes without prior written permission.")
            bulletPoint("The \"DriveSyncAI\" name and logo are trademarks of Amit Chorasiya and may not be used in derivative works without permission.")
            bulletPoint("This software includes optional AI-powered features that use large language models. AI suggestions may be inaccurate and should always be reviewed before execution.")
            bulletPoint("When using cloud AI providers, file metadata (not contents) may be sent to third-party services. Local processing via Ollama keeps all data on your device.")
            bulletPoint("On February 28, 2030, this software will become available under the Apache License, Version 2.0.")
        }
    }

    private var disclaimerSection: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.medium) {
            sectionHeader("Disclaimer of Warranty")

            Text("""
                TO THE MAXIMUM EXTENT PERMITTED BY APPLICABLE LAW, THIS SOFTWARE IS PROVIDED \
                "AS IS" WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT \
                LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE, \
                AND NON-INFRINGEMENT. THE ENTIRE RISK AS TO THE QUALITY AND PERFORMANCE OF THE \
                SOFTWARE IS WITH YOU. SHOULD THE SOFTWARE PROVE DEFECTIVE, YOU ASSUME THE COST \
                OF ALL NECESSARY SERVICING, REPAIR, OR CORRECTION.
                """)
                .font(.system(size: 12))
                .foregroundStyle(Color.dsSecondaryText)
                .fixedSize(horizontal: false, vertical: true)

            Text("""
                IN NO EVENT SHALL THE COPYRIGHT HOLDER, CONTRIBUTORS, OR AFFILIATES BE LIABLE \
                FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL \
                DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR \
                SERVICES; LOSS OF USE, DATA, OR PROFITS; LOSS OF GOODWILL; BUSINESS \
                INTERRUPTION; OR ANY OTHER COMMERCIAL DAMAGES OR LOSSES) HOWEVER CAUSED AND ON \
                ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT \
                (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS \
                SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGES.
                """)
                .font(.system(size: 12))
                .foregroundStyle(Color.dsSecondaryText)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var dataRiskSection: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.medium) {
            sectionHeader("Assumption of Risk")

            Text("""
                YOU ACKNOWLEDGE THAT THIS SOFTWARE PERFORMS FILE SYNCHRONIZATION, DUPLICATE \
                MANAGEMENT, AND AI-POWERED FILE ORGANIZATION OPERATIONS THAT MAY MODIFY, MOVE, \
                RENAME, OR DELETE FILES ON YOUR STORAGE DEVICES. BY ACCEPTING THIS AGREEMENT, \
                YOU EXPRESSLY ASSUME ALL RISK AND RESPONSIBILITY FOR ANY DATA LOSS, DATA \
                CORRUPTION, FILE MISPLACEMENT, INCORRECT RENAMING, HARDWARE DAMAGE, OR OTHER \
                HARM THAT MAY RESULT FROM THE USE OF THIS SOFTWARE, INCLUDING ACTIONS TAKEN \
                BASED ON AI-GENERATED SUGGESTIONS. THE COPYRIGHT HOLDER SHALL NOT BE HELD \
                LIABLE FOR ANY SUCH LOSS OR DAMAGE UNDER ANY CIRCUMSTANCES WHATSOEVER.
                """)
                .font(.system(size: 12))
                .foregroundStyle(Color.dsSecondaryText)
                .fixedSize(horizontal: false, vertical: true)

            Text("""
                IT IS YOUR SOLE RESPONSIBILITY TO MAINTAIN ADEQUATE BACKUPS OF YOUR DATA \
                BEFORE USING THIS SOFTWARE. YOU ARE STRONGLY ADVISED TO USE THE DRY-RUN MODE \
                TO PREVIEW ALL OPERATIONS BEFORE EXECUTING THEM.
                """)
                .font(.system(size: 12))
                .foregroundStyle(Color.dsSecondaryText)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: - Agreement Footer

    private var agreementFooter: some View {
        VStack(spacing: AppTheme.Spacing.large) {
            Toggle(isOn: $hasAgreed) {
                Text("I have read and accept the Business Source License 1.1, Disclaimer of Warranty, Assumption of Risk, and AI Features Disclaimer")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Color.dsPrimaryText)
            }
            .toggleStyle(.checkbox)
            .padding(.horizontal, AppTheme.Spacing.xl)

            HStack(spacing: AppTheme.Spacing.large) {
                GlassButton("Decline", icon: "xmark", style: .secondary) {
                    NSApplication.shared.terminate(nil)
                }

                GlassButton("Accept", icon: "checkmark", style: .primary, isDisabled: !hasAgreed) {
                    withAnimation(AppTheme.Animation.smooth) {
                        hasAcceptedLicense = true
                    }
                }
            }
        }
        .padding(.top, AppTheme.Spacing.large)
    }

    // MARK: - Helpers

    private func sectionHeader(_ title: String) -> some View {
        Text(title)
            .font(.system(size: 15, weight: .semibold))
            .foregroundStyle(Color.dsPrimaryText)
    }

    private func bulletPoint(_ text: String) -> some View {
        HStack(alignment: .top, spacing: AppTheme.Spacing.small) {
            Text("\u{2022}")
                .font(.system(size: 13))
                .foregroundStyle(Color.dsAction)
                .frame(width: 12)
            Text(text)
                .font(.system(size: 13))
                .foregroundStyle(Color.dsSecondaryText)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

private struct ScrollBottomKey: PreferenceKey {
    static var defaultValue: CGFloat = .infinity
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = min(value, nextValue())
    }
}
