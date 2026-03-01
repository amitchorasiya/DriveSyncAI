// Copyright 2026 Amit Chorasiya. All rights reserved.
// Licensed under the Business Source License 1.1. See LICENSE file.

import SwiftUI
import UniformTypeIdentifiers

struct CustomRulesEditorView: View {
    @EnvironmentObject var rulesService: CustomRulesService
    @State private var showingAddSheet = false
    @State private var editingRule: CustomRule?
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            header
            rulesList
            footer
        }
        .frame(width: 560, height: 500)
        .sheet(isPresented: $showingAddSheet) {
            RuleEditorSheet(rulesService: rulesService)
        }
        .sheet(item: $editingRule) { rule in
            RuleEditorSheet(rulesService: rulesService, existingRule: rule)
        }
    }

    private var header: some View {
        VStack(spacing: AppTheme.Spacing.small) {
            Text("Custom Organization Rules")
                .font(.system(size: 18, weight: .bold))
                .foregroundStyle(Color.dsPrimaryText)
            Text("Rules run before AI, giving you direct control over file placement.")
                .font(.system(size: 12))
                .foregroundStyle(Color.dsSecondaryText)
        }
        .padding(AppTheme.Spacing.large)
    }

    private var rulesList: some View {
        GlassCard(padding: 0) {
            if rulesService.rules.isEmpty {
                VStack(spacing: AppTheme.Spacing.medium) {
                    Image(systemName: "list.bullet.rectangle")
                        .font(.system(size: 32))
                        .foregroundStyle(Color.dsTertiaryText)
                    Text("No custom rules yet")
                        .font(.system(size: 14))
                        .foregroundStyle(Color.dsSecondaryText)
                    Text("Add rules to control how specific files get organized.")
                        .font(.system(size: 12))
                        .foregroundStyle(Color.dsTertiaryText)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(AppTheme.Spacing.xl)
            } else {
                List {
                    ForEach(rulesService.rules) { rule in
                        ruleRow(rule)
                    }
                    .onMove { source, dest in
                        rulesService.moveRules(from: source, to: dest)
                    }
                }
                .listStyle(.plain)
            }
        }
        .padding(.horizontal, AppTheme.Spacing.large)
    }

    private func ruleRow(_ rule: CustomRule) -> some View {
        HStack {
            Toggle("", isOn: Binding(
                get: { rule.isEnabled },
                set: { _ in rulesService.toggleRule(id: rule.id) }
            ))
            .toggleStyle(.switch)
            .labelsHidden()
            .controlSize(.small)

            VStack(alignment: .leading, spacing: 2) {
                Text(rule.name)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(rule.isEnabled ? Color.dsPrimaryText : Color.dsTertiaryText)
                Text(rule.displaySummary)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(Color.dsSecondaryText)
                if let cond = rule.condition {
                    Text(cond.displayDescription)
                        .font(.system(size: 10))
                        .foregroundStyle(Color.dsTertiaryText)
                }
            }

            Spacer()

            Button(action: { editingRule = rule }) {
                Image(systemName: "pencil")
                    .foregroundStyle(Color.dsSecondaryText)
            }
            .buttonStyle(.plain)

            Button(action: { rulesService.deleteRule(id: rule.id) }) {
                Image(systemName: "trash")
                    .foregroundStyle(Color.dsDestructive)
            }
            .buttonStyle(.plain)
        }
        .padding(.vertical, 4)
    }

    private var footer: some View {
        HStack {
            Button(action: { showingAddSheet = true }) {
                Label("Add Rule", systemImage: "plus")
            }
            .buttonStyle(.bordered)

            Spacer()

            Button("Done") { dismiss() }
                .buttonStyle(.borderedProminent)
        }
        .padding(AppTheme.Spacing.large)
    }
}

// MARK: - Rule Editor Sheet

