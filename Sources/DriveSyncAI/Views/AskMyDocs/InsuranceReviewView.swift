// Copyright 2026 Amit Chorasiya. All rights reserved.
// Licensed under the Business Source License 1.1. See LICENSE file.

import SwiftUI

struct InsuranceReviewView: View {
    @ObservedObject var insightService: DocumentInsightService
    @ObservedObject var chatService: AskMyDocsChatService
    var configManager: LLMConfigManager
    
    @State private var isReviewing = false
    
    var body: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.large) {
            piiProtectionBanner
            sourceDocumentsStatus
            runReviewButton
            
            if let result = chatService.lastInsuranceReviewResult {
                findingsDashboard(result)
            }
        }
    }
    
    private var piiProtectionBanner: some View {
        HStack(spacing: 8) {
            Image(systemName: "shield.checkered")
                .foregroundStyle(.green)
            VStack(alignment: .leading, spacing: 1) {
                Text("PII/PHI Protection: Always ON")
                    .font(.caption.bold())
                    .foregroundStyle(Color.dsPrimaryText)
                Text("Names, SSNs, policy numbers, and other sensitive data are automatically redacted before being sent to the AI model.")
                    .font(.caption2)
                    .foregroundStyle(Color.dsSecondaryText)
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.green.opacity(0.06))
        .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.green.opacity(0.2), lineWidth: 1))
        .cornerRadius(6)
    }
    
    private var sourceDocumentsStatus: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Source Documents (Insurance Policies)")
                .font(.subheadline.bold())
            
            if insightService.corpus.successfulDocuments.isEmpty {
                HStack {
                    Image(systemName: "exclamationmark.triangle")
                        .foregroundStyle(.orange)
                    Text("No source documents scanned. Add folders with your insurance policies.")
                        .font(.caption)
                        .foregroundStyle(Color.dsSecondaryText)
                }
                .padding(8)
                .background(Color.orange.opacity(0.05))
                .cornerRadius(6)
            } else {
                HStack {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                    Text("\(insightService.corpus.supportedFileCount) documents ready")
                        .font(.caption)
                }
            }
        }
    }
    
    private var runReviewButton: some View {
        Button {
            Task {
                isReviewing = true
                await chatService.runInsuranceReview(
                    corpus: insightService.corpus,
                    configManager: configManager
                )
                isReviewing = false
            }
        } label: {
            HStack {
                if isReviewing {
                    ProgressView().scaleEffect(0.7)
                    Text("Reviewing...")
                } else {
                    Image(systemName: "doc.text.magnifyingglass")
                    Text("Run Insurance Review")
                }
            }
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.borderedProminent)
        .controlSize(.large)
        .disabled(insightService.corpus.successfulDocuments.isEmpty || isReviewing)
    }
    
    private func findingsDashboard(_ result: InsuranceReviewResult) -> some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.large) {
            Divider()
            
            HStack(spacing: AppTheme.Spacing.xl) {
                if let provider = result.provider {
                    summaryBadge(title: "Provider", value: provider, icon: "building.2.fill", color: .blue)
                }
                if let policyNum = result.policyNumber {
                    summaryBadge(title: "Policy #", value: policyNum, icon: "number.circle.fill", color: .green)
                }
                Spacer()
            }
            
            if !result.coverages.isEmpty {
                coveragesSection(result.coverages)
            }
            
            if !result.gaps.isEmpty {
                gapsSection(result.gaps)
            }
        }
    }
    
    private func summaryBadge(title: String, value: String, icon: String, color: Color) -> some View {
        VStack(spacing: 4) {
            Image(systemName: icon)
                .font(.title)
                .foregroundStyle(color)
            Text(value)
                .font(.title2.bold())
                .foregroundStyle(Color.dsPrimaryText)
            Text(title)
                .font(.caption)
                .foregroundStyle(Color.dsSecondaryText)
        }
        .padding(16)
        .background(Color.dsSecondaryBackground)
        .cornerRadius(12)
    }
    
    private func coveragesSection(_ coverages: [InsuranceCoverage]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Coverages")
                .font(.headline)
            
            ForEach(coverages) { coverage in
                HStack(alignment: .top) {
                    VStack(alignment: .leading) {
                        Text(coverage.type)
                            .font(.subheadline.bold())
                        if let notes = coverage.notes {
                            Text(notes)
                                .font(.caption)
                                .foregroundStyle(Color.dsSecondaryText)
                        }
                    }
                    Spacer()
                    VStack(alignment: .trailing) {
                        Text(coverage.limit)
                            .font(.subheadline.monospacedDigit())
                        if let ded = coverage.deductible {
                            Text("Ded: \(ded)")
                                .font(.caption2)
                                .foregroundStyle(Color.dsTertiaryText)
                        }
                    }
                }
                .padding(8)
                .background(Color.dsSecondaryBackground.opacity(0.5))
                .cornerRadius(6)
            }
        }
    }
    
    private func gapsSection(_ gaps: [String]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                Text("Coverage Gaps")
                    .font(.headline)
                    .foregroundStyle(.orange)
            }
            
            ForEach(gaps, id: \.self) { gap in
                HStack(alignment: .top) {
                    Image(systemName: "circle.fill")
                        .font(.system(size: 6))
                        .padding(.top, 6)
                    Text(gap)
                        .font(.body)
                }
                .padding(8)
                .background(Color.orange.opacity(0.05))
                .cornerRadius(6)
            }
        }
    }
}
