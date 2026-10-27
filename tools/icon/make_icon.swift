// Renders the AppIcon set. Run: swift tools/icon/make_icon.swift
import AppKit
let outDir = "Sources/AmazonMusic/Resources/Assets.xcassets/AppIcon.appiconset"
let cs = CGColorSpace(name: CGColorSpace.sRGB)!
func rgb(_ r: CGFloat,_ g: CGFloat,_ b: CGFloat,_ a: CGFloat = 1) -> CGColor { CGColor(colorSpace: cs, components: [r,g,b,a])! }

func squircle(_ r: CGRect) -> CGPath {
  let p = CGMutablePath(); let n: CGFloat = 5; let steps = 360
  for i in 0...steps {
    let t = CGFloat(i)/CGFloat(steps)*2 * .pi
    let c = cos(t), s = sin(t)
    let x = r.midX + r.width/2 * (c < 0 ? -1 : 1) * pow(abs(c), 2/n)
    let y = r.midY + r.height/2 * (s < 0 ? -1 : 1) * pow(abs(s), 2/n)
    i == 0 ? p.move(to: CGPoint(x: x, y: y)) : p.addLine(to: CGPoint(x: x, y: y))
  }
  p.closeSubpath(); return p
}

func notePath() -> CGPath {
  // beamed double eighth note, 1024 space (y up)
  let p = CGMutablePath()
  let sw: CGFloat = 56
  let h1 = CGPoint(x: 330, y: 300), h2 = CGPoint(x: 640, y: 250)
  let s1 = h1.x + 72, s2 = h2.x + 72     // stem centres
  let t1: CGFloat = 740, t2: CGFloat = 690 // stem tops (slanted beam)
  p.addRect(CGRect(x: s1-sw/2, y: h1.y, width: sw, height: t1-h1.y))
  p.addRect(CGRect(x: s2-sw/2, y: h2.y, width: sw, height: t2-h2.y))
  p.move(to: CGPoint(x: s1-sw/2, y: t1-110))
  p.addLine(to: CGPoint(x: s2+sw/2, y: t2-110))
  p.addLine(to: CGPoint(x: s2+sw/2, y: t2+10))
  p.addLine(to: CGPoint(x: s1-sw/2, y: t1+10))
  p.closeSubpath()
  for c in [h1, h2] {
    var t = CGAffineTransform(translationX: c.x, y: c.y).rotated(by: 0.35)
    p.addPath(CGPath(ellipseIn: CGRect(x: -100, y: -72, width: 200, height: 144), transform: &t))
  }
  // Fit: scale so glyph width = 55% of tile (824), centre bbox on tile centre (512,512).
  let bb = p.boundingBoxOfPath
  let k = (824 * 0.55) / bb.width
  var m = CGAffineTransform(translationX: 512, y: 512).scaledBy(x: k, y: k).translatedBy(x: -bb.midX, y: -bb.midY)
  return p.copy(using: &m)!
}

func render(_ px: Int) -> Data {
  let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: px, pixelsHigh: px, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
  let ctx = NSGraphicsContext(bitmapImageRep: rep)!
  NSGraphicsContext.current = ctx
  let g = ctx.cgContext
  g.scaleBy(x: CGFloat(px)/1024, y: CGFloat(px)/1024)
  g.interpolationQuality = .high
  let shape = squircle(CGRect(x: 100, y: 100, width: 824, height: 824))
  // drop shadow
  g.saveGState()
  g.setShadow(offset: CGSize(width: 0, height: -12), blur: 28, color: rgb(0,0,0,0.45))
  g.addPath(shape); g.setFillColor(rgb(0.04,0.08,0.2)); g.fillPath()
  g.restoreGState()
  // gradient
  g.saveGState(); g.addPath(shape); g.clip()
  let grad = CGGradient(colorsSpace: cs, colors: [rgb(0.03,0.07,0.22), rgb(0.05,0.30,0.55), rgb(0.1,0.85,0.9)] as CFArray, locations: [0,0.55,1])!
  g.drawLinearGradient(grad, start: CGPoint(x: 140, y: 924), end: CGPoint(x: 884, y: 100), options: [])
  // top highlight
  let hl = CGGradient(colorsSpace: cs, colors: [rgb(1,1,1,0.12), rgb(1,1,1,0)] as CFArray, locations: [0,1])!
  g.drawLinearGradient(hl, start: CGPoint(x: 512, y: 924), end: CGPoint(x: 512, y: 600), options: [])
  // note with soft shadow
  g.setShadow(offset: CGSize(width: 0, height: -6), blur: 16, color: rgb(0,0.05,0.2,0.5))
  g.addPath(notePath()); g.setFillColor(rgb(1,1,1)); g.fillPath()
  g.restoreGState()
  // rim
  g.addPath(shape); g.setStrokeColor(rgb(1,1,1,0.18)); g.setLineWidth(3); g.strokePath()
  NSGraphicsContext.current = nil
  return rep.representation(using: .png, properties: [:])!
}

var images: [String] = []
for base in [16,32,128,256,512] { for s in [1,2] {
  let name = "icon_\(base)x\(base)\(s == 2 ? "@2x" : "").png"
  try! render(base*s).write(to: URL(fileURLWithPath: "\(outDir)/\(name)"))
  images.append("{\"filename\":\"\(name)\",\"idiom\":\"mac\",\"scale\":\"\(s)x\",\"size\":\"\(base)x\(base)\"}")
}}
try! "{\"images\":[\(images.joined(separator: ","))],\"info\":{\"version\":1,\"author\":\"xcode\"}}\n".write(toFile: "\(outDir)/Contents.json", atomically: true, encoding: .utf8)
try! render(1024).write(to: URL(fileURLWithPath: "tools/icon/master_1024.png"))
