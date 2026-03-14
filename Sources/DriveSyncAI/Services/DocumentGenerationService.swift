// Copyright 2026 Amit Chorasiya. All rights reserved.
// Licensed under the Business Source License 1.1. See LICENSE file.

import Foundation
import AppKit
import WebKit

actor DocumentGenerationService {

    // MARK: - Insight Report Generation

    func generateInsightReport(
        result: InsightResult,
        query: String,
        corpus: DocumentCorpus,
        format: ReportFormat
    ) async throws -> Data {
        switch format {
        case .pdf:
            return try await generateInsightPDF(result: result, query: query, corpus: corpus)
        case .csv:
            return generateInsightCSV(result: result, query: query)
        case .markdown:
            return generateInsightMarkdown(result: result, query: query, corpus: corpus)
        }
    }

    // MARK: - Tax Review Report Generation

    func generateTaxReviewReport(
        result: TaxReviewResult,
        format: ReportFormat
    ) async throws -> Data {
        switch format {
        case .pdf:
            return try await generateTaxReviewPDF(result: result)
        case .csv:
            return generateTaxReviewCSV(result: result)
        case .markdown:
            return generateTaxReviewMarkdown(result: result)
        }
    }

    // MARK: - Insight PDF

    private func generateInsightPDF(result: InsightResult, query: String, corpus: DocumentCorpus) async throws -> Data {
        let html = buildInsightHTML(result: result, query: query, corpus: corpus)
        return try await renderHTMLToPDF(html: html)
    }

    private func buildInsightHTML(result: InsightResult, query: String, corpus: DocumentCorpus) -> String {
        var html = htmlHeader(title: "Document Analysis Report")

        html += "<h1>Document Analysis Report</h1>"
        html += "<p class='meta'>Generated: \(formattedDate()) | Documents: \(corpus.supportedFileCount) | Domain: \(corpus.detectedDomain.displayName)</p>"

        html += "<h2>Query</h2>"
        html += "<p class='query'>\(escapeHTML(query))</p>"

        html += "<h2>Analysis</h2>"
        html += "<div class='answer'>\(escapeHTML(result.answer))</div>"

        if !result.dataPoints.isEmpty {
            html += "<h2>Extracted Data Points</h2>"
            html += "<table><thead><tr><th>Item</th><th>Value</th><th>Category</th><th>Source</th><th>Reference</th></tr></thead><tbody>"
            for dp in result.dataPoints {
                html += "<tr>"
                html += "<td>\(escapeHTML(dp.label))</td>"
                html += "<td><strong>\(escapeHTML(dp.value))</strong></td>"
                html += "<td>\(escapeHTML(dp.category ?? "—"))</td>"
                html += "<td>\(escapeHTML(dp.sourceDocument))</td>"
                html += "<td>\(escapeHTML(dp.pageReference ?? "—"))</td>"
                html += "</tr>"
            }
            html += "</tbody></table>"
        }

        if !result.supportingDocuments.isEmpty {
            html += "<h2>Supporting Documents</h2><ul>"
            for doc in result.supportingDocuments {
                html += "<li>\(escapeHTML(doc))</li>"
            }
            html += "</ul>"
        }

        if let note = result.completenessNote {
            html += "<div class='note'><strong>Note:</strong> \(escapeHTML(note))</div>"
        }

        html += htmlFooter()
        return html
    }

    // MARK: - Tax Review PDF

    private func generateTaxReviewPDF(result: TaxReviewResult) async throws -> Data {
        let html = buildTaxReviewHTML(result: result)
        return try await renderHTMLToPDF(html: html)
    }

    private func buildTaxReviewHTML(result: TaxReviewResult) -> String {
        var html = htmlHeader(title: "Tax Review Report")

        html += "<div class='disclaimer'>\(escapeHTML(TaxReviewResult.fullDisclaimer))</div>"

        html += "<h1>Tax Document Review Report</h1>"
        html += "<p class='meta'>Generated: \(formattedDate()) | Draft: \(escapeHTML(result.draftDocument))</p>"

        html += "<div class='score-section'>"
        html += "<div class='score'>Overall Score: <strong>\(result.overallScore)/100</strong></div>"
        html += "<div class='risk'>Documentation Risk Level: <strong>\(result.auditRiskLevel.displayName.uppercased())</strong></div>"
        html += "</div>"

        let verified = result.accuracyFindings.filter { $0.type == .verified }
        let discrepancies = result.accuracyFindings.filter { $0.type == .discrepancy }

        if !result.accuracyFindings.isEmpty {
            html += "<h2>Accuracy Check (\(verified.count) verified, \(discrepancies.count) discrepancies)</h2>"
            html += "<table><thead><tr><th>Status</th><th>Line</th><th>Draft Value</th><th>Source Value</th><th>Source Doc</th><th>Details</th></tr></thead><tbody>"
            for finding in result.accuracyFindings {
                let statusClass = finding.type == .verified ? "verified" : "discrepancy"
                let statusLabel = finding.type == .verified ? "Verified" : "Discrepancy"
                html += "<tr class='\(statusClass)'>"
                html += "<td><span class='badge \(statusClass)'>\(statusLabel)</span></td>"
                html += "<td>\(escapeHTML(finding.draftLineReference ?? "—"))</td>"
                html += "<td>\(escapeHTML(finding.draftValue ?? "—"))</td>"
                html += "<td>\(escapeHTML(finding.sourceValue ?? "—"))</td>"
                html += "<td>\(escapeHTML(finding.sourceDocument ?? "—"))</td>"
                html += "<td>\(escapeHTML(finding.description))</td>"
                html += "</tr>"
            }
            html += "</tbody></table>"
        }

        if !result.savingsFindings.isEmpty {
            html += "<h2>Areas to Review With Your Tax Preparer (\(result.savingsFindings.count) found)</h2>"
            if let total = result.totalPotentialSavings {
                html += "<p>Estimated potential: <strong>\(escapeHTML(total))</strong> — verify with CPA</p>"
            }
            html += "<table><thead><tr><th>Description</th><th>Est. Savings</th><th>Source</th><th>Recommendation</th></tr></thead><tbody>"
            for finding in result.savingsFindings {
                html += "<tr class='savings'>"
                html += "<td>\(escapeHTML(finding.description))</td>"
                html += "<td>\(escapeHTML(finding.potentialSavings ?? "—"))</td>"
                html += "<td>\(escapeHTML(finding.sourceDocument ?? "—"))</td>"
                html += "<td>\(escapeHTML(finding.recommendation ?? "—"))</td>"
                html += "</tr>"
            }
            html += "</tbody></table>"
        }

        if !result.auditRiskFindings.isEmpty {
            html += "<h2>Items That May Warrant Additional Documentation (\(result.auditRiskFindings.count))</h2>"
            html += "<table><thead><tr><th>Severity</th><th>Description</th><th>Recommendation</th></tr></thead><tbody>"
            for finding in result.auditRiskFindings {
                html += "<tr>"
                html += "<td><span class='badge severity-\(finding.severity.rawValue)'>\(finding.severity.displayName)</span></td>"
                html += "<td>\(escapeHTML(finding.description))</td>"
                html += "<td>\(escapeHTML(finding.recommendation ?? "—"))</td>"
                html += "</tr>"
            }
            html += "</tbody></table>"
        }

        if !result.yoyFindings.isEmpty {
            html += "<h2>Year-over-Year Changes (\(result.yoyFindings.count))</h2>"
            html += "<table><thead><tr><th>Description</th><th>Current Year</th><th>Prior Year</th></tr></thead><tbody>"
            for finding in result.yoyFindings {
                html += "<tr>"
                html += "<td>\(escapeHTML(finding.description))</td>"
                html += "<td>\(escapeHTML(finding.draftValue ?? "—"))</td>"
                html += "<td>\(escapeHTML(finding.sourceValue ?? "—"))</td>"
                html += "</tr>"
            }
            html += "</tbody></table>"
        }

        html += "<div class='disclaimer'>\(escapeHTML(TaxReviewResult.fullDisclaimer))</div>"
        html += htmlFooter()
        return html
    }

    // MARK: - CSV Generation

    private func generateInsightCSV(result: InsightResult, query: String) -> Data {
        var lines = [
            "\"DriveSyncAI Document Analysis Export\"",
            "\"Query\",\"\(csvEscape(query))\"",
            "\"Generated\",\"\(formattedDate())\"",
            "",
            "\"Label\",\"Value\",\"Category\",\"Source Document\",\"Page Reference\",\"Confidence\""
        ]

        for dp in result.dataPoints {
            lines.append("\"\(csvEscape(dp.label))\",\"\(csvEscape(dp.value))\",\"\(csvEscape(dp.category ?? ""))\",\"\(csvEscape(dp.sourceDocument))\",\"\(csvEscape(dp.pageReference ?? ""))\",\"\(dp.confidence)\"")
        }

        return lines.joined(separator: "\n").data(using: .utf8) ?? Data()
    }

    private func generateTaxReviewCSV(result: TaxReviewResult) -> Data {
        var lines = [
            "\"\(csvEscape(TaxReviewResult.shortDisclaimer))\"",
            "",
            "\"Tax Review Report\"",
            "\"Draft\",\"\(csvEscape(result.draftDocument))\"",
            "\"Score\",\"\(result.overallScore)/100\"",
            "\"Risk Level\",\"\(result.auditRiskLevel.displayName)\"",
            "\"Generated\",\"\(formattedDate())\"",
            "",
            "\"Type\",\"Severity\",\"Description\",\"Draft Line\",\"Draft Value\",\"Source Value\",\"Source Doc\",\"Est. Savings\",\"Recommendation\""
        ]

        for finding in result.findings {
            lines.append("\"\(finding.type.rawValue)\",\"\(finding.severity.rawValue)\",\"\(csvEscape(finding.description))\",\"\(csvEscape(finding.draftLineReference ?? ""))\",\"\(csvEscape(finding.draftValue ?? ""))\",\"\(csvEscape(finding.sourceValue ?? ""))\",\"\(csvEscape(finding.sourceDocument ?? ""))\",\"\(csvEscape(finding.potentialSavings ?? ""))\",\"\(csvEscape(finding.recommendation ?? ""))\"")
        }

        lines.append("")
        lines.append("\"\(csvEscape(TaxReviewResult.fullDisclaimer))\"")

        return lines.joined(separator: "\n").data(using: .utf8) ?? Data()
    }

    // MARK: - Markdown Generation

    private func generateInsightMarkdown(result: InsightResult, query: String, corpus: DocumentCorpus) -> Data {
        var md = "# Document Analysis Report\n\n"
        md += "**Generated:** \(formattedDate()) | **Documents:** \(corpus.supportedFileCount) | **Domain:** \(corpus.detectedDomain.displayName)\n\n"
        md += "## Query\n\n> \(query)\n\n"
        md += "## Analysis\n\n\(result.answer)\n\n"

        if !result.dataPoints.isEmpty {
            md += "## Extracted Data Points\n\n"
            md += "| Item | Value | Category | Source | Reference |\n"
            md += "|------|-------|----------|--------|-----------|\n"
            for dp in result.dataPoints {
                md += "| \(dp.label) | **\(dp.value)** | \(dp.category ?? "—") | \(dp.sourceDocument) | \(dp.pageReference ?? "—") |\n"
            }
            md += "\n"
        }

        if let note = result.completenessNote {
            md += "> **Note:** \(note)\n\n"
        }

        return md.data(using: .utf8) ?? Data()
    }

    private func generateTaxReviewMarkdown(result: TaxReviewResult) -> Data {
        var md = "> \(TaxReviewResult.shortDisclaimer)\n\n"
        md += "# Tax Document Review Report\n\n"
        md += "**Draft:** \(result.draftDocument) | **Score:** \(result.overallScore)/100 | **Risk Level:** \(result.auditRiskLevel.displayName)\n\n"
        md += "**Generated:** \(formattedDate())\n\n"

        if !result.accuracyFindings.isEmpty {
            md += "## Accuracy Check\n\n"
            md += "| Status | Line | Draft | Source | Source Doc |\n"
            md += "|--------|------|-------|--------|------------|\n"
            for f in result.accuracyFindings {
                let status = f.type == .verified ? "Verified" : "**DISCREPANCY**"
                md += "| \(status) | \(f.draftLineReference ?? "—") | \(f.draftValue ?? "—") | \(f.sourceValue ?? "—") | \(f.sourceDocument ?? "—") |\n"
            }
            md += "\n"
        }

        if !result.savingsFindings.isEmpty {
            md += "## Areas to Review With Your Tax Preparer\n\n"
            for f in result.savingsFindings {
                md += "- **\(f.description)**"
                if let savings = f.potentialSavings { md += " (\(savings))" }
                md += "\n"
                if let rec = f.recommendation { md += "  - *\(rec)*\n" }
            }
            md += "\n"
        }

        if !result.auditRiskFindings.isEmpty {
            md += "## Items That May Warrant Additional Documentation\n\n"
            for f in result.auditRiskFindings {
                md += "- [\(f.severity.displayName)] \(f.description)\n"
                if let rec = f.recommendation { md += "  - *\(rec)*\n" }
            }
            md += "\n"
        }

        if !result.yoyFindings.isEmpty {
            md += "## Year-over-Year Changes\n\n"
            for f in result.yoyFindings {
                md += "- \(f.description)"
                if let curr = f.draftValue, let prev = f.sourceValue {
                    md += " (Current: \(curr), Prior: \(prev))"
                }
                md += "\n"
            }
            md += "\n"
        }

        md += "---\n\n"
        md += "> \(TaxReviewResult.fullDisclaimer)\n"

        return md.data(using: .utf8) ?? Data()
    }

    // MARK: - HTML to PDF Rendering

    @MainActor
    private func renderHTMLToPDF(html: String) async throws -> Data {
        let webView = WKWebView(frame: NSRect(x: 0, y: 0, width: 800, height: 1200))
        webView.loadHTMLString(html, baseURL: nil)

        try await Task.sleep(nanoseconds: 1_500_000_000)

        let config = WKPDFConfiguration()
        config.rect = NSRect(x: 0, y: 0, width: 612, height: 792)

        return try await webView.pdf(configuration: config)
    }

    // MARK: - HTML Templates

    private func htmlHeader(title: String) -> String {
        """
        <!DOCTYPE html>
        <html><head><meta charset="utf-8"><title>\(title)</title>
        <style>
        body { font-family: -apple-system, Helvetica Neue, sans-serif; margin: 40px; color: #333; font-size: 13px; line-height: 1.5; }
        h1 { font-size: 22px; border-bottom: 2px solid #333; padding-bottom: 8px; }
        h2 { font-size: 16px; color: #555; margin-top: 24px; border-bottom: 1px solid #ddd; padding-bottom: 4px; }
        .meta { color: #888; font-size: 11px; }
        .query { background: #f5f5f5; padding: 12px; border-radius: 6px; font-style: italic; }
        .answer { margin: 12px 0; }
        .disclaimer { background: #fff3cd; border: 1px solid #ffc107; padding: 12px; border-radius: 6px; font-size: 11px; margin: 16px 0; }
        .note { background: #e3f2fd; border: 1px solid #90caf9; padding: 10px; border-radius: 6px; margin: 12px 0; }
        table { width: 100%; border-collapse: collapse; margin: 12px 0; font-size: 12px; table-layout: fixed; }
        th { background: #f0f0f0; padding: 8px; text-align: left; border: 1px solid #ddd; word-wrap: break-word; overflow-wrap: break-word; }
        td { padding: 6px 8px; border: 1px solid #eee; word-wrap: break-word; overflow-wrap: break-word; word-break: break-word; vertical-align: top; }
        tr:nth-child(even) { background: #fafafa; }
        /* Last column (e.g. Recommendation, Details) gets enough width so text wraps instead of cutting off */
        table th:last-child, table td:last-child { width: 40%; }
        .badge { display: inline-block; padding: 2px 8px; border-radius: 4px; font-size: 11px; font-weight: 600; }
        .badge.verified { background: #e8f5e9; color: #2e7d32; }
        .badge.discrepancy { background: #ffebee; color: #c62828; }
        .badge.savings { background: #fff8e1; color: #f57f17; }
        .badge.severity-info { background: #e3f2fd; color: #1565c0; }
        .badge.severity-low { background: #e8f5e9; color: #2e7d32; }
        .badge.severity-medium { background: #fff8e1; color: #f57f17; }
        .badge.severity-high { background: #ffebee; color: #c62828; }
        .badge.severity-critical { background: #b71c1c; color: #fff; }
        .score-section { display: flex; gap: 24px; margin: 16px 0; }
        .score, .risk { background: #f5f5f5; padding: 12px 20px; border-radius: 8px; font-size: 16px; }
        </style></head><body>
        """
    }

    private func htmlFooter() -> String {
        """
        <div class='meta' style='margin-top: 32px; border-top: 1px solid #ddd; padding-top: 8px;'>
        Generated by DriveSyncAI | \(formattedDate())
        </div></body></html>
        """
    }

    // MARK: - Utilities

    private func formattedDate() -> String {
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = .short
        return f.string(from: Date())
    }

    private func escapeHTML(_ text: String) -> String {
        text.replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
    }

    private func csvEscape(_ text: String) -> String {
        text.replacingOccurrences(of: "\"", with: "\"\"")
    }
}
