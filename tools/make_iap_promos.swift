// 畫 App Store 內購推廣圖（1024×1024）：夜空背景 + 燈籠 + 每個商品的插圖，不寫價格和說明文字。
// 用法：swift tools/make_iap_promos.swift store/iap_promo
// 產生 <產品 ID>.png（先畫成 PNG 再轉成沒有透明度的 JPEG，商店不收透明圖）。
import AppKit

let outDir = CommandLine.arguments[1]
let size: CGFloat = 1024

func color(_ hex: UInt32, _ alpha: CGFloat = 1) -> NSColor {
  NSColor(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255,
          blue: CGFloat(hex & 0xFF) / 255, alpha: alpha)
}

let night = color(0x16121F), lantern = color(0xE8432F), lanternEdge = color(0xF2735F)
let glow = color(0xFFB547), paper = color(0xFBF1DC)
let gold = color(0xFFD54F), goldDeep = color(0xF5A623), goldEdge = color(0xC77D0A), goldLight = color(0xFFF3C4)

var ctx: CGContext!

func shadow(_ blur: CGFloat, _ c: NSColor, dy: CGFloat = 0) {
  ctx.setShadow(offset: CGSize(width: 0, height: dy), blur: blur, color: c.cgColor)
}
func noShadow() { ctx.setShadow(offset: .zero, blur: 0, color: nil) }

func fill(_ p: NSBezierPath, _ c: NSColor) { c.setFill(); p.fill() }
func stroke(_ p: NSBezierPath, _ c: NSColor, _ w: CGFloat) { c.setStroke(); p.lineWidth = w; p.stroke() }
func gradientFill(_ p: NSBezierPath, _ top: NSColor, _ bottom: NSColor, angle: CGFloat = -90) {
  NSGradient(starting: top, ending: bottom)!.draw(in: p, angle: angle)
}

// MARK: 背景

func background(glowStrength: CGFloat) {
  fill(NSBezierPath(rect: NSRect(x: 0, y: 0, width: size, height: size)), night)
  let top = NSGradient(colors: [glow.withAlphaComponent(0.32), glow.withAlphaComponent(0)])!
  top.draw(fromCenter: NSPoint(x: size / 2, y: size), radius: 0, toCenter: NSPoint(x: size / 2, y: size), radius: size * 0.7, options: [])
  // 商品後面的暖光
  let halo = NSGradient(colors: [glow.withAlphaComponent(glowStrength), glow.withAlphaComponent(0)])!
  halo.draw(fromCenter: NSPoint(x: size / 2, y: size * 0.44), radius: 0, toCenter: NSPoint(x: size / 2, y: size * 0.44), radius: size * 0.46, options: [])
  // 掛線與燈籠
  let line = NSBezierPath()
  line.move(to: NSPoint(x: 0, y: size * 0.915))
  line.curve(to: NSPoint(x: size, y: size * 0.915), controlPoint1: NSPoint(x: size * 0.3, y: size * 0.875),
             controlPoint2: NSPoint(x: size * 0.7, y: size * 0.875))
  stroke(line, paper.withAlphaComponent(0.3), 4)
  for (i, x) in [0.1, 0.3, 0.5, 0.7, 0.9].enumerated() {
    let cy = size * (i == 0 || i == 4 ? 0.87 : (i == 2 ? 0.84 : 0.85))
    shadow(34, lantern.withAlphaComponent(0.9))
    fill(NSBezierPath(ovalIn: NSRect(x: size * x - 26, y: cy - 34, width: 52, height: 66)), lantern)
    noShadow()
  }
}

func sparkle(_ x: CGFloat, _ y: CGFloat, _ r: CGFloat) {
  let p = NSBezierPath()
  p.move(to: NSPoint(x: x, y: y + r))
  p.curve(to: NSPoint(x: x + r, y: y), controlPoint1: NSPoint(x: x + r * 0.12, y: y + r * 0.12), controlPoint2: NSPoint(x: x + r * 0.12, y: y + r * 0.12))
  p.curve(to: NSPoint(x: x, y: y - r), controlPoint1: NSPoint(x: x + r * 0.12, y: y - r * 0.12), controlPoint2: NSPoint(x: x + r * 0.12, y: y - r * 0.12))
  p.curve(to: NSPoint(x: x - r, y: y), controlPoint1: NSPoint(x: x - r * 0.12, y: y - r * 0.12), controlPoint2: NSPoint(x: x - r * 0.12, y: y - r * 0.12))
  p.curve(to: NSPoint(x: x, y: y + r), controlPoint1: NSPoint(x: x - r * 0.12, y: y + r * 0.12), controlPoint2: NSPoint(x: x - r * 0.12, y: y + r * 0.12))
  shadow(r, goldLight)
  fill(p, goldLight)
  noShadow()
}

