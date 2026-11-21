// 畫夜市翻牌的 App 圖示：夜空背景 + 燈光暈染 + 一排小燈籠 + 微傾斜的紅色卡片寫「夜」。
// 用法：swift tools/make_icon.swift assets/icon
// 產生 icon.png（1024，iOS／一般用，不透明），以及 Android 自適應圖示的
// icon_background.png（背景）與 icon_foreground.png（前景，透明背景）。
import AppKit

let outDir = CommandLine.arguments[1]
let size: CGFloat = 1024

func color(_ hex: UInt32, _ alpha: CGFloat = 1) -> NSColor {
  NSColor(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255,
          blue: CGFloat(hex & 0xFF) / 255, alpha: alpha)
}

let night = color(0x16121F), lantern = color(0xE8432F), lanternEdge = color(0xF2735F)
let glow = color(0xFFB547), paper = color(0xFBF1DC)

/// 夜空背景：暖色光暈、掛線、小燈籠。
/// [k] 縮放比例、[oy] 往下偏移（AppKit 座標，y 往上），[lanternXs] 燈籠的 x（0～1）。
func drawBackground(_ ctx: CGContext, k: CGFloat, oy: CGFloat, lanternXs: [CGFloat]) {
  night.setFill()
  NSRect(x: 0, y: 0, width: size, height: size).fill()
  let ox = (size - size * k) / 2
  func p(_ x: CGFloat, _ y: CGFloat) -> NSPoint { NSPoint(x: ox + x * size * k, y: oy + y * size * k) }
  // 上方暖色燈光
  let g = NSGradient(colors: [glow.withAlphaComponent(0.38), glow.withAlphaComponent(0)])!
  g.draw(fromCenter: p(0.5, 0.98), radius: 0, toCenter: p(0.5, 0.98), radius: size * 0.75 * k, options: [])
  // 掛線與小燈籠（線一律畫到圖的左右兩邊）
  paper.withAlphaComponent(0.3).setStroke()
  let line = NSBezierPath()
  line.move(to: NSPoint(x: 0, y: p(0, 0.905).y))
  line.curve(to: NSPoint(x: size, y: p(0, 0.905).y), controlPoint1: NSPoint(x: size * 0.3, y: p(0, 0.86).y),
             controlPoint2: NSPoint(x: size * 0.7, y: p(0, 0.86).y))
  line.lineWidth = 5 * k
  line.stroke()
  for (i, x) in lanternXs.enumerated() {
    let edge = i == 0 || i == lanternXs.count - 1
    let c = NSPoint(x: size * x, y: p(0, edge ? 0.855 : 0.83).y)
    ctx.setShadow(offset: .zero, blur: 40 * k, color: lantern.withAlphaComponent(0.9).cgColor)
    lantern.setFill()
    NSBezierPath(ovalIn: NSRect(x: c.x - 34 * k, y: c.y - 44 * k, width: 68 * k, height: 84 * k)).fill()
    ctx.setShadow(offset: .zero, blur: 0, color: nil)
  }
}

/// 稍微傾斜的紅色卡片寫「夜」，[scale] 是相對 iOS 圖示的大小。
func drawCard(_ ctx: CGContext, center: NSPoint, scale: CGFloat) {
  let cardW = size * 0.5 * scale, cardH = cardW * 4 / 3
  ctx.saveGState()
  ctx.translateBy(x: center.x, y: center.y)
  ctx.rotate(by: -8 * .pi / 180)
  let card = NSRect(x: -cardW / 2, y: -cardH / 2, width: cardW, height: cardH)
  ctx.setShadow(offset: CGSize(width: 0, height: -18 * scale), blur: 60 * scale, color: NSColor.black.withAlphaComponent(0.55).cgColor)
  lantern.setFill()
  NSBezierPath(roundedRect: card, xRadius: 46 * scale, yRadius: 46 * scale).fill()
  ctx.setShadow(offset: .zero, blur: 0, color: nil)
  lanternEdge.setStroke()
  let edge = NSBezierPath(roundedRect: card.insetBy(dx: 6 * scale, dy: 6 * scale), xRadius: 42 * scale, yRadius: 42 * scale)
  edge.lineWidth = 12 * scale
  edge.stroke()
  paper.withAlphaComponent(0.55).setStroke()
  let inner = NSBezierPath(roundedRect: card.insetBy(dx: 30 * scale, dy: 30 * scale), xRadius: 24 * scale, yRadius: 24 * scale)
  inner.lineWidth = 5 * scale
  inner.stroke()

  // 「夜」字
  let font = NSFont(name: "PingFangTC-Semibold", size: cardW * 0.62) ?? NSFont.boldSystemFont(ofSize: cardW * 0.62)
  let attrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: paper]
  let text = NSAttributedString(string: "夜", attributes: attrs)
  let ts = text.size()
  text.draw(at: NSPoint(x: -ts.width / 2, y: -ts.height / 2 - cardW * 0.02))
  ctx.restoreGState()
}

func render(_ name: String, _ draw: (CGContext) -> Void) {
  let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(size), pixelsHigh: Int(size),
                             bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                             colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
  NSGraphicsContext.saveGraphicsState()
  NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
  draw(NSGraphicsContext.current!.cgContext)
  NSGraphicsContext.restoreGraphicsState()
  let data = rep.representation(using: .png, properties: [:])!
  try! data.write(to: URL(fileURLWithPath: "\(outDir)/\(name)"))
}

// iOS／商店用：整張圖
render("icon.png") { ctx in
  drawBackground(ctx, k: 1, oy: 0, lanternXs: [0.14, 0.38, 0.62, 0.86])
  drawCard(ctx, center: NSPoint(x: size / 2, y: size * 0.42), scale: 1)
}

// Android 自適應圖示（前景不另外內縮，pubspec 的 adaptive_icon_foreground_inset 設 0）：
// 圖層 108dp，手機只露出中間 72dp（2/3），會再裁成圓形或圓角方形，圓形安全區直徑 66dp。
// 所以把 iOS 的畫面縮成 2/3 放在中間，燈籠往中間靠，卡片稍微縮小，圓形裁切也不會切到。
let k: CGFloat = 2.0 / 3
let visibleBottom = (size - size * k) / 2
render("icon_background.png") { ctx in
  drawBackground(ctx, k: k, oy: visibleBottom, lanternXs: [0.355, 0.452, 0.548, 0.645])
}
render("icon_foreground.png") { ctx in
  drawCard(ctx, center: NSPoint(x: size / 2, y: visibleBottom + size * k * 0.43), scale: 0.6)
}
print("done")
