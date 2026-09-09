// Generates Assets/Sweep.icns — run: swift scripts/gen-icon.swift
// Big Sur-style icon: teal gradient squircle on the standard transparent
// margin, white "sparkles" glyph (Sweep = tidy + a little magic, never scary).
import AppKit

let canvas: CGFloat = 1024
let margin: CGFloat = 100 // Apple's grid: content ~824pt inside 1024
let contentRect = CGRect(x: margin, y: margin,
                         width: canvas - margin * 2, height: canvas - margin * 2)

func drawIcon(size: CGFloat) -> NSImage {
    let image = NSImage(size: NSSize(width: size, height: size))
    image.lockFocus()
    defer { image.unlockFocus() }
    let scale = size / canvas
    let rect = CGRect(x: contentRect.minX * scale, y: contentRect.minY * scale,
                      width: contentRect.width * scale, height: contentRect.height * scale)
    let radius = rect.width * 0.2237 // macOS squircle corner ratio
    let path = NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius)

    // Soft drop shadow like system icons.
    NSGraphicsContext.current?.saveGraphicsState()
    let shadow = NSShadow()
    shadow.shadowColor = NSColor.black.withAlphaComponent(0.3)
    shadow.shadowBlurRadius = 10 * scale
    shadow.shadowOffset = NSSize(width: 0, height: -6 * scale)
    shadow.set()
    NSColor(calibratedRed: 0.06, green: 0.55, blue: 0.53, alpha: 1).setFill()
    path.fill()
    NSGraphicsContext.current?.restoreGraphicsState()

    // Vertical teal gradient (Theme.accent family).
    let gradient = NSGradient(
        starting: NSColor(calibratedRed: 0.10, green: 0.74, blue: 0.71, alpha: 1),
        ending: NSColor(calibratedRed: 0.02, green: 0.45, blue: 0.47, alpha: 1)
    )!
    gradient.draw(in: path, angle: -90)

    // White broom glyph, tilted like mid-sweep, plus two small sparkles.
    if let ctx = NSGraphicsContext.current?.cgContext {
        ctx.saveGState()
        // Local space: origin at icon center, 824-unit content square, tilted.
        ctx.translateBy(x: rect.midX, y: rect.midY)
        ctx.rotate(by: -0.48) // ~27° — sweeping, not falling over
        let unit = rect.width / 824.0
        ctx.scaleBy(x: unit, y: unit)
        NSColor.white.withAlphaComponent(0.97).setFill()

        // Handle (top) → ferrule band → fanned bristle strips (bottom).
        NSBezierPath(roundedRect: NSRect(x: -26, y: 20, width: 52, height: 330),
                     xRadius: 26, yRadius: 26).fill()
        NSBezierPath(roundedRect: NSRect(x: -72, y: -60, width: 144, height: 84),
                     xRadius: 20, yRadius: 20).fill()
        let strips = 5
        let topHalf: CGFloat = 62, bottomHalf: CGFloat = 168
        let topGap: CGFloat = 9, bottomGap: CGFloat = 15
        let topW = (topHalf * 2 - topGap * CGFloat(strips - 1)) / CGFloat(strips)
        let bottomW = (bottomHalf * 2 - bottomGap * CGFloat(strips - 1)) / CGFloat(strips)
        for i in 0..<strips {
            let xt = -topHalf + CGFloat(i) * (topW + topGap)
            let xb = -bottomHalf + CGFloat(i) * (bottomW + bottomGap)
            let strip = NSBezierPath()
            strip.move(to: NSPoint(x: xt, y: -52))
            strip.line(to: NSPoint(x: xt + topW, y: -52))
            strip.line(to: NSPoint(x: xb + bottomW, y: -238))
            strip.line(to: NSPoint(x: xb, y: -238))
            strip.close()
            strip.fill()
        }
        ctx.restoreGState()
    }

    // Two sparkles beside the broom head — the "leaves the place tidy" wink.
    let config = NSImage.SymbolConfiguration(pointSize: rect.width * 0.14, weight: .semibold)
    if let symbol = NSImage(systemSymbolName: "sparkle", accessibilityDescription: nil)?
        .withSymbolConfiguration(config) {
        let tinted = NSImage(size: symbol.size)
        tinted.lockFocus()
        NSColor.white.set()
        let bounds = NSRect(origin: .zero, size: symbol.size)
        symbol.draw(in: bounds)
        bounds.fill(using: .sourceAtop)
        tinted.unlockFocus()
        let positions = [(0.70, 0.62, 1.0), (0.60, 0.76, 0.55)]
        for (fx, fy, scaleF) in positions {
            let w = tinted.size.width * scaleF, h = tinted.size.height * scaleF
            tinted.draw(in: NSRect(x: rect.minX + rect.width * fx - w / 2,
                                   y: rect.minY + rect.height * fy - h / 2,
                                   width: w, height: h),
                        from: .zero, operation: .sourceOver, fraction: 0.95)
        }
    }
    return image
}

func writePNG(_ image: NSImage, to url: URL, pixels: Int) {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels,
                               bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
                               isPlanar: false, colorSpaceName: .deviceRGB,
                               bytesPerRow: 0, bitsPerPixel: 0)!
    rep.size = NSSize(width: pixels, height: pixels)
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    image.draw(in: NSRect(x: 0, y: 0, width: pixels, height: pixels))
    NSGraphicsContext.restoreGraphicsState()
    try! rep.representation(using: .png, properties: [:])!.write(to: url)
}

let fm = FileManager.default
let root = URL(fileURLWithPath: fm.currentDirectoryPath)
let iconset = root.appendingPathComponent("Assets/Sweep.iconset")
try? fm.removeItem(at: iconset)
try! fm.createDirectory(at: iconset, withIntermediateDirectories: true)

for base in [16, 32, 128, 256, 512] {
    for scaleFactor in [1, 2] {
        let px = base * scaleFactor
        let name = scaleFactor == 1 ? "icon_\(base)x\(base).png" : "icon_\(base)x\(base)@2x.png"
        writePNG(drawIcon(size: CGFloat(px)), to: iconset.appendingPathComponent(name), pixels: px)
    }
}

let task = Process()
task.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
task.arguments = ["-c", "icns", iconset.path, "-o",
                  root.appendingPathComponent("Assets/Sweep.icns").path]
try! task.run()
task.waitUntilExit()
try? fm.removeItem(at: iconset)
print(task.terminationStatus == 0 ? "Wrote Assets/Sweep.icns" : "iconutil failed")
