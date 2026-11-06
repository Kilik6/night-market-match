// 畫夜市翻牌的專屬小吃圖案（透明背景 PNG），取代 emoji，讓 iOS 和 Android 看起來一樣。
// 用法：swift tools/make_food_icons.swift assets/foods && sips -Z 256 assets/foods/*.png
import AppKit

let outDir = CommandLine.arguments[1]
let size: CGFloat = 512

func color(_ hex: UInt32, _ alpha: CGFloat = 1) -> NSColor {
  NSColor(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255,
          blue: CGFloat(hex & 0xFF) / 255, alpha: alpha)
}

func render(_ name: String, _ draw: (CGContext) -> Void) {
  let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(size), pixelsHigh: Int(size),
                             bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                             colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
  NSGraphicsContext.saveGraphicsState()
  NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
  draw(NSGraphicsContext.current!.cgContext)
  NSGraphicsContext.restoreGraphicsState()
  try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: "\(outDir)/\(name).png"))
}

func ellipse(_ cx: CGFloat, _ cy: CGFloat, _ rx: CGFloat, _ ry: CGFloat) -> NSBezierPath {
  NSBezierPath(ovalIn: NSRect(x: cx - rx, y: cy - ry, width: rx * 2, height: ry * 2))
}

/// 一顆圓胖的小籠包：下半部飽滿，往上收成尖頂，頂端有放射狀的摺痕。
func dumpling(_ ctx: CGContext, _ cx: CGFloat, _ cy: CGFloat, _ r: CGFloat) {
  let top = NSPoint(x: cx, y: cy + r * 1.02)
  let body = NSBezierPath()
  body.move(to: top)
  body.curve(to: NSPoint(x: cx + r, y: cy - r * 0.18),
             controlPoint1: NSPoint(x: cx + r * 0.34, y: cy + r * 0.74),
             controlPoint2: NSPoint(x: cx + r, y: cy + r * 0.46))
  body.curve(to: NSPoint(x: cx, y: cy - r * 0.8),
             controlPoint1: NSPoint(x: cx + r, y: cy - r * 0.62),
             controlPoint2: NSPoint(x: cx + r * 0.56, y: cy - r * 0.8))
  body.curve(to: NSPoint(x: cx - r, y: cy - r * 0.18),
             controlPoint1: NSPoint(x: cx - r * 0.56, y: cy - r * 0.8),
             controlPoint2: NSPoint(x: cx - r, y: cy - r * 0.62))
  body.curve(to: top,
             controlPoint1: NSPoint(x: cx - r, y: cy + r * 0.46),
             controlPoint2: NSPoint(x: cx - r * 0.34, y: cy + r * 0.74))
  body.close()

  ctx.saveGState()
  ctx.setShadow(offset: CGSize(width: 0, height: -r * 0.1), blur: r * 0.22, color: color(0x3A2410, 0.55).cgColor)
  color(0xF3E2C2).setFill()
  body.fill()
  ctx.restoreGState()

  ctx.saveGState()
  body.addClip()
  NSGradient(colors: [color(0xFFF8E9), color(0xF5E6C9), color(0xDDBF90)])!
    .draw(fromCenter: NSPoint(x: cx - r * 0.3, y: cy + r * 0.25), radius: 0,
          toCenter: NSPoint(x: cx, y: cy), radius: r * 1.2, options: [.drawsAfterEndingLocation])
  // 摺痕：從頂端往下放射的弧線
  color(0xC9A36E, 0.75).setStroke()
  for i in -3...3 {
    let t = CGFloat(i) / 3
    let line = NSBezierPath()
    line.lineWidth = r * 0.05
    line.lineCapStyle = .round
    line.move(to: NSPoint(x: cx + t * r * 0.05, y: cy + r * 0.92))
    line.curve(to: NSPoint(x: cx + t * r * 0.8, y: cy + r * (0.12 - abs(t) * 0.08)),
               controlPoint1: NSPoint(x: cx + t * r * 0.14, y: cy + r * 0.62),
               controlPoint2: NSPoint(x: cx + t * r * 0.62, y: cy + r * 0.42))
    line.stroke()
  }
  ctx.restoreGState()

  // 頂端捏起來的小尖
  color(0xE6CDA3).setFill()
  ellipse(cx, cy + r * 0.96, r * 0.11, r * 0.09).fill()
}

// 小籠包：竹蒸籠裡放 5 顆
render("xiaolongbao") { ctx in
  ctx.translateBy(x: 0, y: 66) // 把圖案移到畫面中間
  let cx = size / 2
  let rx: CGFloat = 232, ry: CGFloat = 150
  let rimY: CGFloat = 214

  // 蒸籠外側（圓柱側面）
  ctx.saveGState()
  ctx.setShadow(offset: CGSize(width: 0, height: -10), blur: 22, color: color(0x000000, 0.35).cgColor)
  let side = NSBezierPath()
  side.appendOval(in: NSRect(x: cx - rx, y: rimY - ry - 58, width: rx * 2, height: ry * 2))
  color(0x9A6330).setFill()
  side.fill()
  ctx.restoreGState()
  NSBezierPath(rect: NSRect(x: cx - rx, y: rimY - 58, width: rx * 2, height: 58)).fill()
  NSGradient(colors: [color(0x7E4E22), color(0xC48A4C), color(0xD9A468), color(0xB77C3E), color(0x75461E)])!
    .draw(in: {
      let p = NSBezierPath()
      p.appendOval(in: NSRect(x: cx - rx, y: rimY - ry - 58, width: rx * 2, height: ry * 2))
      p.append(NSBezierPath(rect: NSRect(x: cx - rx, y: rimY - 58, width: rx * 2, height: 58)))
      return p
    }(), angle: 0)

  // 上緣和內部
  NSGradient(colors: [color(0xE8BD83), color(0xC98F50)])!.draw(in: ellipse(cx, rimY, rx, ry), angle: 90)
  let inner = ellipse(cx, rimY + 4, rx - 22, ry - 18)
  NSGradient(colors: [color(0x6F4420), color(0x8E5C2E)])!.draw(in: inner, angle: 90)

  // 竹片
  ctx.saveGState()
  inner.addClip()
  color(0x5A3618, 0.6).setStroke()
  var x = cx - rx
  while x < cx + rx {
    let slat = NSBezierPath()
    slat.lineWidth = 4
    slat.move(to: NSPoint(x: x, y: 0))
    slat.line(to: NSPoint(x: x, y: size))
    slat.stroke()
    x += 34
  }
  ctx.restoreGState()

  // 小籠包：先畫後排
  dumpling(ctx, cx - 92, 270, 86)
  dumpling(ctx, cx + 92, 270, 86)
  dumpling(ctx, cx - 156, 196, 88)
  dumpling(ctx, cx + 156, 196, 88)
  dumpling(ctx, cx, 180, 96)
}

