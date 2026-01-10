#!/usr/bin/env swift

import Cocoa
import SwiftUI

struct AppIconView: View {
    let size: CGFloat

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: size * 0.22, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [Color.black, Color.black.opacity(0.85)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )

            Image(systemName: "bolt.fill")
                .font(.system(size: size * 0.5, weight: .semibold))
                .foregroundStyle(.yellow.gradient)
        }
        .frame(width: size, height: size)
    }
}

@MainActor
func renderIcon(size: Int) -> NSImage {
    let view = AppIconView(size: CGFloat(size))
    let renderer = ImageRenderer(content: view)
    renderer.scale = 1.0  // Use 1x scale, generate actual pixel sizes

    if let cgImage = renderer.cgImage {
        return NSImage(cgImage: cgImage, size: NSSize(width: size, height: size))
    }
    return NSImage()
}

@MainActor
func saveIcon(pixelSize: Int, filename: String, directory: String) {
    let image = renderIcon(size: pixelSize)

    guard let tiffData = image.tiffRepresentation,
          let bitmap = NSBitmapImageRep(data: tiffData),
          let pngData = bitmap.representation(using: .png, properties: [:]) else {
        print("Failed to create PNG for \(filename)")
        return
    }

    let url = URL(fileURLWithPath: directory).appendingPathComponent(filename)
    do {
        try pngData.write(to: url)
        print("Saved: \(filename) (\(pixelSize)x\(pixelSize) pixels)")
    } catch {
        print("Error saving \(filename): \(error)")
    }
}

@MainActor
func main() {
    let dir = FileManager.default.currentDirectoryPath + "/Watt/Resources/Assets.xcassets/AppIcon.appiconset"

    // macOS app icon sizes (actual pixel dimensions)
    // 1x sizes
    saveIcon(pixelSize: 16, filename: "AppIcon_16x16.png", directory: dir)
    saveIcon(pixelSize: 32, filename: "AppIcon_32x32.png", directory: dir)
    saveIcon(pixelSize: 128, filename: "AppIcon_128x128.png", directory: dir)
    saveIcon(pixelSize: 256, filename: "AppIcon_256x256.png", directory: dir)
    saveIcon(pixelSize: 512, filename: "AppIcon_512x512.png", directory: dir)

    // 2x sizes (actual pixel dimensions for @2x)
    saveIcon(pixelSize: 32, filename: "AppIcon_16x16@2x.png", directory: dir)   // 16@2x = 32px
    saveIcon(pixelSize: 64, filename: "AppIcon_32x32@2x.png", directory: dir)   // 32@2x = 64px
    saveIcon(pixelSize: 256, filename: "AppIcon_128x128@2x.png", directory: dir) // 128@2x = 256px
    saveIcon(pixelSize: 512, filename: "AppIcon_256x256@2x.png", directory: dir) // 256@2x = 512px
    saveIcon(pixelSize: 1024, filename: "AppIcon_512x512@2x.png", directory: dir) // 512@2x = 1024px

    // Also save icon.png for README
    saveIcon(pixelSize: 128, filename: "icon.png", directory: FileManager.default.currentDirectoryPath)

    print("\nDone! Icons regenerated with correct sizes.")
}

DispatchQueue.main.async {
    main()
    exit(0)
}

RunLoop.main.run()
