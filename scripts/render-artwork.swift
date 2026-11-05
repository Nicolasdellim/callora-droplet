import AppKit
import Foundation

// Original vector geometry. This makes artwork, never screenshots of the application.
let root = URL(fileURLWithPath: CommandLine.arguments.dropFirst().first ?? FileManager.default.currentDirectoryPath)
func rounded(_ rect: NSRect, _ radius: CGFloat, _ color: NSColor) {
    color.setFill(); NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius).fill()
}
func symbol(_ concept: Int) {
    let silver = NSColor(calibratedWhite: 0.89, alpha: 1)
    let graphite = NSColor(calibratedWhite: 0.29, alpha: 1)
    if concept == 1 {
        rounded(NSRect(x: 206, y: 648, width: 612, height: 118), 59, graphite)
        rounded(NSRect(x: 276, y: 270, width: 472, height: 310), 74, silver)
        rounded(NSRect(x: 301, y: 296, width: 422, height: 258), 51, NSColor(calibratedWhite: 0.12, alpha: 1))
        rounded(NSRect(x: 455, y: 218, width: 114, height: 15), 7, NSColor(calibratedRed: 0.65, green: 0.78, blue: 0.88, alpha: 1))
    } else if concept == 2 {
        rounded(NSRect(x: 202, y: 412, width: 478, height: 310), 80, graphite)
        rounded(NSRect(x: 348, y: 270, width: 478, height: 310), 80, silver)
        rounded(NSRect(x: 378, y: 300, width: 418, height: 250), 54, NSColor(calibratedWhite: 0.1, alpha: 1))
    } else {
        rounded(NSRect(x: 215, y: 302, width: 440, height: 420), 100, silver)
        rounded(NSRect(x: 247, y: 334, width: 376, height: 356), 70, NSColor(calibratedWhite: 0.12, alpha: 1))
        let lens = NSBezierPath(); lens.move(to: .init(x: 700, y: 440)); lens.line(to: .init(x: 844, y: 370)); lens.line(to: .init(x: 844, y: 650)); lens.line(to: .init(x: 700, y: 580)); lens.close(); graphite.setFill(); lens.fill()
    }
}
func png(_ url: URL, size: Int, transparent: Bool = false, concept: Int = 1) throws {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState(); NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    let transform = NSAffineTransform(); transform.scale(by: CGFloat(size) / 1024); transform.concat()
    if !transparent {
        rounded(NSRect(x: 0, y: 0, width: 1024, height: 1024), 220, NSColor(calibratedWhite: 0.055, alpha: 1))
        rounded(NSRect(x: 32, y: 32, width: 960, height: 960), 197, NSColor(calibratedWhite: 0.10, alpha: 1))
    }
    symbol(concept)
    NSGraphicsContext.restoreGraphicsState()
    try rep.representation(using: .png, properties: [:])!.write(to: url)
}
let fm = FileManager.default
let design = root.appendingPathComponent("design")
try fm.createDirectory(at: design, withIntermediateDirectories: true)
for concept in 1...3 { try png(design.appendingPathComponent("concept-\(concept).png"), size: 1024, concept: concept) }
for size in [16, 32, 64, 128, 256, 512, 1024] { try png(design.appendingPathComponent("callora-\(size).png"), size: size) }
let assetDir = root.appendingPathComponent("Callora.icon/Assets")
try fm.createDirectory(at: assetDir, withIntermediateDirectories: true)
try png(assetDir.appendingPathComponent("callora-mark.png"), size: 1024, transparent: true)
// Creator mark is an original neutral monogram, not an inferred personal portrait.
try png(root.appendingPathComponent("Assets/Creator.png"), size: 256, concept: 2)
print("Rendered three concepts and seven export sizes")