// 木瓜牛奶：橘色的高玻璃杯，杯口有吸管和木瓜片
render("papaya_milk") { ctx in
  let cx = size / 2
  let topY: CGFloat = 416, bottomY: CGFloat = 44
  let topW: CGFloat = 134, bottomW: CGFloat = 96

  func cup(inset: CGFloat, top: CGFloat) -> NSBezierPath {
    let w = topW - inset
    let bw = bottomW - inset
    let p = NSBezierPath()
    p.move(to: NSPoint(x: cx - w, y: top))
    p.line(to: NSPoint(x: cx - bw, y: bottomY + inset + 26))
    p.curve(to: NSPoint(x: cx - bw + 26, y: bottomY + inset),
            controlPoint1: NSPoint(x: cx - bw, y: bottomY + inset + 8),
            controlPoint2: NSPoint(x: cx - bw + 10, y: bottomY + inset))
    p.line(to: NSPoint(x: cx + bw - 26, y: bottomY + inset))
    p.curve(to: NSPoint(x: cx + bw, y: bottomY + inset + 26),
            controlPoint1: NSPoint(x: cx + bw - 10, y: bottomY + inset),
            controlPoint2: NSPoint(x: cx + bw, y: bottomY + inset + 8))
    p.line(to: NSPoint(x: cx + w, y: top))
    p.close()
    return p
  }

  // 吸管（畫在杯子後面）
  ctx.saveGState()
  ctx.translateBy(x: cx + 40, y: 300)
  ctx.rotate(by: -0.17)
  color(0xE8432F).setFill()
  NSBezierPath(roundedRect: NSRect(x: -11, y: -40, width: 22, height: 228), xRadius: 8, yRadius: 8).fill()
  color(0xFBF1DC).setFill()
  for y in stride(from: CGFloat(30), to: 180, by: 44) {
    NSBezierPath(rect: NSRect(x: -11, y: y, width: 22, height: 16)).fill()
  }
  ctx.restoreGState()

  // 玻璃杯外形
  ctx.saveGState()
  ctx.setShadow(offset: CGSize(width: 0, height: -8), blur: 18, color: color(0x000000, 0.3).cgColor)
  color(0xFFFFFF, 0.9).setFill()
  cup(inset: 0, top: topY).fill()
  ctx.restoreGState()

  // 橘色木瓜牛奶
  let milk = cup(inset: 11, top: 362)
  NSGradient(colors: [color(0xF4851F), color(0xFB9F3C), color(0xFFB862)])!.draw(in: milk, angle: 90)
  // 上層的奶泡
  ctx.saveGState()
  milk.addClip()
  color(0xFFD9A0).setFill()
  ellipse(cx, 362, topW, 26).fill()
  ctx.restoreGState()

  // 玻璃反光
  ctx.saveGState()
  cup(inset: 0, top: topY).addClip()
  color(0xFFFFFF, 0.5).setFill()
  let shine = NSBezierPath(roundedRect: NSRect(x: cx - 88, y: 110, width: 24, height: 236), xRadius: 12, yRadius: 12)
  let tilt = AffineTransform(translationByX: 0, byY: 0)
  shine.transform(using: tilt)
  shine.fill()
  ctx.restoreGState()

  // 杯口
  color(0xFFFFFF, 0.85).setStroke()
  let rim = ellipse(cx, topY, topW, 13)
  rim.lineWidth = 5
  rim.stroke()

  // 杯緣的木瓜片
  ctx.saveGState()
  ctx.translateBy(x: cx - 112, y: topY + 8)
  ctx.rotate(by: 0.5)
  color(0x4E8F3A).setFill()
  ellipse(0, 0, 66, 50).fill()
  color(0xFF8A2B).setFill()
  ellipse(0, 0, 57, 42).fill()
  color(0xFFB25C).setFill()
  ellipse(0, 0, 30, 19).fill()
  color(0x2A1A14).setFill()
  for (dx, dy) in [(-12.0, 3.0), (0.0, -5.0), (12.0, 4.0), (3.0, 8.0)] as [(CGFloat, CGFloat)] {
    ellipse(dx, dy, 5, 4).fill()
  }
  ctx.restoreGState()
}


/// 不規則圓形的路徑，用來畫煎餅、油亮的醬汁。
func blob(_ cx: CGFloat, _ cy: CGFloat, _ rx: CGFloat, _ ry: CGFloat, wobble: CGFloat, seed: Int) -> NSBezierPath {
  let n = 28
  var pts: [NSPoint] = []
  for i in 0..<n {
    let a = CGFloat(i) / CGFloat(n) * 2 * .pi
    let w = 1 + wobble * (sin(a * 3 + CGFloat(seed)) * 0.6 + sin(a * 5 + CGFloat(seed) * 2) * 0.4)
    pts.append(NSPoint(x: cx + cos(a) * rx * w, y: cy + sin(a) * ry * w))
  }
  let p = NSBezierPath()
  p.move(to: NSPoint(x: (pts[0].x + pts[n - 1].x) / 2, y: (pts[0].y + pts[n - 1].y) / 2))
  for i in 0..<n {
    let cur = pts[i], next = pts[(i + 1) % n]
    p.curve(to: NSPoint(x: (cur.x + next.x) / 2, y: (cur.y + next.y) / 2), controlPoint1: cur, controlPoint2: cur)
  }
  p.close()
  return p
}

func stroke(_ path: NSBezierPath, _ c: NSColor, _ width: CGFloat) {
  c.setStroke()
  path.lineWidth = width
  path.lineCapStyle = .round
  path.lineJoinStyle = .round
  path.stroke()
}

func wave(_ points: [NSPoint]) -> NSBezierPath {
  let p = NSBezierPath()
  p.move(to: points[0])
  for i in 1..<points.count {
    let a = points[i - 1], b = points[i]
    let mid = NSPoint(x: (a.x + b.x) / 2, y: (a.y + b.y) / 2)
    p.curve(to: b, controlPoint1: NSPoint(x: mid.x, y: a.y), controlPoint2: NSPoint(x: mid.x, y: b.y))
  }
  return p
}

// 蚵仔煎：盤子上的金黃煎餅，有鮮蚵、青菜和紅色甜辣醬
render("oyster_omelette") { ctx in
  let cx = size / 2, cy: CGFloat = 248
  ctx.saveGState()
  ctx.setShadow(offset: CGSize(width: 0, height: -10), blur: 20, color: color(0x000000, 0.3).cgColor)
  color(0xFFFFFF).setFill()
  ellipse(cx, cy, 236, 176).fill()
  ctx.restoreGState()
  stroke(ellipse(cx, cy, 236, 176), color(0x3F7FB5), 7)
  stroke(ellipse(cx, cy, 214, 156), color(0xD8E4EE), 3)

  let pancake = blob(cx, cy + 2, 186, 130, wobble: 0.06, seed: 2)
  NSGradient(colors: [color(0xF7D27A), color(0xE7A94B), color(0xC9812E)])!
    .draw(in: pancake, relativeCenterPosition: NSPoint(x: -0.1, y: 0.1))
  ctx.saveGState()
  pancake.addClip()
  // 半透明的粉漿
  color(0xFFF3D2, 0.5).setFill()
  blob(cx - 70, cy + 40, 64, 40, wobble: 0.1, seed: 1).fill()
  blob(cx + 86, cy - 44, 70, 36, wobble: 0.1, seed: 3).fill()
  // 鮮蚵
  for (x, y, r) in [(-104.0, -24.0, 40.0), (-20.0, 58.0, 42.0), (92.0, 28.0, 42.0), (34.0, -66.0, 38.0)] as [(CGFloat, CGFloat, CGFloat)] {
    let oyster = blob(cx + x, cy + y, r, r * 0.72, wobble: 0.1, seed: Int(r))
    NSGradient(colors: [color(0xF6EFE6), color(0xC9BBB0)])!.draw(in: oyster, angle: 70)
    color(0x6E5F6B, 0.75).setFill()
    blob(cx + x + r * 0.2, cy + y - r * 0.1, r * 0.42, r * 0.28, wobble: 0.1, seed: 5).fill()
  }
  // 青菜
  for (x, y, a) in [(-60.0, 8.0, 0.5), (40.0, 14.0, -0.6), (-112.0, 50.0, -0.4), (120.0, -30.0, 0.8), (-34.0, -66.0, 1.1), (86.0, 76.0, 0.2)] as [(CGFloat, CGFloat, CGFloat)] {
    ctx.saveGState()
    ctx.translateBy(x: cx + x, y: cy + y)
    ctx.rotate(by: a)
    color(0x4FA33B).setFill()
    NSBezierPath(roundedRect: NSRect(x: -34, y: -11, width: 68, height: 22), xRadius: 11, yRadius: 11).fill()
    color(0x7CC95D).setFill()
    NSBezierPath(roundedRect: NSRect(x: -24, y: -3, width: 44, height: 6), xRadius: 3, yRadius: 3).fill()
    ctx.restoreGState()
  }
  ctx.restoreGState()
  // 甜辣醬
  let sauce = wave([NSPoint(x: cx - 150, y: cy + 30), NSPoint(x: cx - 70, y: cy + 74), NSPoint(x: cx + 10, y: cy - 8),
                    NSPoint(x: cx + 90, y: cy + 54), NSPoint(x: cx + 150, y: cy - 26)])
  stroke(sauce, color(0xC9331F), 26)
  stroke(sauce, color(0xE85A3A), 12)
}