func sparkles(_ list: [(CGFloat, CGFloat, CGFloat)]) {
  for (x, y, r) in list { sparkle(size * x, size * y, r) }
}

// MARK: 金幣與元寶

/// 正面的金幣（跟遊戲裡的金幣一樣，中間一道亮痕）。
func coin(_ x: CGFloat, _ y: CGFloat, _ r: CGFloat) {
  let outer = NSBezierPath(ovalIn: NSRect(x: x - r, y: y - r, width: r * 2, height: r * 2))
  shadow(r * 0.4, NSColor.black.withAlphaComponent(0.45), dy: -r * 0.12)
  fill(outer, goldEdge)
  noShadow()
  let face = NSBezierPath(ovalIn: NSRect(x: x - r * 0.9, y: y - r * 0.9, width: r * 1.8, height: r * 1.8))
  gradientFill(face, gold, goldDeep)
  stroke(NSBezierPath(ovalIn: NSRect(x: x - r * 0.7, y: y - r * 0.7, width: r * 1.4, height: r * 1.4)), goldEdge.withAlphaComponent(0.45), r * 0.06)
  fill(NSBezierPath(roundedRect: NSRect(x: x - r * 0.09, y: y - r * 0.42, width: r * 0.18, height: r * 0.84), xRadius: r * 0.09, yRadius: r * 0.09), goldLight)
}

/// 一疊金幣（側面），[n] 枚。
func coinStack(_ x: CGFloat, _ y: CGFloat, _ r: CGFloat, _ n: Int) {
  let h = r * 0.22, ry = r * 0.36
  for i in 0..<n {
    let by = y + CGFloat(i) * h
    let body = NSBezierPath()
    body.appendOval(in: NSRect(x: x - r, y: by - ry, width: r * 2, height: ry * 2))
    body.append(NSBezierPath(rect: NSRect(x: x - r, y: by, width: r * 2, height: h)))
    if i == 0 { shadow(r * 0.5, NSColor.black.withAlphaComponent(0.5), dy: -r * 0.1) }
    fill(body, goldEdge)
    noShadow()
    stroke(NSBezierPath(ovalIn: NSRect(x: x - r, y: by - ry, width: r * 2, height: ry * 2)), goldDeep.withAlphaComponent(0.5), 2)
  }
  let ty = y + CGFloat(n) * h
  let top = NSBezierPath(ovalIn: NSRect(x: x - r, y: ty - ry, width: r * 2, height: ry * 2))
  gradientFill(top, gold, goldDeep)
  stroke(NSBezierPath(ovalIn: NSRect(x: x - r * 0.7, y: ty - ry * 0.7, width: r * 1.4, height: ry * 1.4)), goldEdge.withAlphaComponent(0.45), r * 0.05)
}

/// 元寶。
func ingot(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat) {
  let h = w * 0.5
  let base = NSBezierPath()
  base.move(to: NSPoint(x: x - w / 2, y: y + h * 0.55))
  base.curve(to: NSPoint(x: x + w / 2, y: y + h * 0.55), controlPoint1: NSPoint(x: x - w * 0.3, y: y - h * 0.45),
             controlPoint2: NSPoint(x: x + w * 0.3, y: y - h * 0.45))
  base.curve(to: NSPoint(x: x - w / 2, y: y + h * 0.55), controlPoint1: NSPoint(x: x + w * 0.2, y: y + h * 0.3),
             controlPoint2: NSPoint(x: x - w * 0.2, y: y + h * 0.3))
  base.close()
  shadow(w * 0.15, NSColor.black.withAlphaComponent(0.5), dy: -w * 0.04)
  gradientFill(base, gold, goldEdge)
  noShadow()
  let dome = NSBezierPath(ovalIn: NSRect(x: x - w * 0.22, y: y + h * 0.18, width: w * 0.44, height: h * 0.62))
  gradientFill(dome, goldLight, goldDeep)
  stroke(base, goldEdge, w * 0.02)
}

