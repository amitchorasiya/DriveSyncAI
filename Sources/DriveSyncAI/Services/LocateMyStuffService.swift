// Copyright 2026 Amit Chorasiya. All rights reserved.
// Licensed under the Business Source License 1.1. See LICENSE file.

import Foundation
import Vision
import AppKit
import SwiftUI

@MainActor
final class LocateMyStuffService: ObservableObject {
    @Published var items: [LocateItem] = []
    @Published var isProcessing = false
    @Published var lastError: String?
    
    static let storageDir: URL = {
        let home = FileManager.default.homeDirectoryForCurrentUser
        return home.appendingPathComponent(".drivesyncai/locate_stuff", isDirectory: true)
    }()
    
    private var photosDir: URL {
        Self.storageDir.appendingPathComponent("photos", isDirectory: true)
    }
    
    private var indexFile: URL {
        Self.storageDir.appendingPathComponent("index.json")
    }
    
    init() {
        createDirectories()
        loadIndex()
    }
    
    private func createDirectories() {
        do {
            try FileManager.default.createDirectory(at: photosDir, withIntermediateDirectories: true)
        } catch {
            print("Failed to create locate_stuff directories: \(error)")
        }
    }
    
    private func loadIndex() {
        guard let data = try? Data(contentsOf: indexFile),
              let loaded = try? JSONDecoder().decode([LocateItem].self, from: data) else {
            return
        }
        items = loaded.sorted { $0.capturedAt > $1.capturedAt }
    }
    
    private func saveIndex() {
        do {
            let data = try JSONEncoder().encode(items)
            try data.write(to: indexFile)
        } catch {
            print("Failed to save index: \(error)")
        }
    }
    
    func addItem(image: NSImage, place: String?) async {
        isProcessing = true
        defer { isProcessing = false }
        
        // 1. Run Vision to get labels
        let labels = await classifyImage(image)
        
        // 2. Save image to disk
        let id = UUID()
        let filename = "\(id.uuidString).jpg"
        let fileURL = photosDir.appendingPathComponent(filename)
        
        guard let tiffData = image.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiffData),
              let jpegData = bitmap.representation(using: .jpeg, properties: [.compressionFactor: 0.8]) else {
            lastError = "Failed to process image data"
            return
        }
        
        do {
            try jpegData.write(to: fileURL)
            
            // 3. Update index
            let newItem = LocateItem(
                id: id,
                imagePath: filename,
                labels: labels,
                place: place?.trimmingCharacters(in: .whitespacesAndNewlines),
                capturedAt: Date()
            )
            
            items.insert(newItem, at: 0)
            saveIndex()
            
        } catch {
            lastError = "Failed to save image: \(error.localizedDescription)"
        }
    }
    
    func search(query: String) -> [LocateItem] {
        let terms = query.lowercased()
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty && $0.count > 2 } // Skip short words like "is", "my"
            .filter { !["where", "what", "find", "show", "seen"].contains($0) }
            
        guard !terms.isEmpty else { return items }
        
        return items.filter { item in
            // Match against labels
            if item.labels.contains(where: { label in
                terms.contains(where: { label.lowercased().contains($0) })
            }) {
                return true
            }
            
            // Match against place
            if let place = item.place, terms.contains(where: { place.lowercased().contains($0) }) {
                return true
            }
            
            return false
        }
    }
    
    func deleteItem(_ item: LocateItem) {
        do {
            try FileManager.default.removeItem(at: item.fullImagePath)
            items.removeAll { $0.id == item.id }
            saveIndex()
        } catch {
            lastError = "Failed to delete item: \(error.localizedDescription)"
        }
    }
    
    // MARK: - Vision
    
    private func classifyImage(_ image: NSImage) async -> [String] {
        guard let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            return []
        }
        
        return await withCheckedContinuation { continuation in
            let request = VNClassifyImageRequest { request, error in
                guard let observations = request.results as? [VNClassificationObservation] else {
                    continuation.resume(returning: [])
                    return
                }
                
                // Filter confident results
                let labels = observations
                    .filter { $0.confidence > 0.7 }
                    .prefix(10)
                    .map { $0.identifier }
                
                continuation.resume(returning: Array(labels))
            }
            
            let handler = VNImageRequestHandler(cgImage: cgImage)
            try? handler.perform([request])
        }
    }
}