// 黑輪：兩串淋上甜辣醬的魚漿片
render("heilun") { ctx in
  func skewer(_ x: CGFloat, _ y: CGFloat, _ angle: CGFloat) {
    ctx.saveGState()
    ctx.translateBy(x: x, y: y)
    ctx.rotate(by: angle)
    // 竹籤
    color(0xD8B47A).setFill()
    NSBezierPath(roundedRect: NSRect(x: -7, y: -236, width: 14, height: 440), xRadius: 6, yRadius: 6).fill()
    // 三片魚漿片
    for i in 0..<3 {
      let base = CGFloat(i) * 112 - 170
      let rect = NSRect(x: -68, y: base, width: 136, height: 98)
      let piece = NSBezierPath(roundedRect: rect, xRadius: 26, yRadius: 26)
      ctx.saveGState()
      ctx.setShadow(offset: CGSize(width: 0, height: -6), blur: 12, color: color(0x000000, 0.3).cgColor)
      color(0xB9834A).setFill()
      piece.fill()
      ctx.restoreGState()
      NSGradient(colors: [color(0xD9A96B), color(0xB57E45), color(0x8F5E30)])!.draw(in: piece, angle: -70)
      // 烤痕
      color(0x6E431E, 0.75).setFill()
      for j in 0..<3 {
        NSBezierPath(roundedRect: NSRect(x: -46 + CGFloat(j) * 34, y: base + 16, width: 9, height: 66), xRadius: 4, yRadius: 4).fill()
      }
      // 甜辣醬
      let sauce = wave([NSPoint(x: -58, y: base + 62), NSPoint(x: -20, y: base + 32), NSPoint(x: 20, y: base + 68), NSPoint(x: 58, y: base + 36)])
      stroke(sauce, color(0xC9331F), 15)
      stroke(sauce, color(0xEF6A45), 6)
    }
    ctx.restoreGState()
  }
  skewer(182, 262, 0.2)
  skewer(330, 262, -0.2)
}

// 台式飯糰：紙包著的糯米飯糰，切面看得到油條、肉鬆和菜脯
render("rice_roll") { ctx in
  let cx = size / 2
  ctx.saveGState()
  ctx.translateBy(x: cx, y: 244)
  ctx.rotate(by: -0.14)

  // 飯糰身體
  let body = NSBezierPath(roundedRect: NSRect(x: -136, y: -196, width: 272, height: 360), xRadius: 124, yRadius: 124)
  ctx.saveGState()
  ctx.setShadow(offset: CGSize(width: 0, height: -10), blur: 20, color: color(0x000000, 0.3).cgColor)
  color(0xF7F3EA).setFill()
  body.fill()
  ctx.restoreGState()
  NSGradient(colors: [color(0xFFFFFF), color(0xEFE7D8)])!.draw(in: body, angle: 0)

  // 米粒
  ctx.saveGState()
  body.addClip()
  color(0xDCD2BE).setFill()
  for i in 0..<70 {
    let fx = CGFloat((i * 53) % 271) - 135
    let fy = CGFloat((i * 97) % 359) - 195
    ctx.saveGState()
    ctx.translateBy(x: fx, y: fy)
    ctx.rotate(by: CGFloat(i))
    ellipse(0, 0, 13, 6).fill()
    ctx.restoreGState()
  }
  // 中間的餡料切面
  let filling = ellipse(0, 54, 92, 80)
  color(0x8A5A2E).setFill()
  filling.fill()
  filling.addClip()
  // 肉鬆
  color(0xC58A4A).setFill()
  for i in 0..<46 {
    ctx.saveGState()
    ctx.translateBy(x: CGFloat((i * 41) % 180) - 90, y: 54 + CGFloat((i * 67) % 150) - 75)
    ctx.rotate(by: CGFloat(i) * 0.9)
    NSBezierPath(roundedRect: NSRect(x: -15, y: -3, width: 30, height: 6), xRadius: 3, yRadius: 3).fill()
    ctx.restoreGState()
  }
  // 油條
  color(0xE8A83E).setFill()
  NSBezierPath(roundedRect: NSRect(x: -56, y: 62, width: 112, height: 44), xRadius: 20, yRadius: 20).fill()
  color(0xC97F1F).setFill()
  NSBezierPath(roundedRect: NSRect(x: -46, y: 80, width: 92, height: 7), xRadius: 3, yRadius: 3).fill()
  // 菜脯
  color(0xF2D45C).setFill()
  for (x, y) in [(-40.0, 26.0), (-8.0, 12.0), (30.0, 28.0), (52.0, 44.0), (-62.0, 44.0)] as [(CGFloat, CGFloat)] {
    NSBezierPath(roundedRect: NSRect(x: x - 11, y: y - 8, width: 22, height: 16), xRadius: 4, yRadius: 4).fill()
  }
  ctx.restoreGState()

  // 下半部包的紙
  let paper = NSBezierPath()
  paper.move(to: NSPoint(x: -152, y: -64))
  paper.line(to: NSPoint(x: 152, y: -30))
  paper.line(to: NSPoint(x: 140, y: -150))
  paper.curve(to: NSPoint(x: -140, y: -150), controlPoint1: NSPoint(x: 90, y: -234), controlPoint2: NSPoint(x: -90, y: -234))
  paper.close()
  NSGradient(colors: [color(0xE8473A), color(0xC7301F)])!.draw(in: paper, angle: -90)
  color(0xFBF1DC).setFill()
  for i in 0..<5 {
    ellipse(-96 + CGFloat(i) * 48, -104 + CGFloat(i) * 7, 9, 9).fill()
  }
  ctx.restoreGState()
}

// 雞蛋糕：紙袋裡金黃的小圓蛋糕
render("egg_cake") { ctx in
  let cx = size / 2
  // 紙袋
  let bag = NSBezierPath()
  bag.move(to: NSPoint(x: cx - 164, y: 262))
  bag.line(to: NSPoint(x: cx + 164, y: 262))
  bag.line(to: NSPoint(x: cx + 132, y: 40))
  bag.line(to: NSPoint(x: cx - 132, y: 40))
  bag.close()

  func cake(_ x: CGFloat, _ y: CGFloat, _ r: CGFloat) {
    let c = ellipse(x, y, r, r * 0.94)
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -5), blur: 10, color: color(0x5A3410, 0.45).cgColor)
    color(0xE6A23C).setFill()
    c.fill()
    ctx.restoreGState()
    NSGradient(colors: [color(0xFFD978), color(0xEFAE45), color(0xC47A22)])!
      .draw(in: c, relativeCenterPosition: NSPoint(x: -0.3, y: 0.35))
    // 模具壓出的花紋
    color(0xB86F1E, 0.75).setStroke()
    for i in 0..<6 {
      let a = CGFloat(i) / 6 * 2 * .pi
      let line = NSBezierPath()
      line.lineWidth = r * 0.08
      line.lineCapStyle = .round
      line.move(to: NSPoint(x: x + cos(a) * r * 0.26, y: y + sin(a) * r * 0.26))
      line.line(to: NSPoint(x: x + cos(a) * r * 0.72, y: y + sin(a) * r * 0.72))
      line.stroke()
    }
    color(0xFFE9A8, 0.7).setFill()
    ellipse(x - r * 0.36, y + r * 0.42, r * 0.2, r * 0.13).fill()
  }

  cake(cx - 112, 372, 76)
  cake(cx + 112, 372, 76)
  cake(cx, 402, 80)
  cake(cx - 66, 296, 82)
  cake(cx + 74, 296, 82)

  ctx.saveGState()
  ctx.setShadow(offset: CGSize(width: 0, height: -8), blur: 16, color: color(0x000000, 0.3).cgColor)
  color(0xD8A865).setFill()
  bag.fill()
  ctx.restoreGState()
  NSGradient(colors: [color(0xE7C088), color(0xCF9C5A)])!.draw(in: bag, angle: -90)
  color(0xE8432F).setFill()
  NSBezierPath(rect: NSRect(x: cx - 136, y: 140, width: 272, height: 16)).fill()
  NSBezierPath(rect: NSRect(x: cx - 139, y: 176, width: 278, height: 8)).fill()
  // 袋口的鋸齒
  color(0xF3D9AE).setFill()
  let edge = NSBezierPath()
  edge.move(to: NSPoint(x: cx - 164, y: 262))
  var x = cx - 164
  while x < cx + 164 {
    edge.line(to: NSPoint(x: x + 14, y: 248))
    edge.line(to: NSPoint(x: x + 28, y: 262))
    x += 28
  }
  edge.close()
  edge.fill()
}