// MARK: 商品插圖

func redEnvelope(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, angle: CGFloat) {
  let h = w * 1.45
  ctx.saveGState()
  ctx.translateBy(x: x, y: y)
  ctx.rotate(by: angle * .pi / 180)
  let body = NSBezierPath(roundedRect: NSRect(x: -w / 2, y: -h / 2, width: w, height: h), xRadius: w * 0.08, yRadius: w * 0.08)
  shadow(w * 0.2, NSColor.black.withAlphaComponent(0.55), dy: -w * 0.05)
  gradientFill(body, color(0xF0503A), color(0xC8301F))
  noShadow()
  let flap = NSBezierPath()
  flap.move(to: NSPoint(x: -w / 2, y: h / 2 - w * 0.06))
  flap.line(to: NSPoint(x: 0, y: h * 0.12))
  flap.line(to: NSPoint(x: w / 2, y: h / 2 - w * 0.06))
  stroke(flap, color(0x9E2416), w * 0.03)
  let seal = NSBezierPath(ovalIn: NSRect(x: -w * 0.22, y: h * 0.02 - w * 0.22, width: w * 0.44, height: w * 0.44))
  gradientFill(seal, gold, goldDeep)
  let font = NSFont(name: "PingFangTC-Semibold", size: w * 0.28) ?? NSFont.boldSystemFont(ofSize: w * 0.28)
  let t = NSAttributedString(string: "福", attributes: [.font: font, .foregroundColor: color(0xB3261E)])
  let ts = t.size()
  t.draw(at: NSPoint(x: -ts.width / 2, y: h * 0.02 - ts.height / 2))
  stroke(NSBezierPath(roundedRect: NSRect(x: -w / 2 + w * 0.07, y: -h / 2 + w * 0.07, width: w - w * 0.14, height: h - w * 0.14),
                      xRadius: w * 0.05, yRadius: w * 0.05), gold.withAlphaComponent(0.55), w * 0.015)
  ctx.restoreGState()
}

func moneyBag(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat) {
  let bag = NSBezierPath()
  bag.move(to: NSPoint(x: x - w * 0.16, y: y + w * 0.42))
  bag.curve(to: NSPoint(x: x - w * 0.5, y: y - w * 0.2), controlPoint1: NSPoint(x: x - w * 0.42, y: y + w * 0.28),
            controlPoint2: NSPoint(x: x - w * 0.58, y: y + w * 0.08))
  bag.curve(to: NSPoint(x: x + w * 0.5, y: y - w * 0.2), controlPoint1: NSPoint(x: x - w * 0.42, y: y - w * 0.56),
            controlPoint2: NSPoint(x: x + w * 0.42, y: y - w * 0.56))
  bag.curve(to: NSPoint(x: x + w * 0.16, y: y + w * 0.42), controlPoint1: NSPoint(x: x + w * 0.58, y: y + w * 0.08),
            controlPoint2: NSPoint(x: x + w * 0.42, y: y + w * 0.28))
  bag.close()
  shadow(w * 0.12, NSColor.black.withAlphaComponent(0.55), dy: -w * 0.04)
  gradientFill(bag, color(0xD9A35B), color(0x9C6A2E))
  noShadow()
  // 袋口的布
  let top = NSBezierPath()
  top.move(to: NSPoint(x: x - w * 0.16, y: y + w * 0.42))
  top.line(to: NSPoint(x: x - w * 0.3, y: y + w * 0.62))
  top.line(to: NSPoint(x: x - w * 0.1, y: y + w * 0.56))
  top.line(to: NSPoint(x: x, y: y + w * 0.66))
  top.line(to: NSPoint(x: x + w * 0.1, y: y + w * 0.56))
  top.line(to: NSPoint(x: x + w * 0.3, y: y + w * 0.62))
  top.line(to: NSPoint(x: x + w * 0.16, y: y + w * 0.42))
  top.close()
  gradientFill(top, color(0xE2B370), color(0xB07B38))
  // 綁繩
  fill(NSBezierPath(roundedRect: NSRect(x: x - w * 0.2, y: y + w * 0.38, width: w * 0.4, height: w * 0.08), xRadius: w * 0.04, yRadius: w * 0.04), lantern)
  coin(x, y - w * 0.12, w * 0.2)
}

