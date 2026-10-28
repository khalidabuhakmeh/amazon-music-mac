// Renders the AppIcon set ("Equalizer": glowing cyan→violet bars on a dark indigo squircle).
// Run from the repo root: swift tools/icon/make_icon.swift
// Draws a 1024px master, then downsamples it for every slot (keeps glow/shadow consistent at all sizes).
import AppKit

let outDir = "Sources/AmazonMusic/Resources/Assets.xcassets/AppIcon.appiconset"
let cs = CGColorSpace(name: CGColorSpace.sRGB)!

func rgb(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat, _ a: CGFloat = 1) -> CGColor { CGColor(colorSpace: cs, components: [r, g, b, a])! }
func hex(_ h: Int, _ a: CGFloat = 1) -> CGColor {
  rgb(CGFloat((h >> 16) & 255) / 255, CGFloat((h >> 8) & 255) / 255, CGFloat(h & 255) / 255, a)
}
func P(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: x, y: y) }
func grad(_ c: [CGColor], _ l: [CGFloat]? = nil) -> CGGradient { CGGradient(colorsSpace: cs, colors: c as CFArray, locations: l)! }
func lin(_ g: CGContext, _ gr: CGGradient, _ a: CGPoint, _ b: CGPoint) {
  g.drawLinearGradient(gr, start: a, end: b, options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
}
func rad(_ g: CGContext, _ gr: CGGradient, _ c: CGPoint, _ r: CGFloat) {
  g.drawRadialGradient(gr, startCenter: c, startRadius: 0, endCenter: c, endRadius: r, options: [.drawsAfterEndLocation])
}
func fillPath(_ g: CGContext, _ p: CGPath, _ c: CGColor) { g.addPath(p); g.setFillColor(c); g.fillPath() }
func clipFill(_ g: CGContext, _ p: CGPath, _ draw: () -> Void) { g.saveGState(); g.addPath(p); g.clip(); draw(); g.restoreGState() }
func glow(_ g: CGContext, _ c: CGColor, _ blur: CGFloat, _ dy: CGFloat = 0) { g.setShadow(offset: CGSize(width: 0, height: dy), blur: blur, color: c) }
func rrect(_ r: CGRect, _ radius: CGFloat) -> CGPath { CGPath(roundedRect: r, cornerWidth: radius, cornerHeight: radius, transform: nil) }
func circle(_ c: CGPoint, _ r: CGFloat) -> CGPath { CGPath(ellipseIn: CGRect(x: c.x - r, y: c.y - r, width: 2 * r, height: 2 * r), transform: nil) }

/// Continuous-corner tile (superellipse, n = 5), macOS icon grid: 824px tile centred in 1024.
func squircle(_ r: CGRect) -> CGPath {
  let p = CGMutablePath(); let n: CGFloat = 5; let steps = 360
  for i in 0...steps {
    let t = CGFloat(i) / CGFloat(steps) * 2 * .pi
    let c = cos(t), s = sin(t)
    let x = r.midX + r.width / 2 * (c < 0 ? -1 : 1) * pow(abs(c), 2 / n)
    let y = r.midY + r.height / 2 * (s < 0 ? -1 : 1) * pow(abs(s), 2 / n)
    i == 0 ? p.move(to: P(x, y)) : p.addLine(to: P(x, y))
  }
  p.closeSubpath(); return p
}

/// Tile contents: dark indigo background with a violet bloom, seven rounded equalizer bars with a cyan glow,
/// a cyan→violet→magenta fill and a left-edge gloss per bar, plus a row of faint "reflection" dots.
func equalizer(_ g: CGContext) {
  lin(g, grad([hex(0x161B4A), hex(0x070A1E)]), P(512, 924), P(512, 100))
  rad(g, grad([hex(0x7B3FF2, 0.35), hex(0x7B3FF2, 0)]), P(512, 470), 460)
  let heights: [CGFloat] = [190, 330, 500, 390, 560, 300, 170]
  let w: CGFloat = 70, gap: CGFloat = 28
  let x0 = 512 - (7 * w + 6 * gap) / 2
  let bars = CGMutablePath()
  for (i, h) in heights.enumerated() {
    bars.addPath(rrect(CGRect(x: x0 + CGFloat(i) * (w + gap), y: 512 - h / 2, width: w, height: h), w / 2))
  }
  g.saveGState(); glow(g, hex(0x25D1DA, 0.55), 50); fillPath(g, bars, hex(0x25D1DA)); g.restoreGState()
  clipFill(g, bars) {
    lin(g, grad([hex(0x2BE6E6), hex(0x25D1DA), hex(0x7A4CF5), hex(0xC040E0)], [0, 0.35, 0.75, 1]), P(512, 790), P(512, 240))
    for i in 0..<7 {
      let bx = x0 + CGFloat(i) * (w + gap)
      lin(g, grad([rgb(1, 1, 1, 0.28), rgb(1, 1, 1, 0)]), P(bx, 512), P(bx + w * 0.55, 512))
    }
  }
  for i in 0..<7 { fillPath(g, circle(P(x0 + CGFloat(i) * (w + gap) + w / 2, 200), 7), hex(0x25D1DA, 0.5)) }
}

func master() -> CGImage {
  let g = CGContext(data: nil, width: 1024, height: 1024, bitsPerComponent: 8, bytesPerRow: 0, space: cs,
                    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
  g.interpolationQuality = .high; g.setShouldAntialias(true)
  let shape = squircle(CGRect(x: 100, y: 100, width: 824, height: 824))
  // drop shadow under the tile
  g.saveGState(); glow(g, rgb(0, 0, 0, 0.5), 28, -12); fillPath(g, shape, rgb(0.05, 0.05, 0.1)); g.restoreGState()
  g.saveGState(); g.addPath(shape); g.clip()
  equalizer(g)
  lin(g, grad([rgb(1, 1, 1, 0.16), rgb(1, 1, 1, 0)]), P(512, 924), P(512, 640)) // top highlight
  lin(g, grad([rgb(0, 0, 0, 0), rgb(0, 0, 0, 0.22)]), P(512, 300), P(512, 100)) // bottom depth
  g.restoreGState()
  // rim: light at the top, dark at the bottom
  g.saveGState(); g.addPath(shape.copy(strokingWithWidth: 4, lineCap: .butt, lineJoin: .round, miterLimit: 10)); g.clip()
  lin(g, grad([rgb(1, 1, 1, 0.45), rgb(1, 1, 1, 0.05), rgb(0, 0, 0, 0.25)], [0, 0.5, 1]), P(512, 924), P(512, 100))
  g.restoreGState()
  return g.makeImage()!
}

func scaled(_ img: CGImage, _ px: Int) -> CGImage {
  if px == img.width { return img }
  let g = CGContext(data: nil, width: px, height: px, bitsPerComponent: 8, bytesPerRow: 0, space: cs,
                    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
  g.interpolationQuality = .high
  g.draw(img, in: CGRect(x: 0, y: 0, width: px, height: px))
  return g.makeImage()!
}
func png(_ img: CGImage) -> Data { NSBitmapImageRep(cgImage: img).representation(using: .png, properties: [:])! }

let big = master()
var images: [String] = []
for base in [16, 32, 128, 256, 512] { for s in [1, 2] {
  let name = "icon_\(base)x\(base)\(s == 2 ? "@2x" : "").png"
  try! png(scaled(big, base * s)).write(to: URL(fileURLWithPath: "\(outDir)/\(name)"))
  images.append("{\"filename\":\"\(name)\",\"idiom\":\"mac\",\"scale\":\"\(s)x\",\"size\":\"\(base)x\(base)\"}")
}}
try! "{\"images\":[\(images.joined(separator: ","))],\"info\":{\"version\":1,\"author\":\"xcode\"}}\n"
  .write(toFile: "\(outDir)/Contents.json", atomically: true, encoding: .utf8)
try! png(big).write(to: URL(fileURLWithPath: "tools/icon/master_1024.png"))
try! png(scaled(big, 256)).write(to: URL(fileURLWithPath: "docs/icon.png"))