// 大腸包小腸：切開的糯米腸夾著台式香腸，上面有酸菜和蒜片
render("sausage_bun") { ctx in
  ctx.saveGState()
  ctx.translateBy(x: size / 2, y: size / 2)
  ctx.rotate(by: 0.32)

  let bunRect = NSRect(x: -226, y: -92, width: 452, height: 184)
  let bun = NSBezierPath(roundedRect: bunRect, xRadius: 88, yRadius: 88)
  ctx.saveGState()
  ctx.setShadow(offset: CGSize(width: 0, height: -10), blur: 18, color: color(0x000000, 0.35).cgColor)
  color(0xF0E2C8).setFill()
  bun.fill()
  ctx.restoreGState()
  NSGradient(colors: [color(0xF7ECD8), color(0xE3CDA6), color(0xB98C57)])!.draw(in: bun, angle: 90)
  // 糯米的顆粒
  ctx.saveGState()
  bun.addClip()
  color(0xC9A877, 0.8).setFill()
  for i in 0..<60 {
    let fx = CGFloat((i * 61) % 450) - 225
    let fy = CGFloat((i * 83) % 184) - 92
    ctx.saveGState()
    ctx.translateBy(x: fx, y: fy)
    ctx.rotate(by: CGFloat(i))
    ellipse(0, 0, 12, 6).fill()
    ctx.restoreGState()
  }
  // 切開的深色開口
  color(0x7A4A24).setFill()
  NSBezierPath(roundedRect: NSRect(x: -196, y: -30, width: 392, height: 76), xRadius: 38, yRadius: 38).fill()
  ctx.restoreGState()

  // 香腸
  let sausage = NSBezierPath(roundedRect: NSRect(x: -206, y: -16, width: 412, height: 76), xRadius: 38, yRadius: 38)
  NSGradient(colors: [color(0xD85A45), color(0xB5311F), color(0x7E1C12)])!.draw(in: sausage, angle: -90)
  color(0xF28F76, 0.7).setFill()
  NSBezierPath(roundedRect: NSRect(x: -160, y: 34, width: 240, height: 10), xRadius: 5, yRadius: 5).fill()
  // 烤痕
  color(0x5A120A, 0.75).setFill()
  for i in 0..<5 {
    let hx = -150 + CGFloat(i) * 76
    let mark = NSBezierPath()
    mark.move(to: NSPoint(x: hx, y: -8))
    mark.line(to: NSPoint(x: hx + 26, y: 52))
    stroke(mark, color(0x5A120A, 0.75), 8)
  }
  // 酸菜
  for (x, a) in [(-120.0, 0.4), (-70.0, -0.5), (-10.0, 0.7), (56.0, -0.3), (118.0, 0.5)] as [(CGFloat, CGFloat)] {
    ctx.saveGState()
    ctx.translateBy(x: x, y: 58)
    ctx.rotate(by: a)
    color(0x7DB84A).setFill()
    NSBezierPath(roundedRect: NSRect(x: -30, y: -9, width: 60, height: 18), xRadius: 9, yRadius: 9).fill()
    ctx.restoreGState()
  }
  // 蒜片
  for (x, y) in [(-92.0, 40.0), (24.0, 44.0), (88.0, 36.0)] as [(CGFloat, CGFloat)] {
    color(0xFFF7E6).setFill()
    ellipse(x, y, 20, 14).fill()
    stroke(ellipse(x, y, 20, 14), color(0xE0CFA8), 2)
  }
  ctx.restoreGState()
}

// 牛肉麵：青花碗裝的紅燒湯麵，有大塊牛肉、青江菜和筷子
render("beef_noodles") { ctx in
  let cx = size / 2
  let rimY: CGFloat = 300, rx: CGFloat = 228, ry: CGFloat = 92

  // 碗身
  let bowl = NSBezierPath()
  bowl.move(to: NSPoint(x: cx - rx, y: rimY))
  bowl.curve(to: NSPoint(x: cx - 84, y: 62), controlPoint1: NSPoint(x: cx - rx + 8, y: 190), controlPoint2: NSPoint(x: cx - 150, y: 92))
  bowl.line(to: NSPoint(x: cx + 84, y: 62))
  bowl.curve(to: NSPoint(x: cx + rx, y: rimY), controlPoint1: NSPoint(x: cx + 150, y: 92), controlPoint2: NSPoint(x: cx + rx - 8, y: 190))
  bowl.close()
  ctx.saveGState()
  ctx.setShadow(offset: CGSize(width: 0, height: -10), blur: 20, color: color(0x000000, 0.35).cgColor)
  color(0xF7F8FA).setFill()
  bowl.fill()
  ctx.restoreGState()
  NSGradient(colors: [color(0xC8D2DC), color(0xFFFFFF), color(0xD3DBE3)])!.draw(in: bowl, angle: 0)
  // 青花花紋
  ctx.saveGState()
  bowl.addClip()
  let pattern = wave([NSPoint(x: cx - 220, y: 196), NSPoint(x: cx - 150, y: 164), NSPoint(x: cx - 80, y: 196),
                      NSPoint(x: cx - 10, y: 164), NSPoint(x: cx + 60, y: 196), NSPoint(x: cx + 130, y: 164), NSPoint(x: cx + 210, y: 196)])
  stroke(pattern, color(0x2F68A8), 13)
  color(0x2F68A8).setFill()
  NSBezierPath(rect: NSRect(x: cx - 100, y: 62, width: 200, height: 20)).fill()
  ctx.restoreGState()
  // 碗底
  color(0xB9C4CF).setFill()
  NSBezierPath(roundedRect: NSRect(x: cx - 80, y: 44, width: 160, height: 24), xRadius: 8, yRadius: 8).fill()

  // 碗口和湯
  color(0xFFFFFF).setFill()
  ellipse(cx, rimY, rx, ry).fill()
  stroke(ellipse(cx, rimY, rx, ry), color(0x2F68A8), 6)
  let soup = ellipse(cx, rimY - 2, rx - 22, ry - 15)
  NSGradient(colors: [color(0x7A2F14), color(0xA04A1E)])!.draw(in: soup, angle: 90)

  ctx.saveGState()
  soup.addClip()
  // 麵條
  for i in 0..<6 {
    let y = rimY - 44 + CGFloat(i) * 15
    stroke(wave([NSPoint(x: cx - 200, y: y), NSPoint(x: cx - 110, y: y + 14), NSPoint(x: cx - 20, y: y - 8), NSPoint(x: cx + 80, y: y + 12)]),
           color(0xF3D88E), 9)
  }
  // 浮油
  color(0xE8A23C, 0.6).setFill()
  for (x, y, r) in [(120.0, 30.0, 13.0), (150.0, -6.0, 9.0), (64.0, -46.0, 10.0)] as [(CGFloat, CGFloat, CGFloat)] {
    ellipse(cx + x, rimY + y, r, r * 0.6).fill()
  }
  // 牛肉
  for (x, y, a) in [(-6.0, 26.0, 0.2), (86.0, 6.0, -0.15), (24.0, -36.0, 0.1)] as [(CGFloat, CGFloat, CGFloat)] {
    ctx.saveGState()
    ctx.translateBy(x: cx + x, y: rimY + y)
    ctx.rotate(by: a)
    let beef = NSBezierPath(roundedRect: NSRect(x: -54, y: -30, width: 108, height: 60), xRadius: 22, yRadius: 22)
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -4), blur: 8, color: color(0x000000, 0.45).cgColor)
    color(0x6E3216).setFill()
    beef.fill()
    ctx.restoreGState()
    NSGradient(colors: [color(0x9A5228), color(0x6A2E14)])!.draw(in: beef, angle: -80)
    color(0xE7C39A, 0.8).setFill()
    NSBezierPath(roundedRect: NSRect(x: -36, y: -4, width: 72, height: 7), xRadius: 3, yRadius: 3).fill()
    ctx.restoreGState()
  }
  // 青江菜
  for (x, y, a) in [(-124.0, -22.0, 0.3), (-164.0, 14.0, -0.3)] as [(CGFloat, CGFloat, CGFloat)] {
    ctx.saveGState()
    ctx.translateBy(x: cx + x, y: rimY + y)
    ctx.rotate(by: a)
    color(0xD8EDB8).setFill()
    NSBezierPath(roundedRect: NSRect(x: -40, y: -9, width: 80, height: 18), xRadius: 9, yRadius: 9).fill()
    color(0x3F9E3A).setFill()
    ellipse(-46, 0, 40, 22).fill()
    ctx.restoreGState()
  }
  ctx.restoreGState()

  // 筷子
  for dx in [CGFloat(0), 34] {
    let chop = NSBezierPath()
    chop.move(to: NSPoint(x: cx + 112 + dx, y: 492))
    chop.line(to: NSPoint(x: cx + 16 + dx * 0.4, y: rimY + 8))
    stroke(chop, color(0x7A3B1C), 13)
  }
}