struct RuleEditorSheet: View {
    let rulesService: CustomRulesService
    @State private var name: String
    @State private var pattern: String
    @State private var destination: String
    @State private var hasCondition = false
    @State private var conditionType = "olderThan"
    @State private var conditionDays = 30
    @State private var conditionBytes: Int64 = 10_000_000
    @State private var conditionFolder = ""
    @Environment(\.dismiss) private var dismiss

    private let existingRule: CustomRule?

    init(rulesService: CustomRulesService, existingRule: CustomRule? = nil) {
        self.rulesService = rulesService
        self.existingRule = existingRule
        _name = State(initialValue: existingRule?.name ?? "")
        _pattern = State(initialValue: existingRule?.pattern ?? "")
        _destination = State(initialValue: existingRule?.destination ?? "")
        _hasCondition = State(initialValue: existingRule?.condition != nil)
    }

    var body: some View {
        VStack(spacing: AppTheme.Spacing.large) {
            Text(existingRule != nil ? "Edit Rule" : "New Rule")
                .font(.system(size: 16, weight: .bold))

            VStack(alignment: .leading, spacing: AppTheme.Spacing.medium) {
                field("Name", text: $name, placeholder: "My Rule")
                field("Pattern", text: $pattern, placeholder: "*.pdf, Screenshot*, IMG_*")
                field("Destination", text: $destination, placeholder: "Documents/Reports")

                VStack(alignment: .leading, spacing: 4) {
                    Text("Pattern Examples")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Color.dsSecondaryText)
                    Text("*.pdf — all PDF files\nIMG_* — files starting with IMG_\n*.receipt.* — files with 'receipt' before extension")
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(Color.dsTertiaryText)
                }

                Toggle("Add condition", isOn: $hasCondition)
                    .font(.system(size: 12))

                if hasCondition {
                    Picker("Condition", selection: $conditionType) {
                        Text("Older than N days").tag("olderThan")
                        Text("Newer than N days").tag("newerThan")
                        Text("Larger than").tag("largerThan")
                        Text("Smaller than").tag("smallerThan")
                        Text("In folder").tag("inFolder")
                    }
                    .font(.system(size: 12))

                    if conditionType == "olderThan" || conditionType == "newerThan" {
                        Stepper("Days: \(conditionDays)", value: $conditionDays, in: 1...3650)
                            .font(.system(size: 12))
                    }
                    if conditionType == "inFolder" {
                        field("Folder name", text: $conditionFolder, placeholder: "Downloads")
                    }
                }
            }

            HStack {
                Button("Cancel") { dismiss() }
                    .buttonStyle(.bordered)
                Spacer()
                Button(existingRule != nil ? "Save" : "Add") {
                    saveRule()
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
                .disabled(name.isEmpty || pattern.isEmpty || destination.isEmpty)
            }
        }
        .padding(AppTheme.Spacing.xl)
        .frame(width: 420)
    }

    private func field(_ label: String, text: Binding<String>, placeholder: String) -> some View {
        HStack {
            Text(label)
                .font(.system(size: 12))
                .foregroundStyle(Color.dsSecondaryText)
                .frame(width: 80, alignment: .trailing)
            TextField(placeholder, text: text)
                .textFieldStyle(.roundedBorder)
        }
    }

    private func saveRule() {
        var condition: RuleCondition? = nil
        if hasCondition {
            switch conditionType {
            case "olderThan": condition = .olderThan(days: conditionDays)
            case "newerThan": condition = .newerThan(days: conditionDays)
            case "largerThan": condition = .largerThan(bytes: conditionBytes)
            case "smallerThan": condition = .smallerThan(bytes: conditionBytes)
            case "inFolder": condition = .inFolder(conditionFolder)
            default: break
            }
        }

        if var existing = existingRule {
            existing.name = name
            existing.pattern = pattern
            existing.destination = destination
            existing.condition = condition
            rulesService.updateRule(existing)
        } else {
            let rule = CustomRule(name: name, pattern: pattern, destination: destination, condition: condition)
            rulesService.addRule(rule)
        }
    }
}
