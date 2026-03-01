// Copyright 2026 Amit Chorasiya. All rights reserved.
// Licensed under the Business Source License 1.1. See LICENSE file.

import SwiftUI

private extension DriveConnectionType {
    var displayName: String {
        switch self {
        case .usb2: return "USB 2"
        case .usb3: return "USB 3"
        case .thunderbolt: return "Thunderbolt"
        case .nvme: return "NVMe"
        case .network: return "Network"
        case .internal_: return "Internal"
        case .unknown: return "Unknown"
        }
    }
}

struct DriveStatusCard: View {
    let drive: DriveInfo
    var lastSyncDate: Date? = nil

    private var usageColor: Color {
        let pct = drive.usagePercentage
        if pct < 60 { return .dsSuccess }
        if pct < 80 { return .dsWarning }
        return .dsDestructive
    }

    private var lastSyncText: String {
        if let date = lastSyncDate {
            let formatter = RelativeDateTimeFormatter()
            formatter.unitsStyle = .abbreviated
            return formatter.localizedString(for: date, relativeTo: Date())
        }
        return "Never synced"
    }

    var body: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: AppTheme.Spacing.large) {
                HStack(spacing: AppTheme.Spacing.medium) {
                    Image(systemName: "externaldrive.fill")
                        .font(.system(size: 24, weight: .medium))
                        .foregroundStyle(Color.dsAction)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(drive.name)
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(Color.dsPrimaryText)

                        Text("\(drive.formattedUsed) / \(drive.formattedTotal)")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(Color.dsSecondaryText)
                    }

                    Spacer(minLength: 0)

                    Text(drive.connectionType.displayName)
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(Color.dsSecondaryText)
                        .padding(.horizontal, AppTheme.Spacing.small)
                        .padding(.vertical, 4)
                        .background(
                            Capsule()
                                .fill(Color.dsSecondaryFill)
                        )
                }

                VStack(alignment: .leading, spacing: AppTheme.Spacing.small) {
                    GeometryReader { geometry in
                        ZStack(alignment: .leading) {
                            RoundedRectangle(cornerRadius: AppTheme.CornerRadius.small, style: .continuous)
                                .fill(Color.dsSecondaryFill)

                            RoundedRectangle(cornerRadius: AppTheme.CornerRadius.small, style: .continuous)
                                .fill(
                                    LinearGradient(
                                        colors: [usageColor, usageColor.opacity(0.85)],
                                        startPoint: .leading,
                                        endPoint: .trailing
                                    )
                                )
                                .frame(width: geometry.size.width * min(drive.usagePercentage / 100, 1))
                        }
                    }
                    .frame(height: 6)
                }

                Text(lastSyncText)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Color.dsTertiaryText)
            }
        }
        .frame(minWidth: 220, idealWidth: 260, maxWidth: 300)
    }
}