func dropShadow(_ ctx: CGContext, blur: CGFloat = 18, alpha: CGFloat = 0.3, _ body: () -> Void) {
  ctx.saveGState()
  ctx.setShadow(offset: CGSize(width: 0, height: -8), blur: blur, color: color(0x000000, alpha).cgColor)
  body()
  ctx.restoreGState()
}

func rotated(_ ctx: CGContext, _ x: CGFloat, _ y: CGFloat, _ angle: CGFloat, _ body: () -> Void) {
  ctx.saveGState()
  ctx.translateBy(x: x, y: y)
  ctx.rotate(by: angle)
  body()
  ctx.restoreGState()
}

// 雞排：比手掌還大的金黃酥脆炸雞排，撒胡椒鹽
render("chicken_cutlet") { ctx in
  let cx = size / 2, cy = size / 2
  let cutlet = blob(cx, cy, 214, 182, wobble: 0.1, seed: 4)
  dropShadow(ctx) { color(0xC77F2B).setFill(); cutlet.fill() }
  NSGradient(colors: [color(0xF6C766), color(0xE39A36), color(0xB76A1F)])!
    .draw(in: cutlet, relativeCenterPosition: NSPoint(x: -0.2, y: 0.25))
  ctx.saveGState()
  cutlet.addClip()
  // 酥脆的麵衣顆粒
  for i in 0..<130 {
    let x = CGFloat((i * 73) % 430) + 41, y = CGFloat((i * 139) % 380) + 66
    let r = 9 + CGFloat(i % 4) * 4
    color(i % 3 == 0 ? 0xFFD98A : 0xC67A26, 0.75).setFill()
    blob(x, y, r, r * 0.8, wobble: 0.15, seed: i).fill()
  }
  // 胡椒鹽
  for i in 0..<70 {
    let x = CGFloat((i * 113) % 400) + 56, y = CGFloat((i * 59) % 360) + 76
    color(i % 4 == 0 ? 0x8C2A1A : 0x3A2A1C).setFill()
    ellipse(x, y, 4, 3).fill()
  }
  ctx.restoreGState()
}

// 珍珠奶茶：封膜塑膠杯、粗吸管、杯底的黑糖珍珠
render("bubble_tea") { ctx in
  let cx = size / 2
  let top: CGFloat = 400, bottom: CGFloat = 40, tw: CGFloat = 138, bw: CGFloat = 100
  // 粗吸管
  rotated(ctx, cx + 38, 330, -0.13) {
    color(0xE8432F).setFill()
    NSBezierPath(roundedRect: NSRect(x: -18, y: -150, width: 36, height: 320), xRadius: 8, yRadius: 8).fill()
  }
  let cup = NSBezierPath()
  cup.move(to: NSPoint(x: cx - tw, y: top))
  cup.line(to: NSPoint(x: cx - bw, y: bottom + 20))
  cup.curve(to: NSPoint(x: cx - bw + 22, y: bottom), controlPoint1: NSPoint(x: cx - bw, y: bottom + 6), controlPoint2: NSPoint(x: cx - bw + 8, y: bottom))
  cup.line(to: NSPoint(x: cx + bw - 22, y: bottom))
  cup.curve(to: NSPoint(x: cx + bw, y: bottom + 20), controlPoint1: NSPoint(x: cx + bw - 8, y: bottom), controlPoint2: NSPoint(x: cx + bw, y: bottom + 6))
  cup.line(to: NSPoint(x: cx + tw, y: top))
  cup.close()
  dropShadow(ctx) { color(0xD9A873).setFill(); cup.fill() }
  NSGradient(colors: [color(0xC08A55), color(0xDDB184), color(0xEBC79F)])!.draw(in: cup, angle: 90)
  ctx.saveGState()
  cup.addClip()
  // 吸管在奶茶裡的影子
  rotated(ctx, cx + 38, 330, -0.13) {
    color(0xB23A26, 0.4).setFill()
    NSBezierPath(rect: NSRect(x: -18, y: -300, width: 36, height: 300)).fill()
  }
  // 珍珠
  for (i, row) in [(46.0, 6), (88.0, 6), (128.0, 5), (168.0, 3)].enumerated() {
    let (y, count) = row
    let start = cx - CGFloat(count - 1) * 18 + (i % 2 == 0 ? 0 : 6)
    for j in 0..<count {
      let x = start + CGFloat(j) * 36
      NSGradient(colors: [color(0x5A3A2A), color(0x1E120C)])!.draw(in: ellipse(x, CGFloat(y) + 14, 21, 20), relativeCenterPosition: NSPoint(x: -0.3, y: 0.3))
      color(0xFFFFFF, 0.5).setFill()
      ellipse(x - 7, CGFloat(y) + 21, 4, 3).fill()
    }
  }
  // 反光
  color(0xFFFFFF, 0.35).setFill()
  NSBezierPath(roundedRect: NSRect(x: cx - 100, y: 130, width: 20, height: 230), xRadius: 10, yRadius: 10).fill()
  ctx.restoreGState()
  // 封膜
  color(0xF4EEE3).setFill()
  NSBezierPath(roundedRect: NSRect(x: cx - tw - 8, y: top - 8, width: tw * 2 + 16, height: 26), xRadius: 12, yRadius: 12).fill()
  color(0xE8432F).setFill()
  NSBezierPath(roundedRect: NSRect(x: cx - 40, y: top - 2, width: 80, height: 14), xRadius: 7, yRadius: 7).fill()
  rotated(ctx, cx + 38, 330, -0.13) {
    color(0xE8432F).setFill()
    NSBezierPath(roundedRect: NSRect(x: -18, y: 60, width: 36, height: 110), xRadius: 8, yRadius: 8).fill()
  }
}

