// Copyright 2026 Amit Chorasiya. All rights reserved.
// Licensed under the Business Source License 1.1. See LICENSE file.

import SwiftUI
import AppKit
import QuickLookThumbnailing
import QuickLook
import Quartz

private final class QuickLookDataSource: NSObject, QLPreviewPanelDataSource {
    let url: URL
    init(url: URL) { self.url = url }
    func numberOfPreviewItems(in panel: QLPreviewPanel!) -> Int { 1 }
    func previewPanel(_ panel: QLPreviewPanel!, previewItemAt index: Int) -> QLPreviewItem! {
        url as NSURL
    }
}

struct FilePreviewPanel: View {
    let fileInfo: FileInfo
    @Binding var isVisible: Bool
    @State private var thumbnailImage: NSImage?
    @State private var thumbnailError = false
    @State private var quickLookDataSource: QuickLookDataSource?

    private let thumbnailSize = CGSize(width: 200, height: 200)

    var body: some View {
        HStack(spacing: 0) {
            Spacer(minLength: 0)
            GlassCard(padding: AppTheme.Spacing.large) {
                VStack(alignment: .leading, spacing: AppTheme.Spacing.large) {
                    header
                    thumbnailSection
                    metadataSection
                    pathSection
                    actionsSection
                }
                .frame(width: 320)
                .padding(AppTheme.Spacing.medium)
            }
            .transition(.move(edge: .trailing).combined(with: .opacity))
            .zIndex(1)
        }
        .background(
            Color.black.opacity(isVisible ? 0.2 : 0)
                .ignoresSafeArea()
                .onTapGesture { close() }
        )
        .onAppear { loadThumbnail() }
        .onChange(of: fileInfo.id) { _, _ in loadThumbnail() }
    }

    private var header: some View {
        HStack {
            Text(fileInfo.name)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(Color.dsPrimaryText)
                .lineLimit(1)
                .truncationMode(.middle)
            Spacer()
            Button {
                close()
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 20))
                    .foregroundStyle(Color.dsSecondaryText)
                    .symbolRenderingMode(.hierarchical)
            }
            .buttonStyle(.plain)
        }
    }

    private var thumbnailSection: some View {
        Group {
            if let img = thumbnailImage {
                Image(nsImage: img)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(maxWidth: .infinity)
                    .frame(height: 200)
                    .clipShape(RoundedRectangle(cornerRadius: AppTheme.CornerRadius.medium, style: .continuous))
            } else if thumbnailError || !isImageOrVideo {
                Image(nsImage: NSWorkspace.shared.icon(forFile: fileInfo.url.path))
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(maxWidth: .infinity)
                    .frame(height: 200)
                    .clipShape(RoundedRectangle(cornerRadius: AppTheme.CornerRadius.medium, style: .continuous))
            } else {
                ProgressView()
                    .frame(maxWidth: .infinity)
                    .frame(height: 200)
            }
        }
    }

    private var metadataSection: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.small) {
            metadataRow("Extension", (fileInfo.name as NSString).pathExtension)
            metadataRow("Size", fileInfo.formattedSize)
            metadataRow("Created", formatDate(fileInfo.creationDate))
            metadataRow("Modified", formatDate(fileInfo.modificationDate))
        }
    }

    private func metadataRow(_ label: String, _ value: String) -> some View {
        HStack(alignment: .top) {
            Text("\(label):")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(Color.dsSecondaryText)
                .frame(width: 70, alignment: .leading)
            Text(value)
                .font(.system(size: 12))
                .foregroundStyle(Color.dsPrimaryText)
            Spacer()
        }
    }

    private var pathSection: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.small) {
            Text("Path")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(Color.dsSecondaryText)
            Text(fileInfo.url.path)
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(Color.dsPrimaryText)
                .lineLimit(3)
                .truncationMode(.middle)
                .textSelection(.enabled)
        }
    }

    private var actionsSection: some View {
        HStack(spacing: AppTheme.Spacing.medium) {
            GlassButton("Open in Finder", icon: "folder", style: .secondary) {
                NSWorkspace.shared.selectFile(fileInfo.url.path, inFileViewerRootedAtPath: fileInfo.url.deletingLastPathComponent().path)
            }
            GlassButton("Quick Look", icon: "eye", style: .secondary) {
                openQuickLook()
            }
        }
    }

    private var isImageOrVideo: Bool {
        let ext = (fileInfo.name as NSString).pathExtension.lowercased()
        let imageExts: Set<String> = ["jpg", "jpeg", "png", "heic", "heif", "gif", "bmp", "tiff", "webp"]
        let videoExts: Set<String> = ["mp4", "mov", "avi", "mkv", "m4v"]
        return imageExts.contains(ext) || videoExts.contains(ext)
    }

    private func loadThumbnail() {
        thumbnailImage = nil
        thumbnailError = false
        guard isImageOrVideo else {
            thumbnailError = true
            return
        }
        let request = QLThumbnailGenerator.Request(
            fileAt: fileInfo.url,
            size: thumbnailSize,
            scale: 2.0,
            representationTypes: .thumbnail
        )
        QLThumbnailGenerator.shared.generateBestRepresentation(for: request) { thumbnail, error in
            DispatchQueue.main.async {
                if let thumb = thumbnail {
                    thumbnailImage = thumb.nsImage
                } else {
                    thumbnailError = true
                }
            }
        }
    }

    private func formatDate(_ date: Date) -> String {
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = .short
        return f.string(from: date)
    }

    private func close() {
        withAnimation(AppTheme.Animation.respectingReducedMotion(AppTheme.Animation.springSnappy)) {
            isVisible = false
        }
    }

    private func openQuickLook() {
        guard let panel = QLPreviewPanel.shared() else { return }
        let dataSource = QuickLookDataSource(url: fileInfo.url)
        quickLookDataSource = dataSource
        panel.dataSource = dataSource
        panel.reloadData()
        if panel.isVisible {
            panel.orderOut(nil)
        } else {
            panel.makeKeyAndOrderFront(nil)
        }
    }
}
