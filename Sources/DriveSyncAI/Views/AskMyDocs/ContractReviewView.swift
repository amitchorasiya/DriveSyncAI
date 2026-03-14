// Copyright 2026 Amit Chorasiya. All rights reserved.
// Licensed under the Business Source License 1.1. See LICENSE file.

import SwiftUI

struct ContractReviewView: View {
    @ObservedObject var insightService: DocumentInsightService
    @ObservedObject var chatService: AskMyDocsChatService
    var configManager: LLMConfigManager
    
    @State private var isReviewing = false
    
    var body: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.large) {
            piiProtectionBanner
            sourceDocumentsStatus
            runReviewButton
            
            if let result = chatService.lastContractReviewResult {
                findingsDashboard(result)
            }
        }
    }
    
    private var piiProtectionBanner: some View {
        HStack(spacing: 8) {
            Image(systemName: "shield.checkered")
                .foregroundStyle(.green)
            VStack(alignment: .leading, spacing: 1) {
                Text("PII Protection: Always ON")
                    .font(.caption.bold())
                    .foregroundStyle(Color.dsPrimaryText)
                Text("Names, SSNs, and other sensitive data are automatically redacted before being sent to the AI model.")
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
            Text("Source Documents (Contracts)")
                .font(.subheadline.bold())
            
            if insightService.corpus.successfulDocuments.isEmpty {
                HStack {
                    Image(systemName: "exclamationmark.triangle")
                        .foregroundStyle(.orange)
                    Text("No source documents scanned. Add folders with your contracts.")
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
                await chatService.runContractReview(
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
                    Text("Run Contract Review")
                }
            }
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.borderedProminent)
        .controlSize(.large)
        .disabled(insightService.corpus.successfulDocuments.isEmpty || isReviewing)
    }
    
    private func findingsDashboard(_ result: ContractReviewResult) -> some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.large) {
            Divider()
            
            Text("Summary")
                .font(.headline)
            Text(result.summary)
                .font(.body)
                .foregroundStyle(Color.dsSecondaryText)
            
            if !result.criticalRisks.isEmpty {
                risksSection(result.criticalRisks)
            }
            
            if !result.keyTerms.isEmpty {
                termsSection(result.keyTerms)
            }
        }
    }
    
    private func risksSection(_ risks: [ContractTerm]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.red)
                Text("Critical Risks")
                    .font(.headline)
                    .foregroundStyle(.red)
            }
            
            ForEach(risks) { risk in
                HStack(alignment: .top) {
                    VStack(alignment: .leading) {
                        Text(risk.term)
                            .font(.subheadline.bold())
                        Text(risk.description)
                            .font(.caption)
                            .foregroundStyle(Color.dsSecondaryText)
                    }
                    Spacer()
                    if let page = risk.pageReference {
                        Text(page)
                            .font(.caption2)
                            .foregroundStyle(Color.dsTertiaryText)
                    }
                }
                .padding(8)
                .background(Color.red.opacity(0.05))
                .cornerRadius(6)
            }
        }
    }
    
    private func termsSection(_ terms: [ContractTerm]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Key Terms")
                .font(.headline)
            
            ForEach(terms) { term in
                HStack(alignment: .top) {
                    VStack(alignment: .leading) {
                        Text(term.term)
                            .font(.subheadline.bold())
                        Text(term.description)
                            .font(.caption)
                            .foregroundStyle(Color.dsSecondaryText)
                    }
                    Spacer()
                    Text(term.type.displayName)
                        .font(.caption2)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.dsSecondaryBackground)
                        .cornerRadius(4)
                }
                .padding(8)
                .background(Color.dsSecondaryBackground.opacity(0.5))
                .cornerRadius(6)
            }
        }
    }
}
