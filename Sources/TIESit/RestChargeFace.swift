import SwiftUI

/// 可独立渲染的充能外观；长按计时与解锁仍由 HoldButton 管理。
struct RestChargeFace: View {
    var progress: Double
    var totalSeconds: Double
    var pressed = false
    var hovered = false
    var aborted = false

    private var charge: Double { min(1, max(0, progress)) }
    private var active: Bool { charge > 0 || pressed }

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            ZStack(alignment: .topLeading) {
                PixelControlShape().fill(Color(rgb: 0x030E16)).offset(y: 4)
                ZStack(alignment: .topLeading) {
                    PixelControlShape().fill(Color(rgb: active ? 0x203F45 : (hovered ? 0x20383E : 0x182F37)))
                    // 面板内部也会随长按逐渐充满，文字保留在填充层上方。
                    Rectangle().fill(RestTheme.mint.opacity(0.14))
                        .frame(width: max(0, (w - 12) * charge), height: 66)
                        .offset(x: 6, y: 6)
                    Canvas { context, size in
                        func rect(_ x: CGFloat, _ y: CGFloat, _ width: CGFloat, _ height: CGFloat, _ color: Color) {
                            context.fill(Path(CGRect(x: x, y: y, width: width, height: height)), with: .color(color))
                        }
                        let edge = RestTheme.mint.opacity(active ? 0.9 : (hovered ? 0.72 : 0.5))
                        // 两层斜切像素边缘、上沿高光和底部压暗，形成实体按键。
                        rect(8, 0, size.width - 16, 2, edge)
                        rect(4, 2, 4, 2, edge); rect(size.width - 8, 2, 4, 2, edge)
                        rect(2, 4, 2, 4, edge); rect(size.width - 4, 4, 2, 4, edge)
                        rect(0, 8, 2, size.height - 16, edge)
                        rect(size.width - 2, 8, 2, size.height - 16, RestTheme.quiet.opacity(0.7))
                        rect(8, size.height - 4, size.width - 16, 4, Color(rgb: 0x0A202A))
                        rect(12, 5, size.width - 24, 1, RestTheme.text.opacity(active ? 0.3 : 0.14))
                        // 咖啡图标嵌在独立凹槽中，随充能由灰绿亮到奶油色。
                        rect(12, 12, 36, 38, Color(rgb: 0x0E252E))
                        rect(12, 12, 36, 1, RestTheme.quiet.opacity(0.3))
                        let cup = active ? RestTheme.text : RestTheme.mint
                        rect(21, 27, 16, 12, cup)
                        rect(23, 39, 12, 2, cup)
                        rect(37, 28, 6, 2, cup); rect(41, 30, 2, 5, cup); rect(37, 35, 6, 2, cup)
                        rect(21, 25, 16, 2, RestTheme.sand)
                        rect(19, 43, 22, 2, RestTheme.quiet)
                        let drift: CGFloat = active ? CGFloat(Int(charge * totalSeconds * 5) % 3) : 0
                        rect(25, 18 - drift, 2, 5, cup.opacity(0.65))
                        rect(31, 16 - drift, 2, 6, cup.opacity(0.4))
                        // 深色槽底 + 逐格充能 + 明亮的前沿，不靠细边框表示进度。
                        let left: CGFloat = 14
                        let trackWidth = size.width - 28
                        rect(left - 2, 60, trackWidth + 4, 14, Color(rgb: 0x091D26))
                        let gap: CGFloat = 2
                        let cell = (trackWidth - 31 * gap) / 32
                        for index in 0..<32 {
                            let fraction = min(1, max(0, charge * 32 - Double(index)))
                            let x = left + CGFloat(index) * (cell + gap)
                            rect(x, 63, cell, 8, RestTheme.quiet.opacity(0.18))
                            if fraction > 0 {
                                rect(x, 63, max(1, (cell * fraction).rounded()), 8,
                                     index == Int(ceil(charge * 32)) - 1 ? RestTheme.sand : RestTheme.mint)
                                rect(x, 63, max(1, (cell * fraction).rounded()), 2, RestTheme.text.opacity(0.45))
                            }
                        }
                        for x in [CGFloat(7), size.width - 10] {
                            rect(x, 52, 3, 3, RestTheme.quiet.opacity(0.55))
                        }
                    }
                    VStack(alignment: .leading, spacing: 9) {
                        PixelCJK(active ? "正在充能，准备启程" : "按住，开始休息", color: RestTheme.text)
                        PixelCJK(active ? "还需 \(max(0, Int(ceil(totalSeconds * (1 - charge))))) 秒，松开可取消" :
                                 (aborted ? "已重置，准备好了再试" : "长按 \(Int(totalSeconds)) 秒，为自己充充电"), grid: 12, color: RestTheme.secondary)
                    }.offset(x: 62, y: 14)
                    if active {
                        PixelText("\(Int(charge * 100))%", scale: 1, color: RestTheme.sand)
                            .frame(width: 32, alignment: .trailing).offset(x: w - 46, y: 17)
                    }
                }
                .frame(height: 80)
                .clipShape(PixelControlShape())
                .offset(y: pressed ? 2 : 0)
            }
        }
        .frame(height: 84)
    }
}

private struct PixelControlShape: Shape {
    func path(in rect: CGRect) -> Path {
        let c: CGFloat = 8
        return Path { p in
            p.move(to: CGPoint(x: c, y: 0))
            p.addLines([CGPoint(x: rect.width - c, y: 0), CGPoint(x: rect.width - c, y: 4),
                        CGPoint(x: rect.width - 4, y: 4), CGPoint(x: rect.width - 4, y: c),
                        CGPoint(x: rect.width, y: c), CGPoint(x: rect.width, y: rect.height - c),
                        CGPoint(x: rect.width - 4, y: rect.height - c), CGPoint(x: rect.width - 4, y: rect.height - 4),
                        CGPoint(x: rect.width - c, y: rect.height - 4), CGPoint(x: rect.width - c, y: rect.height),
                        CGPoint(x: c, y: rect.height), CGPoint(x: c, y: rect.height - 4),
                        CGPoint(x: 4, y: rect.height - 4), CGPoint(x: 4, y: rect.height - c),
                        CGPoint(x: 0, y: rect.height - c), CGPoint(x: 0, y: c),
                        CGPoint(x: 4, y: c), CGPoint(x: 4, y: 4), CGPoint(x: c, y: 4)])
            p.closeSubpath()
        }
    }
}
