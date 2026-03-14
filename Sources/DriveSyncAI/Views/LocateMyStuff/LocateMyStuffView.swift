// Copyright 2026 Amit Chorasiya. All rights reserved.
// Licensed under the Business Source License 1.1. See LICENSE file.

import SwiftUI
import PhotosUI

struct LocateMyStuffView: View {
    @StateObject private var service = LocateMyStuffService()
    @State private var searchText = ""
    @State private var showCapture = false
    @State private var selectedItem: PhotosPickerItem?
    @State private var capturedImage: NSImage?
    @State private var placeName = ""
    @State private var isSaving = false
    
    var filteredItems: [LocateItem] {
        if searchText.isEmpty {
            return service.items
        }
        return service.search(query: searchText)
    }
    
    var body: some View {
        VStack(spacing: 0) {
            header
            
            if service.items.isEmpty {
                emptyState
            } else {
                content
            }
        }
        .background(Color.dsBackground)
        .sheet(isPresented: $showCapture) {
            captureSheet
        }
        .onChange(of: selectedItem) { _, newItem in
            Task {
                if let data = try? await newItem?.loadTransferable(type: Data.self),
                   let image = NSImage(data: data) {
                    capturedImage = image
                    showCapture = true
                }
            }
        }
    }
    
    private var header: some View {
        VStack(spacing: AppTheme.Spacing.medium) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Locate My Stuff")
                        .font(.title2.bold())
                        .foregroundStyle(Color.dsPrimaryText)
                    Text("Take photos of your items to find them later")
                        .font(.caption)
                        .foregroundStyle(Color.dsSecondaryText)
                }
                
                Spacer()
                
                PhotosPicker(selection: $selectedItem, matching: .images) {
                    Label("Add Photo", systemImage: "camera")
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(Color.accentColor)
                        .foregroundStyle(.white)
                        .cornerRadius(8)
                }
            }
            
            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(Color.dsSecondaryText)
                TextField("Where is my...", text: $searchText)
                    .textFieldStyle(.plain)
                    .font(.body)
                if !searchText.isEmpty {
                    Button {
                        searchText = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(Color.dsSecondaryText)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(10)
            .background(Color.dsSecondaryBackground)
            .cornerRadius(8)
        }
        .padding(AppTheme.Spacing.xl)
        .background(Color.dsBackground)
        .overlay(alignment: .bottom) {
            Divider()
        }
    }
    
    private var emptyState: some View {
        VStack(spacing: 20) {
            Spacer()
            Image(systemName: "location.magnifyingglass")
                .font(.system(size: 48))
                .foregroundStyle(Color.dsTertiaryText)
            Text("No items tracked yet")
                .font(.title3.bold())
                .foregroundStyle(Color.dsSecondaryText)
            Text("Take a photo of your keys, wallet, or other items\nto remember where you left them.")
                .multilineTextAlignment(.center)
                .foregroundStyle(Color.dsTertiaryText)
            Spacer()
        }
    }
    
    private var content: some View {
        ScrollView {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 200, maximum: 300), spacing: 16)], spacing: 16) {
                ForEach(filteredItems) { item in
                    ItemCard(item: item) {
                        service.deleteItem(item)
                    }
                }
            }
            .padding(AppTheme.Spacing.xl)
        }
    }
    
    private var captureSheet: some View {
        VStack(spacing: 20) {
            Text("Add Item")
                .font(.headline)
            
            if let image = capturedImage {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(height: 300)
                    .cornerRadius(8)
            }
            
            TextField("Where is this? (e.g. Desk, Living Room)", text: $placeName)
                .textFieldStyle(.roundedBorder)
                .frame(width: 300)
            
            HStack {
                Button("Cancel") {
                    showCapture = false
                    capturedImage = nil
                    placeName = ""
                    selectedItem = nil
                }
                .keyboardShortcut(.cancelAction)
                
                Button("Save") {
                    guard let image = capturedImage else { return }
                    isSaving = true
                    Task {
                        await service.addItem(image: image, place: placeName.isEmpty ? nil : placeName)
                        isSaving = false
                        showCapture = false
                        capturedImage = nil
                        placeName = ""
                        selectedItem = nil
                    }
                }
                .keyboardShortcut(.defaultAction)
                .disabled(isSaving)
            }
        }
        .padding()
        .frame(width: 400, height: 500)
    }
}

struct ItemCard: View {
    let item: LocateItem
    let onDelete: () -> Void
    @State private var isHovering = false
    
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            AsyncImage(url: item.fullImagePath) { image in
                image
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } placeholder: {
                Color.dsSecondaryBackground
            }
            .frame(height: 160)
            .clipped()
            .overlay(alignment: .topTrailing) {
                if isHovering {
                    Button(action: onDelete) {
                        Image(systemName: "trash.circle.fill")
                            .font(.title2)
                            .foregroundStyle(.white)
                            .shadow(radius: 2)
                    }
                    .buttonStyle(.plain)
                    .padding(8)
                }
            }
            
            VStack(alignment: .leading, spacing: 4) {
                if let place = item.place {
                    Text(place)
                        .font(.headline)
                        .foregroundStyle(Color.dsPrimaryText)
                } else {
                    Text("No location")
                        .font(.headline)
                        .foregroundStyle(Color.dsTertiaryText)
                }
                
                Text(item.capturedAt.formatted(date: .abbreviated, time: .shortened))
                    .font(.caption)
                    .foregroundStyle(Color.dsSecondaryText)
                
                if !item.labels.isEmpty {
                    Text(item.labels.prefix(3).joined(separator: ", "))
                        .font(.caption2)
                        .foregroundStyle(Color.dsTertiaryText)
                        .lineLimit(1)
                }
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.dsSecondaryBackground)
        }
        .cornerRadius(12)
        .shadow(color: Color.black.opacity(0.1), radius: 4, x: 0, y: 2)
        .onHover { isHovering = $0 }
    }
}