func bowl(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat) {
  let rim = w * 0.16
  let body = NSBezierPath()
  body.move(to: NSPoint(x: x - w / 2, y: y))
  body.curve(to: NSPoint(x: x + w / 2, y: y), controlPoint1: NSPoint(x: x - w * 0.45, y: y - w * 0.55),
             controlPoint2: NSPoint(x: x + w * 0.45, y: y - w * 0.55))
  body.close()
  shadow(w * 0.12, NSColor.black.withAlphaComponent(0.55), dy: -w * 0.04)
  gradientFill(body, color(0xE8432F), color(0x9E2416))
  noShadow()
  // 底座
  fill(NSBezierPath(roundedRect: NSRect(x: x - w * 0.2, y: y - w * 0.44, width: w * 0.4, height: w * 0.08), xRadius: w * 0.03, yRadius: w * 0.03), goldEdge)
  // 花紋帶
  let band = NSBezierPath()
  band.move(to: NSPoint(x: x - w * 0.47, y: y - w * 0.1))
  band.curve(to: NSPoint(x: x + w * 0.47, y: y - w * 0.1), controlPoint1: NSPoint(x: x - w * 0.2, y: y - w * 0.2),
             controlPoint2: NSPoint(x: x + w * 0.2, y: y - w * 0.2))
  stroke(band, gold, w * 0.03)
  // 碗口
  let mouth = NSBezierPath(ovalIn: NSRect(x: x - w / 2, y: y - rim / 2, width: w, height: rim))
  gradientFill(mouth, gold, goldEdge)
}

func chest(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, treasure: () -> Void) {
  let h = w * 0.5
  // 打開的蓋子（在後面）
  let lid = NSBezierPath(roundedRect: NSRect(x: x - w / 2, y: y + h * 0.5, width: w, height: h * 0.75), xRadius: w * 0.06, yRadius: w * 0.06)
  gradientFill(lid, color(0x7A4A24), color(0x5A3418))
  stroke(lid, goldDeep, w * 0.02)
  fill(NSBezierPath(rect: NSRect(x: x - w / 2, y: y + h * 0.5, width: w, height: h * 0.12)), color(0x2A1A10))
  treasure()
  // 箱子本體
  let box = NSBezierPath(roundedRect: NSRect(x: x - w / 2, y: y - h / 2, width: w, height: h), xRadius: w * 0.04, yRadius: w * 0.04)
  shadow(w * 0.1, NSColor.black.withAlphaComponent(0.55), dy: -w * 0.03)
  gradientFill(box, color(0x8E5A2E), color(0x5E3718))
  noShadow()
  for bx in [-0.32, 0.32] as [CGFloat] {
    fill(NSBezierPath(rect: NSRect(x: x + w * bx - w * 0.04, y: y - h / 2, width: w * 0.08, height: h)), goldDeep)
  }
  fill(NSBezierPath(rect: NSRect(x: x - w / 2, y: y + h / 2 - w * 0.05, width: w, height: w * 0.05)), goldDeep)
  // 鎖
  let lock = NSBezierPath(roundedRect: NSRect(x: x - w * 0.07, y: y + h * 0.05, width: w * 0.14, height: w * 0.16), xRadius: w * 0.02, yRadius: w * 0.02)
  gradientFill(lock, gold, goldEdge)
  fill(NSBezierPath(ovalIn: NSRect(x: x - w * 0.018, y: y + h * 0.17, width: w * 0.036, height: w * 0.036)), color(0x5E3718))
}

