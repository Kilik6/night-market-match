// 畫夜市翻牌的 App 圖示：夜空背景 + 燈光暈染 + 一排小燈籠 + 微傾斜的紅色卡片寫「夜」。
// 用法：swift tools/make_icon.swift assets/icon
// 產生 icon.png（1024，iOS／一般用，不透明）與 icon_foreground.png（Android 自適應圖示前景，透明背景）。
import AppKit

let outDir = CommandLine.arguments[1]
let size: CGFloat = 1024

func color(_ hex: UInt32, _ alpha: CGFloat = 1) -> NSColor {
  NSColor(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255,
          blue: CGFloat(hex & 0xFF) / 255, alpha: alpha)
}

let night = color(0x16121F), lantern = color(0xE8432F), lanternEdge = color(0xF2735F)
let glow = color(0xFFB547), paper = color(0xFBF1DC)

func render(_ name: String, background: Bool, scale: CGFloat) {
  let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(size), pixelsHigh: Int(size),
                             bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                             colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
  NSGraphicsContext.saveGraphicsState()
  NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
  let ctx = NSGraphicsContext.current!.cgContext

  if background {
    night.setFill()
    NSRect(x: 0, y: 0, width: size, height: size).fill()
    // 上方暖色燈光
    let g = NSGradient(colors: [glow.withAlphaComponent(0.38), glow.withAlphaComponent(0)])!
    g.draw(fromCenter: NSPoint(x: size / 2, y: size * 0.98), radius: 0,
           toCenter: NSPoint(x: size / 2, y: size * 0.98), radius: size * 0.75, options: [])
    // 掛線與小燈籠
    paper.withAlphaComponent(0.3).setStroke()
    let line = NSBezierPath()
    line.move(to: NSPoint(x: 0, y: size * 0.905))
    line.curve(to: NSPoint(x: size, y: size * 0.905), controlPoint1: NSPoint(x: size * 0.3, y: size * 0.86),
               controlPoint2: NSPoint(x: size * 0.7, y: size * 0.86))
    line.lineWidth = 5
    line.stroke()
    for (i, x) in [0.14, 0.38, 0.62, 0.86].enumerated() {
      let cx = size * CGFloat(x)
      let cy = size * (i == 0 || i == 3 ? 0.855 : 0.83)
      ctx.setShadow(offset: .zero, blur: 40, color: lantern.withAlphaComponent(0.9).cgColor)
      lantern.setFill()
      NSBezierPath(ovalIn: NSRect(x: cx - 34, y: cy - 44, width: 68, height: 84)).fill()
      ctx.setShadow(offset: .zero, blur: 0, color: nil)
    }
  }

  // 卡片（稍微傾斜）
  let cardW = size * 0.5 * scale, cardH = cardW * 4 / 3
  let center = NSPoint(x: size / 2, y: background ? size * 0.42 : size / 2)
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

  NSGraphicsContext.restoreGraphicsState()
  let data = rep.representation(using: .png, properties: [:])!
  try! data.write(to: URL(fileURLWithPath: "\(outDir)/\(name)"))
}

render("icon.png", background: true, scale: 1.0)
// Android 自適應圖示前景：內容要在中間約 66% 的安全區內，所以縮小一點
render("icon_foreground.png", background: false, scale: 0.78)
print("done")