// 烤魷魚：整隻串在竹籤上，刷上醬汁
render("grilled_squid") { ctx in
  rotated(ctx, size / 2, size / 2, -0.32) {
    color(0xD8B47A).setFill()
    NSBezierPath(roundedRect: NSRect(x: -8, y: -250, width: 16, height: 460), xRadius: 6, yRadius: 6).fill()
    // 觸手
    for (i, dx) in [-58.0, -34.0, -11.0, 12.0, 35.0, 58.0].enumerated() {
      let x = CGFloat(dx)
      let t = NSBezierPath()
      t.move(to: NSPoint(x: x * 0.8, y: -60))
      t.curve(to: NSPoint(x: x * 1.5 + (i % 2 == 0 ? -8 : 8), y: -206),
              controlPoint1: NSPoint(x: x * 1.3, y: -110), controlPoint2: NSPoint(x: x * 0.9, y: -160))
      dropShadow(ctx, blur: 6, alpha: 0.2) { stroke(t, color(0xA2522A), 20) }
      stroke(t, color(0xCE7C42), 9)
    }
    // 身體
    let body = NSBezierPath()
    body.move(to: NSPoint(x: 0, y: 214))
    body.curve(to: NSPoint(x: 84, y: -40), controlPoint1: NSPoint(x: 56, y: 150), controlPoint2: NSPoint(x: 92, y: 60))
    body.curve(to: NSPoint(x: -84, y: -40), controlPoint1: NSPoint(x: 66, y: -92), controlPoint2: NSPoint(x: -66, y: -92))
    body.curve(to: NSPoint(x: 0, y: 214), controlPoint1: NSPoint(x: -92, y: 60), controlPoint2: NSPoint(x: -56, y: 150))
    body.close()
    dropShadow(ctx) { color(0xB5612F).setFill(); body.fill() }
    NSGradient(colors: [color(0xE9A25C), color(0xC8703A), color(0x9A4A22)])!.draw(in: body, angle: -10)
    ctx.saveGState()
    body.addClip()
    // 交叉刀紋
    for i in -8...8 {
      let y = CGFloat(i) * 34
      let a = NSBezierPath(); a.move(to: NSPoint(x: -120, y: y - 60)); a.line(to: NSPoint(x: 120, y: y + 60))
      stroke(a, color(0x7A3618, 0.65), 6)
      let b = NSBezierPath(); b.move(to: NSPoint(x: -120, y: y + 60)); b.line(to: NSPoint(x: 120, y: y - 60))
      stroke(b, color(0x7A3618, 0.65), 6)
    }
    color(0xFFD9A8, 0.35).setFill()
    NSBezierPath(roundedRect: NSRect(x: -56, y: -30, width: 22, height: 160), xRadius: 11, yRadius: 11).fill()
    ctx.restoreGState()
    // 鰭
    for sx in [CGFloat(-1), 1] {
      let fin = NSBezierPath()
      fin.move(to: NSPoint(x: 0, y: 220))
      fin.curve(to: NSPoint(x: sx * 72, y: 104), controlPoint1: NSPoint(x: sx * 62, y: 216), controlPoint2: NSPoint(x: sx * 92, y: 158))
      fin.line(to: NSPoint(x: sx * 40, y: 124))
      fin.close()
      color(0xB5612F).setFill()
      fin.fill()
    }
  }
}

// 糖葫蘆：竹籤串著裹上透明糖衣的紅果實
render("tanghulu") { ctx in
  rotated(ctx, size / 2, size / 2, -0.24) {
    color(0xD8B47A).setFill()
    NSBezierPath(roundedRect: NSRect(x: -8, y: -250, width: 16, height: 480), xRadius: 6, yRadius: 6).fill()
    for (i, y) in [150.0, 62.0, -26.0, -114.0].enumerated() {
      let r: CGFloat = i == 0 ? 56 : 66
      let berry = blob(0, CGFloat(y), r, r * 0.92, wobble: 0.03, seed: i)
      dropShadow(ctx, blur: 12) { color(0xB81E1A).setFill(); berry.fill() }
      NSGradient(colors: [color(0xF26A55), color(0xD92B22), color(0x8E1212)])!
        .draw(in: berry, relativeCenterPosition: NSPoint(x: -0.3, y: 0.35))
      // 糖衣反光
      color(0xFFFFFF, 0.75).setFill()
      ellipse(-r * 0.36, CGFloat(y) + r * 0.42, r * 0.24, r * 0.15).fill()
      color(0xFFFFFF, 0.35).setFill()
      ellipse(r * 0.34, CGFloat(y) - r * 0.4, r * 0.15, r * 0.09).fill()
    }
  }
}

// 烤玉米：刷上醬汁、帶焦色的玉米
render("grilled_corn") { ctx in
  rotated(ctx, size / 2, size / 2, -0.5) {
    color(0xD8B47A).setFill()
    NSBezierPath(roundedRect: NSRect(x: -9, y: -250, width: 18, height: 130), xRadius: 6, yRadius: 6).fill()
    let cob = NSBezierPath(roundedRect: NSRect(x: -94, y: -170, width: 188, height: 396), xRadius: 90, yRadius: 90)
    dropShadow(ctx) { color(0x9A5A22).setFill(); cob.fill() }
    color(0x7A4318).setFill()
    cob.fill()
    ctx.saveGState()
    cob.addClip()
    // 玉米粒
    var row = 0
    var y: CGFloat = -180
    while y < 236 {
      var x: CGFloat = -112 + (row % 2 == 0 ? 0 : 18)
      while x < 112 {
        let edge = abs(x) / 112
        let burnt = (Int(x + 200) * 7 + row * 13) % 5 == 0
        let c = burnt ? color(0x7E4516) : color(edge > 0.7 ? 0xC9892C : 0xE7AE3F)
        c.setFill()
        NSBezierPath(roundedRect: NSRect(x: x - 16, y: y - 15, width: 32, height: 30), xRadius: 11, yRadius: 11).fill()
        color(0xFFE29A, burnt ? 0.15 : 0.6).setFill()
        ellipse(x - 5, y + 6, 6, 4).fill()
        x += 36
      }
      y += 33
      row += 1
    }
    ctx.restoreGState()
  }
}

// 芒果冰：玻璃碗裡的綿密冰山，鋪滿芒果丁、淋煉乳
render("mango_ice") { ctx in
  let cx = size / 2
  // 冰山
  let ice = NSBezierPath()
  ice.move(to: NSPoint(x: cx - 196, y: 198))
  ice.curve(to: NSPoint(x: cx, y: 452), controlPoint1: NSPoint(x: cx - 176, y: 340), controlPoint2: NSPoint(x: cx - 96, y: 452))
  ice.curve(to: NSPoint(x: cx + 196, y: 198), controlPoint1: NSPoint(x: cx + 96, y: 452), controlPoint2: NSPoint(x: cx + 176, y: 340))
  ice.close()
  color(0xFFD56B).setFill()
  ice.fill()
  NSGradient(colors: [color(0xFFE9A6), color(0xFFC94F)])!.draw(in: ice, angle: -90)
  // 芒果丁
  let cubes: [(CGFloat, CGFloat, CGFloat)] = [(-120, 232, 0.2), (-44, 226, -0.3), (40, 232, 0.4), (122, 228, -0.2), (-84, 300, 0.5),
                                              (2, 302, -0.2), (88, 298, 0.3), (-40, 372, -0.4), (46, 372, 0.2), (0, 426, 0.5)]
  for (x, y, a) in cubes {
    rotated(ctx, cx + x, y, a) {
      let cube = NSBezierPath(roundedRect: NSRect(x: -42, y: -38, width: 84, height: 76), xRadius: 15, yRadius: 15)
      dropShadow(ctx, blur: 8, alpha: 0.25) { color(0xF28A1E).setFill(); cube.fill() }
      NSGradient(colors: [color(0xFFB83F), color(0xF2851C)])!.draw(in: cube, angle: -70)
      color(0xFFE3A0, 0.8).setFill()
      NSBezierPath(roundedRect: NSRect(x: -28, y: 14, width: 34, height: 11), xRadius: 5, yRadius: 5).fill()
    }
  }
  // 煉乳
  let milk = wave([NSPoint(x: cx - 100, y: 276), NSPoint(x: cx - 40, y: 340), NSPoint(x: cx + 20, y: 270), NSPoint(x: cx + 70, y: 346), NSPoint(x: cx + 116, y: 284)])
  stroke(milk, color(0xFFF8E6), 16)
  // 玻璃碗
  let bowl = NSBezierPath()
  bowl.move(to: NSPoint(x: cx - 224, y: 204))
  bowl.curve(to: NSPoint(x: cx - 62, y: 72), controlPoint1: NSPoint(x: cx - 216, y: 130), controlPoint2: NSPoint(x: cx - 130, y: 84))
  bowl.line(to: NSPoint(x: cx - 62, y: 44))
  bowl.line(to: NSPoint(x: cx + 62, y: 44))
  bowl.line(to: NSPoint(x: cx + 62, y: 72))
  bowl.curve(to: NSPoint(x: cx + 224, y: 204), controlPoint1: NSPoint(x: cx + 130, y: 84), controlPoint2: NSPoint(x: cx + 216, y: 130))
  bowl.close()
  dropShadow(ctx) { color(0xCFE6F2).setFill(); bowl.fill() }
  NSGradient(colors: [color(0xA9D3E8), color(0xE7F4FA), color(0xA9D3E8)])!.draw(in: bowl, angle: 0)
  color(0xFFFFFF, 0.8).setFill()
  NSBezierPath(roundedRect: NSRect(x: cx - 236, y: 194, width: 472, height: 20), xRadius: 10, yRadius: 10).fill()
  NSBezierPath(roundedRect: NSRect(x: cx - 88, y: 34, width: 176, height: 16), xRadius: 8, yRadius: 8).fill()
}

