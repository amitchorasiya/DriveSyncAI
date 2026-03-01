// Copyright 2026 Amit Chorasiya. All rights reserved.
// Licensed under the Business Source License 1.1. See LICENSE file.

import SwiftUI

/// Premium achievements view with glass cards, tier badges, and stats summary.
struct AchievementsView: View {
    @EnvironmentObject var achievementService: AchievementService

    private let columns = [
        GridItem(.flexible(), spacing: AppTheme.Spacing.large),
        GridItem(.flexible(), spacing: AppTheme.Spacing.large)
    ]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: AppTheme.Spacing.xl) {
                statsSummarySection
                achievementsGrid
            }
            .padding(AppTheme.Spacing.xl)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(Color.dsBackground)
        .navigationTitle("Achievements")
    }

    private var statsSummarySection: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: AppTheme.Spacing.large) {
                Text("Your Progress")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(Color.dsPrimaryText)

                HStack(spacing: AppTheme.Spacing.xl) {
                    statItem(value: achievementService.stats.formattedBytesSynced, label: "Synced")
                    statItem(value: achievementService.stats.formattedSpaceSaved, label: "Space Saved")
                    statItem(value: "\(achievementService.stats.totalDuplicatesFound)", label: "Duplicates Found")
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func statItem(value: String, label: String) -> some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.small) {
            Text(value)
                .font(.system(size: 18, weight: .bold, design: .rounded))
                .foregroundStyle(Color.dsPrimaryText)
            Text(label)
                .font(.system(size: 12))
                .foregroundStyle(Color.dsSecondaryText)
        }
    }

    private var achievementsGrid: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.large) {
            Text("Achievements")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(Color.dsPrimaryText)

            LazyVGrid(columns: columns, spacing: AppTheme.Spacing.large) {
                ForEach(achievementService.achievements) { achievement in
                    AchievementCard(achievement: achievement)
                }
            }
        }
    }
}

// MARK: - Achievement Card

private struct AchievementCard: View {
    let achievement: Achievement

    var body: some View {
        GlassCard(padding: AppTheme.Spacing.large) {
            VStack(alignment: .leading, spacing: AppTheme.Spacing.medium) {
                HStack(spacing: AppTheme.Spacing.medium) {
                    iconView
                    VStack(alignment: .leading, spacing: 2) {
                        Text(achievement.name)
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(achievement.isUnlocked ? Color.dsPrimaryText : Color.dsSecondaryText)
                        tierBadge
                    }
                    Spacer()
                    statusBadge
                }

                Text(achievement.description)
                    .font(.system(size: 12))
                    .foregroundStyle(achievement.isUnlocked ? Color.dsSecondaryText : Color.dsTertiaryText)
                    .lineLimit(2)

                if let date = achievement.unlockedAt {
                    Text(unlockDateString(date))
                        .font(.system(size: 11))
                        .foregroundStyle(Color.dsTertiaryText)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .opacity(achievement.isUnlocked ? 1 : 0.7)
        }
    }

    private var iconView: some View {
        ZStack {
            RoundedRectangle(cornerRadius: AppTheme.CornerRadius.medium, style: .continuous)
                .fill(achievement.isUnlocked ? tierColor.opacity(0.2) : Color.dsTertiaryFill)
                .frame(width: 44, height: 44)

            Image(systemName: achievement.isUnlocked ? achievement.icon : "lock.fill")
                .font(.system(size: 20, weight: .medium))
                .foregroundStyle(achievement.isUnlocked ? tierColor : Color.dsSecondaryText)
        }
    }

    private var tierBadge: some View {
        Text(achievement.tier.rawValue.capitalized)
            .font(.system(size: 10, weight: .bold))
            .foregroundStyle(achievement.isUnlocked ? .white : Color.dsSecondaryText)
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .background(
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .fill(achievement.isUnlocked ? tierColor : Color.dsTertiaryFill)
            )
    }

    private var statusBadge: some View {
        Group {
            if achievement.isUnlocked {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 18))
                    .foregroundStyle(Color.dsSuccess)
            } else {
                Image(systemName: "lock.fill")
                    .font(.system(size: 14))
                    .foregroundStyle(Color.dsTertiaryText)
            }
        }
    }

    private var tierColor: Color {
        switch achievement.tier {
        case .bronze:
            return Color(red: 0.8, green: 0.5, blue: 0.2)
        case .silver:
            return Color(red: 0.6, green: 0.6, blue: 0.65)
        case .gold:
            return Color(red: 0.85, green: 0.65, blue: 0.13)
        case .platinum:
            return Color(red: 0.65, green: 0.55, blue: 0.85)
        }
    }

    private func unlockDateString(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        return "Unlocked \(formatter.string(from: date))"
    }
}
