// Copyright 2026 Amit Chorasiya. All rights reserved.
// Licensed under the Business Source License 1.1. See LICENSE file.

import SwiftUI

struct FilterEditorView: View {
    @Binding var rules: [FilterRule]
    @State private var testPath: String = ""
    @State private var showAddSheet: Bool = false
    @State private var editingRule: FilterRule? = nil
    @State private var draftRule: FilterRule = FilterRule(type: .exclude, pattern: "", description: "")
    @State private var isEditMode: Bool = false

    private var filterService: FilterService {
        FilterService(rules: rules)
    }

    private var testResult: Bool {
        guard !testPath.trimmingCharacters(in: .whitespaces).isEmpty else { return true }
        return filterService.shouldInclude(relativePath: testPath)
    }

    private static let commonExcludes: [FilterRule] = [
        FilterRule(type: .exclude, pattern: "*/.DS_Store", description: "macOS metadata"),
        FilterRule(type: .exclude, pattern: "*/.Trashes", description: "Trash folders"),
        FilterRule(type: .exclude, pattern: "*/node_modules/*", description: "Node.js deps"),
        FilterRule(type: .exclude, pattern: "*/.git/*", description: "Git metadata"),
        FilterRule(type: .exclude, pattern: "*/__pycache__/*", description: "Python cache"),
        FilterRule(type: .exclude, pattern: "*/Thumbs.db", description: "Windows thumbnails"),
    ]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: AppTheme.Spacing.xl) {
                rulesSection
                liveTestSection
                presetSection
            }
            .padding(AppTheme.Spacing.xl)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(Color.dsBackground)
        .sheet(isPresented: $showAddSheet) {
            addEditRuleSheet
        }
    }

    // MARK: - Rules Section

    private var rulesSection: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: AppTheme.Spacing.large) {
                HStack {
                    Text("Filter Rules")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(Color.dsPrimaryText)
                    Spacer()
                    GlassButton("Add Rule", icon: "plus", style: .secondary) {
                        draftRule = FilterRule(type: .exclude, pattern: "", description: "")
                        isEditMode = false
                        showAddSheet = true
                    }
                }

                if rules.isEmpty {
                    emptyState
                } else {
                    LazyVStack(spacing: 0) {
                        ForEach(rules) { rule in
                            FilterRuleRowView(
                                rule: rule,
                                onToggle: { toggleRule(rule) },
                                onEdit: {
                                    draftRule = rule
                                    isEditMode = true
                                    editingRule = rule
                                    showAddSheet = true
                                },
                                onDelete: { deleteRule(rule) }
                            )

                            if rule.id != rules.last?.id {
                                Divider()
                                    .background(Color.dsSeparator)
                                    .padding(.leading, AppTheme.Spacing.xl)
                            }
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var emptyState: some View {
        VStack(spacing: AppTheme.Spacing.medium) {
            Image(systemName: "line.3.horizontal.decrease.circle")
                .font(.system(size: 32))
                .foregroundStyle(Color.dsTertiaryText)
            Text("No filter rules yet")
                .font(.system(size: 13))
                .foregroundStyle(Color.dsSecondaryText)
            Text("Add rules to include or exclude files during sync")
                .font(.system(size: 12))
                .foregroundStyle(Color.dsTertiaryText)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, AppTheme.Spacing.xl)
    }

    // MARK: - Live Test Section

    private var liveTestSection: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: AppTheme.Spacing.large) {
                Text("Live Test")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(Color.dsPrimaryText)

                VStack(alignment: .leading, spacing: AppTheme.Spacing.small) {
                    TextField("Enter a sample path (e.g. Documents/node_modules/foo.js)", text: $testPath)
                        .textFieldStyle(.roundedBorder)
                        .font(.system(size: 13, design: .monospaced))

                    HStack(spacing: AppTheme.Spacing.small) {
                        Circle()
                            .fill(testResult ? Color.dsSuccess : Color.dsDestructive)
                            .frame(width: 8, height: 8)
                        Text(testResult ? "INCLUDED" : "EXCLUDED")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(testResult ? Color.dsSuccess : Color.dsDestructive)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    // MARK: - Preset Section

    private var presetSection: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: AppTheme.Spacing.large) {
                Text("Presets")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(Color.dsPrimaryText)

                GlassButton("Add Common Excludes", icon: "folder.badge.minus", style: .secondary) {
                    addCommonExcludes()
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    // MARK: - Add/Edit Sheet

    private var addEditRuleSheet: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.xl) {
            HStack {
                Text(isEditMode ? "Edit Rule" : "Add Rule")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(Color.dsPrimaryText)
                Spacer()
                Button {
                    showAddSheet = false
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 22))
                        .foregroundStyle(Color.dsTertiaryText)
                }
                .buttonStyle(.plain)
            }

            VStack(alignment: .leading, spacing: AppTheme.Spacing.medium) {
                Text("Type")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Color.dsSecondaryText)
                Picker("", selection: $draftRule.type) {
                    Text("Include").tag(FilterRuleType.include)
                    Text("Exclude").tag(FilterRuleType.exclude)
                }
                .pickerStyle(.segmented)
            }

            VStack(alignment: .leading, spacing: AppTheme.Spacing.small) {
                Text("Pattern")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Color.dsSecondaryText)
                TextField("e.g. *.tmp, */.DS_Store", text: $draftRule.pattern)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: 13, design: .monospaced))
            }

            VStack(alignment: .leading, spacing: AppTheme.Spacing.small) {
                Text("Description")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Color.dsSecondaryText)
                TextField("Optional description", text: $draftRule.description)
                    .textFieldStyle(.roundedBorder)
            }

            Spacer()

            HStack(spacing: AppTheme.Spacing.medium) {
                GlassButton("Cancel", icon: "xmark", style: .secondary) {
                    showAddSheet = false
                }
                GlassButton(isEditMode ? "Save" : "Add", icon: "checkmark") {
                    saveRule()
                    showAddSheet = false
                }
                .disabled(draftRule.pattern.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            .frame(maxWidth: .infinity, alignment: .trailing)
        }
        .padding(AppTheme.Spacing.xl)
        .frame(minWidth: 400, minHeight: 320)
        .background(Color.dsBackground)
    }

    // MARK: - Actions

    private func toggleRule(_ rule: FilterRule) {
        withAnimation(AppTheme.Animation.respectingReducedMotion(AppTheme.Animation.springSnappy)) {
            if let idx = rules.firstIndex(where: { $0.id == rule.id }) {
                rules[idx].isEnabled.toggle()
            }
        }
    }

    private func deleteRule(_ rule: FilterRule) {
        withAnimation(AppTheme.Animation.respectingReducedMotion(AppTheme.Animation.springSnappy)) {
            rules.removeAll { $0.id == rule.id }
        }
    }

    private func addCommonExcludes() {
        withAnimation(AppTheme.Animation.respectingReducedMotion(AppTheme.Animation.springSnappy)) {
            for rule in Self.commonExcludes {
                if !rules.contains(where: { $0.pattern == rule.pattern && $0.type == rule.type }) {
                    rules.append(rule)
                }
            }
        }
    }

    private func saveRule() {
        withAnimation(AppTheme.Animation.respectingReducedMotion(AppTheme.Animation.springSnappy)) {
            let pattern = draftRule.pattern.trimmingCharacters(in: .whitespaces)
            guard !pattern.isEmpty else { return }

            var updated = draftRule
            updated.pattern = pattern
            if updated.description.isEmpty {
                updated.description = pattern
            }

            if isEditMode, let idx = rules.firstIndex(where: { $0.id == editingRule?.id }) {
                rules[idx] = updated
            } else {
                rules.append(updated)
            }
        }
        editingRule = nil
    }
}

