import CoreGraphics
import ImageIO
import Foundation
import UniformTypeIdentifiers

// App 图标：火星 + 仰望星空、伸手探索的孩子 —— 寓意"探索宇宙"
let S = 1024
let cs = CGColorSpace(name: CGColorSpace.sRGB)!
let ctx = CGContext(data: nil, width: S, height: S, bitsPerComponent: 8, bytesPerRow: 0,
                    space: cs, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
func col(_ r: Double, _ g: Double, _ b: Double, _ a: Double = 1) -> CGColor {
    CGColor(colorSpace: cs, components: [r, g, b, a])!
}
let F = CGFloat(S)

// 1) 深空背景渐变（靛蓝 → 近黑）
let bg = CGGradient(colorsSpace: cs, colors: [
    col(0.16, 0.13, 0.32),
    col(0.09, 0.08, 0.20),
    col(0.04, 0.04, 0.10),
] as CFArray, locations: [0, 0.55, 1])!
ctx.drawLinearGradient(bg, start: CGPoint(x: 0, y: F), end: CGPoint(x: 0, y: 0), options: [])

// 2) 星星（确定性散布）
let stars: [(CGFloat, CGFloat, CGFloat, Double)] = [
    (150, 880, 3, 0.8), (320, 800, 2, 0.6), (240, 700, 2.5, 0.7),
    (860, 900, 3, 0.85), (760, 700, 2, 0.6), (910, 760, 2.5, 0.7),
    (120, 560, 2, 0.5), (900, 560, 2.2, 0.6), (430, 920, 2, 0.6), (600, 880, 2.2, 0.55),
]
for (x, y, r, a) in stars {
    ctx.setFillColor(col(1, 1, 1, a))
    ctx.fillEllipse(in: CGRect(x: x - r, y: y - r, width: r * 2, height: r * 2))
}

// 3) 主星（孩子伸手够的那颗），带光晕 + 十字星芒
let starC = CGPoint(x: 720, y: 815)
let glow = CGGradient(colorsSpace: cs, colors: [
    col(1, 0.95, 0.8, 0.9), col(1, 0.9, 0.7, 0.0),
] as CFArray, locations: [0, 1])!
ctx.drawRadialGradient(glow, startCenter: starC, startRadius: 0, endCenter: starC, endRadius: 70, options: [])
ctx.setFillColor(col(1, 0.97, 0.88, 1))
ctx.fillEllipse(in: CGRect(x: starC.x - 9, y: starC.y - 9, width: 18, height: 18))
ctx.setStrokeColor(col(1, 0.97, 0.88, 0.9)); ctx.setLineWidth(4); ctx.setLineCap(.round)
ctx.move(to: CGPoint(x: starC.x - 26, y: starC.y)); ctx.addLine(to: CGPoint(x: starC.x + 26, y: starC.y))
ctx.move(to: CGPoint(x: starC.x, y: starC.y - 26)); ctx.addLine(to: CGPoint(x: starC.x, y: starC.y + 26))
ctx.strokePath()

// 4) 火星
let marsC = CGPoint(x: 512, y: 300)
let marsR: CGFloat = 308
let marsRect = CGRect(x: marsC.x - marsR, y: marsC.y - marsR, width: marsR * 2, height: marsR * 2)
let lit = CGPoint(x: marsC.x + 120, y: marsC.y + 130)   // 受光从右上（主星方向）
let marsGrad = CGGradient(colorsSpace: cs, colors: [
    col(0.86, 0.46, 0.24, 1),
    col(0.72, 0.34, 0.18, 1),
    col(0.40, 0.17, 0.12, 1),
] as CFArray, locations: [0, 0.55, 1])!
ctx.saveGState()
ctx.addEllipse(in: marsRect); ctx.clip()
ctx.drawRadialGradient(marsGrad, startCenter: lit, startRadius: 20, endCenter: marsC, endRadius: marsR * 1.15, options: [])
// 表面暗斑（maria）
let patches: [(CGFloat, CGFloat, CGFloat, CGFloat)] = [
    (430, 360, 120, 70), (560, 220, 150, 90), (380, 200, 80, 55), (640, 400, 70, 45),
]
for (x, y, w, h) in patches {
    ctx.setFillColor(col(0.30, 0.13, 0.10, 0.30))
    ctx.fillEllipse(in: CGRect(x: x - w/2, y: y - h/2, width: w, height: h))
}
// 北极冰冠
ctx.setFillColor(col(0.95, 0.93, 0.92, 0.85))
ctx.fillEllipse(in: CGRect(x: marsC.x - 60, y: marsC.y + marsR - 70, width: 120, height: 70))
ctx.restoreGState()

// 5) 站在火星上、仰望并伸手够星星的孩子（奶白剪影）
let cream = col(0.96, 0.93, 0.86, 1)
ctx.setStrokeColor(cream); ctx.setLineCap(.round); ctx.setLineJoin(.round)
let feetY = marsC.y + marsR - 6   // 站在火星顶
// 腿
ctx.setLineWidth(20)
ctx.move(to: CGPoint(x: 500, y: feetY)); ctx.addLine(to: CGPoint(x: 503, y: feetY + 48)); ctx.strokePath()
ctx.move(to: CGPoint(x: 524, y: feetY)); ctx.addLine(to: CGPoint(x: 521, y: feetY + 48)); ctx.strokePath()
// 躯干
ctx.setLineWidth(34)
let shoulderY = feetY + 110
ctx.move(to: CGPoint(x: 512, y: feetY + 44)); ctx.addLine(to: CGPoint(x: 512, y: shoulderY)); ctx.strokePath()
// 手臂：一只伸向主星（右上），一只自然下垂
ctx.setLineWidth(17)
ctx.move(to: CGPoint(x: 512, y: shoulderY - 6)); ctx.addLine(to: CGPoint(x: 612, y: shoulderY + 60)); ctx.strokePath()
ctx.move(to: CGPoint(x: 512, y: shoulderY - 6)); ctx.addLine(to: CGPoint(x: 470, y: shoulderY - 48)); ctx.strokePath()
// 头（偏大，童趣）
ctx.setFillColor(cream)
let headC = CGPoint(x: 512, y: shoulderY + 44)
ctx.fillEllipse(in: CGRect(x: headC.x - 34, y: headC.y - 34, width: 68, height: 68))

guard let img = ctx.makeImage() else { fatalError("no image") }
let url = URL(fileURLWithPath: "/tmp/icon_1024.png")
let dest = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil)!
CGImageDestinationAddImage(dest, img, nil)
CGImageDestinationFinalize(dest)
print("wrote /tmp/icon_1024.png")
