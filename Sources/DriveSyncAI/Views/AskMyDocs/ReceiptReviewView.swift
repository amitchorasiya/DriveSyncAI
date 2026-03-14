// Copyright 2026 Amit Chorasiya. All rights reserved.
// Licensed under the Business Source License 1.1. See LICENSE file.

import SwiftUI

struct ReceiptReviewView: View {
    @ObservedObject var insightService: DocumentInsightService
    @ObservedObject var chatService: AskMyDocsChatService
    var configManager: LLMConfigManager
    
    @State private var isReviewing = false
    
    var body: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.large) {
            piiProtectionBanner
            sourceDocumentsStatus
            runReviewButton
            
            if let result = chatService.lastReceiptReviewResult {
                findingsDashboard(result)
            }
        }
    }
    
    private var piiProtectionBanner: some View {
        HStack(spacing: 8) {
            Image(systemName: "shield.checkered")
                .foregroundStyle(.green)
            VStack(alignment: .leading, spacing: 1) {
                Text("PII/PCI Protection: Always ON")
                    .font(.caption.bold())
                    .foregroundStyle(Color.dsPrimaryText)
                Text("Credit card numbers and other sensitive data are automatically redacted before being sent to the AI model.")
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
            Text("Source Documents (Receipts)")
                .font(.subheadline.bold())
            
            if insightService.corpus.successfulDocuments.isEmpty {
                HStack {
                    Image(systemName: "exclamationmark.triangle")
                        .foregroundStyle(.orange)
                    Text("No source documents scanned. Add folders with your receipts.")
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
                await chatService.runReceiptReview(
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
                    Text("Run Receipt Review")
                }
            }
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.borderedProminent)
        .controlSize(.large)
        .disabled(insightService.corpus.successfulDocuments.isEmpty || isReviewing)
    }
    
    private func findingsDashboard(_ result: ReceiptReviewResult) -> some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.large) {
            Divider()
            
            HStack(spacing: AppTheme.Spacing.xl) {
                summaryBadge(title: "Total", value: formatCurrency(result.totalAmount), icon: "dollarsign.circle.fill", color: .green)
                summaryBadge(title: "Items", value: "\(result.items.count)", icon: "list.bullet", color: .blue)
                Spacer()
            }
            
            if !result.items.isEmpty {
                itemsList(result.items)
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
    
    private func itemsList(_ items: [ReceiptItem]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Receipt Items")
                .font(.headline)
            
            VStack(spacing: 1) {
                ForEach(items) { item in
                    HStack {
                        Image(systemName: item.status.icon)
                            .foregroundStyle(statusColor(item.status))
                        
                        VStack(alignment: .leading) {
                            Text(item.merchant)
                                .font(.subheadline.bold())
                            Text(item.date?.formatted(date: .numeric, time: .omitted) ?? "No Date")
                                .font(.caption2)
                                .foregroundStyle(Color.dsSecondaryText)
                        }
                        
                        Spacer()
                        
                        Text(formatCurrency(item.amount ?? 0))
                            .font(.subheadline.monospacedDigit())
                        
                        if let cat = item.category {
                            Text(cat)
                                .font(.caption2)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Color.dsSecondaryBackground)
                                .cornerRadius(4)
                        }
                    }
                    .padding(8)
                    .background(Color.dsSecondaryBackground.opacity(0.5))
                }
            }
            .cornerRadius(8)
        }
    }
    
    private func statusColor(_ status: ReceiptStatus) -> Color {
        switch status {
        case .verified: return .green
        case .mismatch: return .orange
        case .missing: return .red
        case .duplicate: return .purple
        case .unknown: return .gray
        }
    }
    
    private func formatCurrency(_ amount: Decimal) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = "USD"
        return formatter.string(from: NSNumber(value: NSDecimalNumber(decimal: amount).doubleValue)) ?? "$0.00"
    }
}
