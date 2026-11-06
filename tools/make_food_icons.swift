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

print("done")
