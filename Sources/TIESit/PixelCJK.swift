import SwiftUI
import AppKit
import CoreText

// 中文先绘制为无抗锯齿的点阵，再按整倍像素放大；不依赖额外字体资源。
struct PixelCJK: View {
    let text: String
    var grid: Int = 16
    var scale: CGFloat = 1
    var color: Color = PX.chalk
    var spacing: CGFloat = 6
    var alignment: HorizontalAlignment = .leading

    init(_ text: String, grid: Int = 16, scale: CGFloat = 1, color: Color = PX.chalk,
         spacing: CGFloat = 6, alignment: HorizontalAlignment = .leading) {
        self.text = text
        self.grid = grid
        self.scale = scale
        self.color = color
        self.spacing = spacing
        self.alignment = alignment
    }

    var body: some View {
        VStack(alignment: alignment, spacing: spacing) {
            ForEach(Array(text.components(separatedBy: "\n").enumerated()), id: \.offset) { _, line in
                let bitmap = PixelCJKBitmap.image(line, grid: grid)
                Image(decorative: bitmap, scale: 1)
                    .resizable().interpolation(.none).renderingMode(.template)
                    .foregroundColor(color)
                    .frame(width: CGFloat(bitmap.width) * scale, height: CGFloat(grid) * scale)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(text)
    }
}

private enum PixelCJKBitmap {
    private static var cache: [String: CGImage] = [:]

    static func image(_ text: String, grid: Int) -> CGImage {
        let key = "\(grid):\(text)"
        if let cached = cache[key] { return cached }
        let characters = Array(text)
        let widths = characters.map { $0.isASCII ? max(5, grid / 2) : grid }
        let width = max(1, widths.reduce(0, +))
        let context = CGContext(data: nil, width: width, height: grid, bitsPerComponent: 8,
                                bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(),
                                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.setShouldAntialias(false)
        context.setShouldSmoothFonts(false)
        context.setShouldSubpixelPositionFonts(false)
        context.setShouldSubpixelQuantizeFonts(true)
        context.setFillColor(CGColor(gray: 1, alpha: 1))
        let font = CTFontCreateWithName("PingFangSC-Medium" as CFString, CGFloat(grid - 2), nil)
        var cursor: CGFloat = 0
        for (index, character) in characters.enumerated() {
            let attributes: [NSAttributedString.Key: Any] = [
                NSAttributedString.Key(kCTFontAttributeName as String): font,
                NSAttributedString.Key(kCTForegroundColorAttributeName as String): CGColor(gray: 1, alpha: 1),
            ]
            let line = CTLineCreateWithAttributedString(NSAttributedString(string: String(character), attributes: attributes))
            let bounds = CTLineGetBoundsWithOptions(line, .useGlyphPathBounds)
            context.textPosition = CGPoint(x: cursor + floor((CGFloat(widths[index]) - bounds.width) / 2) - bounds.minX,
                                           y: floor((CGFloat(grid) - bounds.height) / 2) - bounds.minY)
            CTLineDraw(line, context)
            cursor += CGFloat(widths[index])
        }
        let image = context.makeImage()!
        // 文案中含倒计时数字，避免长期运行时无限缓存。
        if cache.count > 384 { cache.removeAll(keepingCapacity: true) }
        cache[key] = image
        return image
    }
}