func gameCard(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, angle: CGFloat, mark: String) {
  let h = w * 4 / 3
  ctx.saveGState()
  ctx.translateBy(x: x, y: y)
  ctx.rotate(by: angle * .pi / 180)
  let card = NSRect(x: -w / 2, y: -h / 2, width: w, height: h)
  shadow(w * 0.12, NSColor.black.withAlphaComponent(0.55), dy: -w * 0.04)
  fill(NSBezierPath(roundedRect: card, xRadius: w * 0.09, yRadius: w * 0.09), color(0xC8301F))
  noShadow()
  // 開張大吉卡背：紅底金點、金框
  NSGradient(starting: color(0xE8432F), ending: color(0xB3261E))!.draw(in: NSBezierPath(roundedRect: card, xRadius: w * 0.09, yRadius: w * 0.09), angle: -90)
  for row in 0..<9 {
    for col in 0..<7 {
      let px = -w / 2 + w * (0.1 + CGFloat(col) * 0.135) + (row % 2 == 0 ? 0 : w * 0.067)
      let py = -h / 2 + h * (0.08 + CGFloat(row) * 0.105)
      fill(NSBezierPath(ovalIn: NSRect(x: px - w * 0.012, y: py - w * 0.012, width: w * 0.024, height: w * 0.024)), gold.withAlphaComponent(0.35))
    }
  }
  stroke(NSBezierPath(roundedRect: card.insetBy(dx: w * 0.03, dy: w * 0.03), xRadius: w * 0.07, yRadius: w * 0.07), gold, w * 0.04)
  let badge = NSBezierPath(ovalIn: NSRect(x: -w * 0.27, y: -w * 0.27, width: w * 0.54, height: w * 0.54))
  shadow(w * 0.08, glow)
  gradientFill(badge, color(0xE8432F), color(0xB3261E))
  noShadow()
  stroke(badge, gold, w * 0.035)
  let font = NSFont(name: "PingFangTC-Semibold", size: w * 0.3) ?? NSFont.boldSystemFont(ofSize: w * 0.3)
  let t = NSAttributedString(string: mark, attributes: [.font: font, .foregroundColor: gold])
  let ts = t.size()
  t.draw(at: NSPoint(x: -ts.width / 2, y: -ts.height / 2))
  ctx.restoreGState()
}

func calendar(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat) {
  let h = w * 1.05
  let page = NSBezierPath(roundedRect: NSRect(x: x - w / 2, y: y - h / 2, width: w, height: h), xRadius: w * 0.08, yRadius: w * 0.08)
  shadow(w * 0.12, NSColor.black.withAlphaComponent(0.55), dy: -w * 0.04)
  fill(page, paper)
  noShadow()
  let header = NSBezierPath(roundedRect: NSRect(x: x - w / 2, y: y + h / 2 - h * 0.28, width: w, height: h * 0.28), xRadius: w * 0.08, yRadius: w * 0.08)
  fill(header, lantern)
  fill(NSBezierPath(rect: NSRect(x: x - w / 2, y: y + h / 2 - h * 0.28, width: w, height: h * 0.1)), lantern)
  for rx in [-0.25, 0.25] as [CGFloat] {
    fill(NSBezierPath(roundedRect: NSRect(x: x + w * rx - w * 0.035, y: y + h / 2 - h * 0.08, width: w * 0.07, height: h * 0.16), xRadius: w * 0.035, yRadius: w * 0.035), color(0x5A5A66))
  }
  let font = NSFont(name: "Avenir Next Heavy", size: w * 0.48) ?? NSFont.boldSystemFont(ofSize: w * 0.48)
  let t = NSAttributedString(string: "30", attributes: [.font: font, .foregroundColor: night])
  let ts = t.size()
  t.draw(at: NSPoint(x: x - ts.width / 2, y: y - h * 0.14 - ts.height / 2))
}

func noAds(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat) {
  let h = w * 0.62
  let screen = NSBezierPath(roundedRect: NSRect(x: x - w / 2, y: y - h / 2, width: w, height: h), xRadius: w * 0.06, yRadius: w * 0.06)
  shadow(w * 0.1, NSColor.black.withAlphaComponent(0.55), dy: -w * 0.03)
  fill(screen, color(0x2A2438))
  noShadow()
  stroke(screen, color(0x5A5070), w * 0.025)
  let font = NSFont(name: "Avenir Next Heavy", size: w * 0.3) ?? NSFont.boldSystemFont(ofSize: w * 0.3)
  let t = NSAttributedString(string: "AD", attributes: [.font: font, .foregroundColor: color(0x8C82A6)])
  let ts = t.size()
  t.draw(at: NSPoint(x: x - ts.width / 2, y: y - ts.height / 2))
  // 禁止符號
  let r = w * 0.46
  let ring = NSBezierPath(ovalIn: NSRect(x: x - r, y: y - r, width: r * 2, height: r * 2))
  shadow(w * 0.06, lantern)
  stroke(ring, lantern, w * 0.08)
  let bar = NSBezierPath()
  bar.move(to: NSPoint(x: x - r * 0.7, y: y + r * 0.7))
  bar.line(to: NSPoint(x: x + r * 0.7, y: y - r * 0.7))
  stroke(bar, lantern, w * 0.08)
  noShadow()
}