// 地瓜球：紙杯裝的金黃膨膨小球，插竹籤
render("sweet_potato_balls") { ctx in
  let cx = size / 2
  func ball(_ x: CGFloat, _ y: CGFloat, _ r: CGFloat) {
    let b = ellipse(x, y, r, r)
    dropShadow(ctx, blur: 8, alpha: 0.3) { color(0xD98C22).setFill(); b.fill() }
    NSGradient(colors: [color(0xFFD86F), color(0xF2A52E), color(0xB86C14)])!
      .draw(in: b, relativeCenterPosition: NSPoint(x: -0.32, y: 0.36))
    color(0xFFF0B8, 0.75).setFill()
    ellipse(x - r * 0.34, y + r * 0.38, r * 0.24, r * 0.15).fill()
  }
  rotated(ctx, cx + 92, 420, -0.4) {
    color(0xD8B47A).setFill()
    NSBezierPath(roundedRect: NSRect(x: -7, y: -90, width: 14, height: 170), xRadius: 6, yRadius: 6).fill()
  }
  for (x, y, r) in [(-118.0, 322.0, 66.0), (118.0, 322.0, 66.0), (0.0, 334.0, 70.0), (-62.0, 396.0, 62.0), (62.0, 400.0, 60.0)] as [(CGFloat, CGFloat, CGFloat)] {
    ball(cx + x, y, r)
  }
  let cup = NSBezierPath()
  cup.move(to: NSPoint(x: cx - 182, y: 286))
  cup.line(to: NSPoint(x: cx + 182, y: 286))
  cup.line(to: NSPoint(x: cx + 128, y: 36))
  cup.line(to: NSPoint(x: cx - 128, y: 36))
  cup.close()
  dropShadow(ctx) { color(0xF8F1E2).setFill(); cup.fill() }
  NSGradient(colors: [color(0xFFFFFF), color(0xEADFC8)])!.draw(in: cup, angle: 0)
  ctx.saveGState()
  cup.addClip()
  color(0xE8432F).setFill()
  for i in 0..<5 {
    let x = cx - 180 + CGFloat(i) * 90
    let s = NSBezierPath()
    s.move(to: NSPoint(x: x, y: 290)); s.line(to: NSPoint(x: x + 40, y: 290))
    s.line(to: NSPoint(x: x + 34 + (x < cx ? 18 : -18), y: 30)); s.line(to: NSPoint(x: x + 6 + (x < cx ? 18 : -18), y: 30))
    s.close()
    s.fill()
  }
  ctx.restoreGState()
}

// 茶葉蛋：大理石紋路的褐色滷蛋，泡在滷汁小碗裡
render("tea_egg") { ctx in
  let cx = size / 2
  func egg(_ x: CGFloat, _ y: CGFloat, _ angle: CGFloat, _ r: CGFloat) {
    rotated(ctx, x, y, angle) {
      let shape = NSBezierPath()
      shape.move(to: NSPoint(x: 0, y: r * 1.3))
      shape.curve(to: NSPoint(x: r, y: -r * 0.1), controlPoint1: NSPoint(x: r * 0.6, y: r * 1.3), controlPoint2: NSPoint(x: r, y: r * 0.5))
      shape.curve(to: NSPoint(x: 0, y: -r), controlPoint1: NSPoint(x: r, y: -r * 0.66), controlPoint2: NSPoint(x: r * 0.56, y: -r))
      shape.curve(to: NSPoint(x: -r, y: -r * 0.1), controlPoint1: NSPoint(x: -r * 0.56, y: -r), controlPoint2: NSPoint(x: -r, y: -r * 0.66))
      shape.curve(to: NSPoint(x: 0, y: r * 1.3), controlPoint1: NSPoint(x: -r, y: r * 0.5), controlPoint2: NSPoint(x: -r * 0.6, y: r * 1.3))
      shape.close()
      dropShadow(ctx, blur: 10) { color(0xA87040).setFill(); shape.fill() }
      NSGradient(colors: [color(0xD9A873), color(0xB27A46), color(0x7E4E26)])!
        .draw(in: shape, relativeCenterPosition: NSPoint(x: -0.25, y: 0.3))
      ctx.saveGState()
      shape.addClip()
      // 大理石裂紋
      for i in 0..<16 {
        var px = CGFloat((i * 71) % Int(r * 2)) - r
        var py = CGFloat((i * 113) % Int(r * 2.3)) - r
        let line = NSBezierPath()
        line.move(to: NSPoint(x: px, y: py))
        for j in 0..<4 {
          px += CGFloat(((i + j) * 37) % 50) - 16
          py += CGFloat(((i + j * 2) * 29) % 44) - 22
          line.line(to: NSPoint(x: px, y: py))
        }
        stroke(line, color(0x4A2A14, 0.7), 4)
      }
      ctx.restoreGState()
    }
  }
  egg(cx - 72, 290, 0.2, 94)
  egg(cx + 76, 268, -0.16, 94)
  // 小碗
  let bowl = NSBezierPath()
  bowl.move(to: NSPoint(x: cx - 216, y: 236))
  bowl.curve(to: NSPoint(x: cx - 84, y: 56), controlPoint1: NSPoint(x: cx - 208, y: 136), controlPoint2: NSPoint(x: cx - 140, y: 70))
  bowl.line(to: NSPoint(x: cx + 84, y: 56))
  bowl.curve(to: NSPoint(x: cx + 216, y: 236), controlPoint1: NSPoint(x: cx + 140, y: 70), controlPoint2: NSPoint(x: cx + 208, y: 136))
  bowl.close()
  dropShadow(ctx) { color(0x6E4A30).setFill(); bowl.fill() }
  NSGradient(colors: [color(0x5A3A26), color(0x8A5C3C), color(0x5A3A26)])!.draw(in: bowl, angle: 0)
  color(0x3E2616).setFill()
  NSBezierPath(roundedRect: NSRect(x: cx - 224, y: 226, width: 448, height: 22), xRadius: 11, yRadius: 11).fill()
  color(0xFFFFFF, 0.2).setFill()
  NSBezierPath(roundedRect: NSRect(x: cx - 150, y: 120, width: 18, height: 84), xRadius: 9, yRadius: 9).fill()
}

// 炸蝦：彎彎的金黃炸蝦，紅色蝦尾
render("fried_shrimp") { ctx in
  func shrimp(_ x: CGFloat, _ y: CGFloat, _ angle: CGFloat) {
    rotated(ctx, x, y, angle) {
      // 蝦尾
      for sx in [CGFloat(-1), 1] {
        let tail = NSBezierPath()
        tail.move(to: NSPoint(x: 0, y: 148))
        tail.curve(to: NSPoint(x: sx * 62, y: 222), controlPoint1: NSPoint(x: sx * 26, y: 170), controlPoint2: NSPoint(x: sx * 60, y: 190))
        tail.curve(to: NSPoint(x: 0, y: 200), controlPoint1: NSPoint(x: sx * 40, y: 226), controlPoint2: NSPoint(x: sx * 14, y: 216))
        tail.close()
        NSGradient(colors: [color(0xF2573A), color(0xB92A1C)])!.draw(in: tail, angle: 90)
      }
      let body = NSBezierPath(roundedRect: NSRect(x: -66, y: -206, width: 132, height: 366), xRadius: 64, yRadius: 64)
      dropShadow(ctx) { color(0xC77F2B).setFill(); body.fill() }
      NSGradient(colors: [color(0xF8CE70), color(0xE8A23C), color(0xB76E22)])!.draw(in: body, angle: 0)
      ctx.saveGState()
      body.addClip()
      for i in 0..<64 {
        let bx = CGFloat((i * 47) % 130) - 65, by = CGFloat((i * 89) % 366) - 206
        let r = 10 + CGFloat(i % 3) * 3
        color(i % 2 == 0 ? 0xFFE09A : 0xC67F26, 0.75).setFill()
        blob(bx, by, r, r * 0.8, wobble: 0.15, seed: i).fill()
      }
      ctx.restoreGState()
    }
  }
  shrimp(170, 236, 0.22)
  shrimp(342, 236, -0.22)
}

