import CoreGraphics
import ImageIO
import Foundation
import UniformTypeIdentifiers

let S = 1024
let cs = CGColorSpace(name: CGColorSpace.sRGB)!
let ctx = CGContext(data: nil, width: S, height: S, bitsPerComponent: 8, bytesPerRow: 0,
                    space: cs, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!

func col(_ r: Double, _ g: Double, _ b: Double, _ a: Double = 1) -> CGColor {
    CGColor(colorSpace: cs, components: [r, g, b, a])!
}

// 背景：深色影院蓝 → 青绿渐变（对齐 App 主题 Theme.accent/bg）
let grad = CGGradient(colorsSpace: cs, colors: [
    col(0.10, 0.13, 0.18),   // 深底
    col(0.13, 0.30, 0.38),   // 中段青蓝
    col(0.21, 0.72, 0.80),   // 顶部青绿 accent
] as CFArray, locations: [0.0, 0.55, 1.0])!
ctx.drawLinearGradient(grad, start: CGPoint(x: 0, y: 0), end: CGPoint(x: CGFloat(S), y: CGFloat(S)), options: [])

let c = CGFloat(S) / 2

// 柔光圆环
ctx.setFillColor(col(1, 1, 1, 0.08))
ctx.fillEllipse(in: CGRect(x: c - 330, y: c - 330, width: 660, height: 660))
ctx.setFillColor(col(1, 1, 1, 0.12))
ctx.fillEllipse(in: CGRect(x: c - 250, y: c - 250, width: 500, height: 500))

// 中央播放三角（轻微圆角），白色
let pts = [
    CGPoint(x: c - 95, y: c + 158),   // 左上
    CGPoint(x: c - 95, y: c - 158),   // 左下
    CGPoint(x: c + 178, y: c),        // 右尖
]
let r: CGFloat = 34
let tri = CGMutablePath()
// 从第一条边的中点起，依次对每个顶点做圆角
tri.move(to: CGPoint(x: (pts[2].x + pts[0].x)/2, y: (pts[2].y + pts[0].y)/2))
tri.addArc(tangent1End: pts[0], tangent2End: pts[1], radius: r)
tri.addArc(tangent1End: pts[1], tangent2End: pts[2], radius: r)
tri.addArc(tangent1End: pts[2], tangent2End: pts[0], radius: r)
tri.closeSubpath()
ctx.setShadow(offset: CGSize(width: 0, height: -16), blur: 36, color: col(0, 0, 0, 0.30))
ctx.setFillColor(col(0.98, 0.99, 1.0, 1))
ctx.addPath(tri)
ctx.fillPath()
ctx.setShadow(offset: .zero, blur: 0, color: nil)

guard let img = ctx.makeImage() else { fatalError("no image") }
let url = URL(fileURLWithPath: "/tmp/icon_1024.png")
let dest = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil)!
CGImageDestinationAddImage(dest, img, nil)
CGImageDestinationFinalize(dest)
print("wrote /tmp/icon_1024.png")