// MARK: 輸出

func render(_ id: String, glowStrength: CGFloat = 0.28, _ draw: () -> Void) {
  let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(size), pixelsHigh: Int(size),
                             bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                             colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
  NSGraphicsContext.saveGraphicsState()
  NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
  ctx = NSGraphicsContext.current!.cgContext
  background(glowStrength: glowStrength)
  draw()
  NSGraphicsContext.restoreGraphicsState()
  let data = rep.representation(using: .jpeg, properties: [.compressionFactor: 0.92])!
  try! data.write(to: URL(fileURLWithPath: "\(outDir)/\(id).jpg"))
}

let c = size / 2

render("coins_30", glowStrength: 0.18) {
  coinStack(c - 70, 330, 95, 3)
  coin(c + 90, 420, 105)
  coin(c - 40, 560, 115)
  sparkles([(0.3, 0.62, 18), (0.72, 0.58, 14)])
}

render("coins_90", glowStrength: 0.22) {
  redEnvelope(c - 20, 470, 270, angle: 8)
  coin(c + 170, 300, 90)
  coin(c - 190, 290, 75)
  sparkles([(0.25, 0.68, 20), (0.74, 0.66, 16), (0.66, 0.36, 12)])
}

render("coins_170", glowStrength: 0.26) {
  moneyBag(c, 470, 400)
  coinStack(c - 230, 230, 70, 3)
  coin(c + 220, 270, 80)
  coin(c + 140, 210, 60)
  sparkles([(0.22, 0.66, 20), (0.78, 0.62, 18), (0.7, 0.44, 12)])
}

render("coins_330", glowStrength: 0.3) {
  // 碗裡堆滿金幣和元寶
  for (dx, dy, r) in [(-150, 30, 70), (150, 30, 70), (-70, 60, 78), (70, 60, 78), (0, 90, 82)] as [(CGFloat, CGFloat, CGFloat)] {
    coin(c + dx, 430 + dy, r)
  }
  ingot(c, 560, 230)
  bowl(c, 420, 520)
  sparkles([(0.2, 0.66, 22), (0.8, 0.62, 18), (0.72, 0.74, 14), (0.3, 0.42, 12)])
}

render("coins_590", glowStrength: 0.34) {
  chest(c, 360, 520) {
    for (dx, dy, r) in [(-150, 140, 60), (150, 140, 60), (-60, 175, 66), (70, 170, 66)] as [(CGFloat, CGFloat, CGFloat)] {
      coin(c + dx, 360 + dy, r)
    }
    ingot(c, 430, 210)
  }
  coin(c + 290, 200, 66)
  sparkles([(0.18, 0.7, 22), (0.82, 0.66, 20), (0.5, 0.8, 16), (0.2, 0.4, 14)])
}

render("coins_990", glowStrength: 0.42) {
  chest(c, 380, 560) {
    for (dx, dy, r) in [(-190, 150, 62), (190, 150, 62), (-110, 190, 70), (110, 190, 70), (0, 215, 74)] as [(CGFloat, CGFloat, CGFloat)] {
      coin(c + dx, 380 + dy, r)
    }
    ingot(c - 100, 470, 190)
    ingot(c + 110, 480, 190)
  }
  coinStack(c - 330, 180, 70, 4)
  coinStack(c + 330, 180, 70, 3)
  ingot(c - 230, 170, 150)
  ingot(c + 230, 160, 150)
  sparkles([(0.15, 0.72, 24), (0.85, 0.7, 22), (0.5, 0.84, 18), (0.12, 0.46, 14), (0.88, 0.44, 14)])
}

render("starter_pack", glowStrength: 0.34) {
  gameCard(c + 40, 500, 330, angle: -8, mark: "開")
  coinStack(c - 230, 220, 90, 4)
  coin(c + 250, 250, 85)
  sparkles([(0.2, 0.7, 22), (0.8, 0.72, 20), (0.82, 0.42, 14)])
}

render("month_card", glowStrength: 0.3) {
  calendar(c - 30, 500, 380)
  coin(c + 180, 300, 110)
  sparkles([(0.2, 0.7, 22), (0.8, 0.72, 18), (0.24, 0.32, 14)])
}

render("remove_ads", glowStrength: 0.22) {
  noAds(c, 470, 520)
  sparkles([(0.18, 0.72, 18), (0.82, 0.3, 16)])
}

print("done")