// 霜淇淋：格紋餅乾甜筒上的螺旋霜淇淋
render("soft_serve") { ctx in
  let cx = size / 2
  // 甜筒
  let cone = NSBezierPath()
  cone.move(to: NSPoint(x: cx - 112, y: 262))
  cone.line(to: NSPoint(x: cx + 112, y: 262))
  cone.line(to: NSPoint(x: cx, y: 24))
  cone.close()
  dropShadow(ctx) { color(0xD8A24F).setFill(); cone.fill() }
  NSGradient(colors: [color(0xEFC070), color(0xCF9440)])!.draw(in: cone, angle: 0)
  ctx.saveGState()
  cone.addClip()
  for i in -6...8 {
    let d = CGFloat(i) * 44
    let a = NSBezierPath(); a.move(to: NSPoint(x: cx - 160 + d, y: 280)); a.line(to: NSPoint(x: cx + d, y: 0))
    stroke(a, color(0xA8702A), 5)
    let b = NSBezierPath(); b.move(to: NSPoint(x: cx + 160 - d, y: 280)); b.line(to: NSPoint(x: cx - d, y: 0))
    stroke(b, color(0xA8702A), 5)
  }
  ctx.restoreGState()
  // 螺旋：由下往上越來越小
  let layers: [(CGFloat, CGFloat, CGFloat)] = [(274, 142, 52), (332, 112, 46), (384, 80, 40)]
  for (y, rx, ry) in layers {
    let layer = NSBezierPath(roundedRect: NSRect(x: cx - rx, y: y - ry, width: rx * 2, height: ry * 2), xRadius: ry, yRadius: ry)
    dropShadow(ctx, blur: 8, alpha: 0.18) { color(0xFFF9EC).setFill(); layer.fill() }
    NSGradient(colors: [color(0xFFFFFF), color(0xF6E8CC)])!.draw(in: layer, angle: -90)
    let groove = NSBezierPath()
    groove.move(to: NSPoint(x: cx - rx * 0.86, y: y - ry * 0.3))
    groove.curve(to: NSPoint(x: cx + rx * 0.86, y: y + ry * 0.3), controlPoint1: NSPoint(x: cx - rx * 0.3, y: y - ry * 0.5), controlPoint2: NSPoint(x: cx + rx * 0.3, y: y + ry * 0.1))
    stroke(groove, color(0xE2CFA8), 5)
  }
  // 尖端
  let tip = NSBezierPath()
  tip.move(to: NSPoint(x: cx - 50, y: 418))
  tip.curve(to: NSPoint(x: cx + 22, y: 492), controlPoint1: NSPoint(x: cx - 34, y: 462), controlPoint2: NSPoint(x: cx - 6, y: 474))
  tip.curve(to: NSPoint(x: cx + 50, y: 418), controlPoint1: NSPoint(x: cx + 30, y: 466), controlPoint2: NSPoint(x: cx + 46, y: 450))
  tip.close()
  NSGradient(colors: [color(0xFFFFFF), color(0xF6E8CC)])!.draw(in: tip, angle: -90)
}

// 烤肉串：肉塊和蔥段交錯，帶焦香
render("meat_skewer") { ctx in
  func skewer(_ x: CGFloat, _ angle: CGFloat) {
    rotated(ctx, x, 262, angle) {
      color(0xD8B47A).setFill()
      NSBezierPath(roundedRect: NSRect(x: -7, y: -240, width: 14, height: 470), xRadius: 6, yRadius: 6).fill()
      for (i, y) in [136.0, 58.0, -20.0, -98.0].enumerated() {
        if i % 2 == 1 {
          // 蔥段
          let scallion = NSBezierPath(roundedRect: NSRect(x: -58, y: CGFloat(y) - 24, width: 116, height: 48), xRadius: 22, yRadius: 22)
          dropShadow(ctx, blur: 6, alpha: 0.25) { color(0x8FC45A).setFill(); scallion.fill() }
          NSGradient(colors: [color(0xE4F2C2), color(0x8FC45A), color(0xE4F2C2)])!.draw(in: scallion, angle: 0)
          color(0x7A4A1E, 0.7).setFill()
          NSBezierPath(roundedRect: NSRect(x: -24, y: CGFloat(y) - 20, width: 14, height: 40), xRadius: 6, yRadius: 6).fill()
        } else {
          let meat = blob(0, CGFloat(y), 76, 44, wobble: 0.08, seed: i + 2)
          dropShadow(ctx, blur: 8) { color(0x7E3C1A).setFill(); meat.fill() }
          NSGradient(colors: [color(0xB9652F), color(0x8A431E), color(0x5E2A10)])!.draw(in: meat, angle: -70)
          color(0x2E1408, 0.75).setFill()
          for j in 0..<3 {
            NSBezierPath(roundedRect: NSRect(x: -46 + CGFloat(j) * 34, y: CGFloat(y) - 24, width: 9, height: 48), xRadius: 4, yRadius: 4).fill()
          }
          color(0xF6D9A8, 0.75).setFill()
          ellipse(-30, CGFloat(y) + 20, 15, 5).fill()
          for j in 0..<6 {
            ellipse(CGFloat((j * 37) % 110) - 54, CGFloat(y) + CGFloat((j * 23) % 60) - 30, 3, 2).fill()
          }
        }
      }
    }
  }
  skewer(180, 0.2)
  skewer(332, -0.2)
}

// 布丁：盤子上的雞蛋布丁，頂端有焦糖往下流
render("pudding") { ctx in
  let cx = size / 2
  dropShadow(ctx) { color(0xFFFFFF).setFill(); ellipse(cx, 92, 214, 56).fill() }
  stroke(ellipse(cx, 92, 214, 56), color(0x3F7FB5), 6)
  let body = NSBezierPath()
  body.move(to: NSPoint(x: cx - 166, y: 104))
  body.curve(to: NSPoint(x: cx - 112, y: 372), controlPoint1: NSPoint(x: cx - 154, y: 200), controlPoint2: NSPoint(x: cx - 136, y: 320))
  body.curve(to: NSPoint(x: cx + 112, y: 372), controlPoint1: NSPoint(x: cx - 60, y: 400), controlPoint2: NSPoint(x: cx + 60, y: 400))
  body.curve(to: NSPoint(x: cx + 166, y: 104), controlPoint1: NSPoint(x: cx + 136, y: 320), controlPoint2: NSPoint(x: cx + 154, y: 200))
  body.curve(to: NSPoint(x: cx - 166, y: 104), controlPoint1: NSPoint(x: cx + 80, y: 78), controlPoint2: NSPoint(x: cx - 80, y: 78))
  body.close()
  NSGradient(colors: [color(0xE8AE3C), color(0xFFD86A), color(0xE8AE3C)])!.draw(in: body, angle: 0)
  ctx.saveGState()
  body.addClip()
  // 焦糖
  let caramel = NSBezierPath()
  caramel.move(to: NSPoint(x: cx - 170, y: 420))
  caramel.line(to: NSPoint(x: cx + 170, y: 420))
  caramel.line(to: NSPoint(x: cx + 170, y: 292))
  for (x, y) in [(112.0, 248.0), (70.0, 300.0), (24.0, 214.0), (-26.0, 292.0), (-74.0, 240.0), (-120.0, 296.0), (-170.0, 262.0)] as [(CGFloat, CGFloat)] {
    let cur = caramel.currentPoint
    caramel.curve(to: NSPoint(x: cx + x, y: y), controlPoint1: NSPoint(x: cur.x, y: y), controlPoint2: NSPoint(x: cx + x, y: cur.y))
  }
  caramel.close()
  NSGradient(colors: [color(0x5E2A0E), color(0x9A4E17)])!.draw(in: caramel, angle: -90)
  color(0xFFFFFF, 0.45).setFill()
  NSBezierPath(roundedRect: NSRect(x: cx - 104, y: 150, width: 20, height: 104), xRadius: 10, yRadius: 10).fill()
  color(0xFFFFFF, 0.35).setFill()
  ellipse(cx - 40, 360, 56, 11).fill()
  ctx.restoreGState()
}

print("done")