// MARK: - Filter Rule Row

private struct FilterRuleRowView: View {
    let rule: FilterRule
    let onToggle: () -> Void
    let onEdit: () -> Void
    let onDelete: () -> Void

    private var typeBadgeColor: Color {
        rule.type == .include ? Color.dsSuccess : Color.dsDestructive
    }

    private var typeLabel: String {
        rule.type == .include ? "Include" : "Exclude"
    }

    var body: some View {
        HStack(spacing: AppTheme.Spacing.medium) {
            Toggle("", isOn: Binding(
                get: { rule.isEnabled },
                set: { _ in onToggle() }
            ))
            .toggleStyle(.checkbox)
            .labelsHidden()

            Text(typeLabel)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(typeBadgeColor)
                .padding(.horizontal, AppTheme.Spacing.small)
                .padding(.vertical, 2)
                .background(typeBadgeColor.opacity(0.2), in: Capsule())

            VStack(alignment: .leading, spacing: 2) {
                Text(rule.pattern)
                    .font(.system(size: 13, weight: .medium, design: .monospaced))
                    .foregroundStyle(Color.dsPrimaryText)
                    .lineLimit(1)
                    .truncationMode(.middle)
                if !rule.description.isEmpty && rule.description != rule.pattern {
                    Text(rule.description)
                        .font(.system(size: 11))
                        .foregroundStyle(Color.dsSecondaryText)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Button {
                onEdit()
            } label: {
                Image(systemName: "pencil")
                    .font(.system(size: 12))
                    .foregroundStyle(Color.dsSecondaryText)
            }
            .buttonStyle(.plain)

            Button {
                onDelete()
            } label: {
                Image(systemName: "trash")
                    .font(.system(size: 12))
                    .foregroundStyle(Color.dsDestructive)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, AppTheme.Spacing.medium)
        .padding(.vertical, AppTheme.Spacing.small)
        .contentShape(Rectangle())
    }
}
