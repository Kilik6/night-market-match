// 畫夜市翻牌的專屬小吃圖案（透明背景 PNG），取代 emoji，讓 iOS 和 Android 看起來一樣。
// 用法：swift tools/make_food_icons.swift assets/foods
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

print("done")
