// Renders the PocketAlpaca logo as a square PNG.
//   swift Scripts/make_logo.swift Assets/logo-256.png 256      (Alpaca Connect logo)
//   swift Scripts/make_logo.swift PocketAlpaca/Assets.xcassets/AppIcon.appiconset/AppIcon.png 1024   (iOS app icon)
// The drawing is designed on a 256-pt canvas and scaled; iOS masks its own corners,
// so the 1024 icon is drawn square-cornered.
import Foundation
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

let out = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "logo-256.png"
let px = CommandLine.arguments.count > 2 ? Int(CommandLine.arguments[2]) ?? 256 : 256
let size = 256                      // design canvas in points
let isAppIcon = px >= 512           // iOS applies its own corner mask
let cs = CGColorSpaceCreateDeviceRGB()
guard let ctx = CGContext(data: nil, width: px, height: px, bitsPerComponent: 8, bytesPerRow: 0,
                          space: cs, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { exit(1) }
ctx.scaleBy(x: CGFloat(px) / CGFloat(size), y: CGFloat(px) / CGFloat(size))

// Background: deep green square, rounded only for the standalone logo.
let radius: CGFloat = isAppIcon ? 0 : 56
let bg = CGPath(roundedRect: CGRect(x: 0, y: 0, width: size, height: size), cornerWidth: radius, cornerHeight: radius, transform: nil)
ctx.addPath(bg)
ctx.setFillColor(CGColor(red: 0.06, green: 0.36, blue: 0.24, alpha: 1))
ctx.fillPath()

// Faint grid lines.
ctx.setStrokeColor(CGColor(red: 1, green: 1, blue: 1, alpha: 0.10))
ctx.setLineWidth(2)
for y in stride(from: 56, through: 200, by: 48) {
    ctx.move(to: CGPoint(x: 40, y: y)); ctx.addLine(to: CGPoint(x: 216, y: y))
}
ctx.strokePath()

// Equity line: rising with a dip, like a portfolio chart.
let pts: [CGPoint] = [CGPoint(x: 44, y: 84), CGPoint(x: 84, y: 118), CGPoint(x: 116, y: 100),
                      CGPoint(x: 148, y: 150), CGPoint(x: 180, y: 136), CGPoint(x: 212, y: 190)]
// Area fill under the line.
ctx.move(to: CGPoint(x: pts[0].x, y: 52))
for p in pts { ctx.addLine(to: p) }
ctx.addLine(to: CGPoint(x: pts.last!.x, y: 52))
ctx.closePath()
ctx.setFillColor(CGColor(red: 0.55, green: 0.95, blue: 0.70, alpha: 0.22))
ctx.fillPath()

ctx.setStrokeColor(CGColor(red: 0.62, green: 0.98, blue: 0.75, alpha: 1))
ctx.setLineWidth(14)
ctx.setLineCap(.round)
ctx.setLineJoin(.round)
ctx.move(to: pts[0])
for p in pts.dropFirst() { ctx.addLine(to: p) }
ctx.strokePath()

// End-point dot.
ctx.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
ctx.fillEllipse(in: CGRect(x: pts.last!.x - 13, y: pts.last!.y - 13, width: 26, height: 26))

guard let img = ctx.makeImage(),
      let dest = CGImageDestinationCreateWithURL(URL(fileURLWithPath: out) as CFURL, UTType.png.identifier as CFString, 1, nil)
else { exit(2) }
CGImageDestinationAddImage(dest, img, nil)
guard CGImageDestinationFinalize(dest) else { exit(3) }
print("wrote \(out) \(px)x\(px)")
