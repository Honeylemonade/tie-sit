import SwiftUI

// MARK: - 调色板（九色上限）

enum PX {
    static let void   = Color(rgb: 0x000000)   // 真空黑
    static let bay    = Color(rgb: 0x3C3C3C)   // 暗舱灰
    static let hull   = Color(rgb: 0x7C7C7C)   // 船体灰
    static let star   = Color(rgb: 0xBCBCBC)   // 星尘白
    static let chalk  = Color(rgb: 0xFCFCFC)   // 纯白
    static let order  = Color(rgb: 0xF8B800)   // 指令黄
    static let alert  = Color(rgb: 0xE40058)   // 帝国警报红
    static let sys    = Color(rgb: 0x3CBCFC)   // 光剑蓝
    static let ok     = Color(rgb: 0x58D854)   // 控制台绿

    static let dim = Color(rgb: 0x2A2A2A)
}

extension Color {
    init(rgb: UInt32) {
        self.init(
            .sRGB,
            red:   Double((rgb >> 16) & 0xFF) / 255.0,
            green: Double((rgb >> 8) & 0xFF) / 255.0,
            blue:  Double(rgb & 0xFF) / 255.0,
            opacity: 1.0
        )
    }
}

// MARK: - 5×7 点阵字库
//
// 自己画字而不是加载字体文件：数字和英文是可验证的 8-bit 点阵，
// 不依赖用户机器上装没装像素字体，也不会有字体渲染糊边。

enum PixelFont {

    static let glyphs: [Character: [String]] = [
        "0": ["01110","10001","10011","10101","11001","10001","01110"],
        "1": ["00100","01100","00100","00100","00100","00100","01110"],
        "2": ["01110","10001","00001","00010","00100","01000","11111"],
        "3": ["11111","00010","00100","00010","00001","10001","01110"],
        "4": ["00010","00110","01010","10010","11111","00010","00010"],
        "5": ["11111","10000","11110","00001","00001","10001","01110"],
        "6": ["00110","01000","10000","11110","10001","10001","01110"],
        "7": ["11111","00001","00010","00100","01000","01000","01000"],
        "8": ["01110","10001","10001","01110","10001","10001","01110"],
        "9": ["01110","10001","10001","01111","00001","00010","01100"],

        "A": ["01110","10001","10001","11111","10001","10001","10001"],
        "B": ["11110","10001","10001","11110","10001","10001","11110"],
        "C": ["01110","10001","10000","10000","10000","10001","01110"],
        "D": ["11110","10001","10001","10001","10001","10001","11110"],
        "E": ["11111","10000","10000","11110","10000","10000","11111"],
        "F": ["11111","10000","10000","11110","10000","10000","10000"],
        "G": ["01110","10001","10000","10111","10001","10001","01111"],
        "H": ["10001","10001","10001","11111","10001","10001","10001"],
        "I": ["01110","00100","00100","00100","00100","00100","01110"],
        "J": ["00111","00010","00010","00010","00010","10010","01100"],
        "K": ["10001","10010","10100","11000","10100","10010","10001"],
        "L": ["10000","10000","10000","10000","10000","10000","11111"],
        "M": ["10001","11011","10101","10101","10001","10001","10001"],
        "N": ["10001","11001","10101","10011","10001","10001","10001"],
        "O": ["01110","10001","10001","10001","10001","10001","01110"],
        "P": ["11110","10001","10001","11110","10000","10000","10000"],
        "Q": ["01110","10001","10001","10001","10101","10010","01101"],
        "R": ["11110","10001","10001","11110","10100","10010","10001"],
        "S": ["01111","10000","10000","01110","00001","00001","11110"],
        "T": ["11111","00100","00100","00100","00100","00100","00100"],
        "U": ["10001","10001","10001","10001","10001","10001","01110"],
        "V": ["10001","10001","10001","10001","10001","01010","00100"],
        "W": ["10001","10001","10001","10101","10101","11011","10001"],
        "X": ["10001","10001","01010","00100","01010","10001","10001"],
        "Y": ["10001","10001","01010","00100","00100","00100","00100"],
        "Z": ["11111","00001","00010","00100","01000","10000","11111"],

        ":": ["00000","00100","00100","00000","00100","00100","00000"],
        ".": ["00000","00000","00000","00000","00000","00100","00100"],
        ",": ["00000","00000","00000","00000","00100","00100","01000"],
        "/": ["00001","00010","00010","00100","01000","01000","10000"],
        "-": ["00000","00000","00000","01110","00000","00000","00000"],
        "+": ["00000","00100","00100","11111","00100","00100","00000"],
        "%": ["10001","10010","00100","00100","01000","01001","10001"],
        "!": ["00100","00100","00100","00100","00100","00000","00100"],
        "?": ["01110","10001","00001","00010","00100","00000","00100"],
        ">": ["01000","00100","00010","00001","00010","00100","01000"],
        "<": ["00010","00100","01000","10000","01000","00100","00010"],
        "*": ["00000","10101","01110","11111","01110","10101","00000"],
        "#": ["01010","01010","11111","01010","11111","01010","01010"],
        "=": ["00000","00000","11111","00000","11111","00000","00000"],
        " ": ["00000","00000","00000","00000","00000","00000","00000"],
    ]

    static let glyphW: CGFloat = 5
    static let glyphH: CGFloat = 7

    /// 一个字 = 5 个点宽，字间留 gap 个点
    static func width(_ text: String, scale: CGFloat, gap: CGFloat = 1) -> CGFloat {
        let n = CGFloat(text.count)
        guard n > 0 else { return 0 }
        return (n * (glyphW + gap) - gap) * scale
    }

    static func height(scale: CGFloat) -> CGFloat { glyphH * scale }

    static func draw(_ text: String,
                     into ctx: inout GraphicsContext,
                     at origin: CGPoint,
                     scale: CGFloat,
                     gap: CGFloat = 1,
                     color: Color) {
        var x = origin.x
        for ch in text.uppercased() {
            let rows = glyphs[ch] ?? glyphs["?"]!
            for (r, row) in rows.enumerated() {
                let rowChars = Array(row)
                for c in 0..<rowChars.count where rowChars[c] == "1" {
                    let rect = CGRect(
                        x: x + CGFloat(c) * scale,
                        y: origin.y + CGFloat(r) * scale,
                        width: scale,
                        height: scale
                    )
                    ctx.fill(Path(rect), with: .color(color))
                }
            }
            x += (glyphW + gap) * scale
        }
    }
}

// MARK: - 像素文字视图

struct PixelText: View {
    let text: String
    var scale: CGFloat = 2
    var gap: CGFloat = 1
    var color: Color = PX.chalk

    init(_ text: String, scale: CGFloat = 2, gap: CGFloat = 1, color: Color = PX.chalk) {
        self.text = text
        self.scale = scale
        self.gap = gap
        self.color = color
    }

    var body: some View {
        Canvas { ctx, _ in
            PixelFont.draw(text, into: &ctx, at: .zero, scale: scale, gap: gap, color: color)
        }
        .frame(width: PixelFont.width(text, scale: scale, gap: gap),
               height: PixelFont.height(scale: scale))
        .accessibilityLabel(text)
    }
}

// MARK: - 像素通用件

/// 2px 硬边描边，无圆角
struct PixelFrame: ViewModifier {
    var color: Color = PX.hull
    var width: CGFloat = 2

    func body(content: Content) -> some View {
        content.overlay(
            Rectangle()
                .strokeBorder(color, lineWidth: width)
        )
    }
}

extension View {
    func pixelFrame(_ color: Color = PX.hull, width: CGFloat = 2) -> some View {
        modifier(PixelFrame(color: color, width: width))
    }
}

/// CRT 扫描线。全站唯一持续性叠加层，可关闭。
struct Scanlines: View {
    var opacity: Double = 0.55

    var body: some View {
        Canvas { ctx, size in
            var y: CGFloat = 0
            let line = Path(CGRect(x: 0, y: 0, width: size.width, height: 1))
            while y < size.height {
                var p = line
                p = p.offsetBy(dx: 0, dy: y)
                ctx.fill(p, with: .color(Color.black.opacity(opacity)))
                y += 3
            }
        }
        .allowsHitTesting(false)
        .blendMode(.multiply)
    }
}

/// 20 格血条：filled 格为亮色
struct BlockBar: View {
    var progress: Double            // 0...1
    var color: Color = PX.order
    var emptyColor: Color = PX.dim
    var blocks: Int = 20
    var blockHeight: CGFloat = 14
    var gap: CGFloat = 2
    var flashing: Bool = false

    var body: some View {
        Canvas { ctx, size in
            let totalGap = gap * CGFloat(blocks - 1)
            let w = max(1, (size.width - totalGap) / CGFloat(blocks))
            let filled = Int((progress.clamped(to: 0...1)) * Double(blocks) + 0.0001)
            for i in 0..<blocks {
                let x = CGFloat(i) * (w + gap)
                let rect = CGRect(x: x, y: 0, width: w, height: size.height)
                ctx.fill(Path(rect), with: .color(i < filled ? color : emptyColor))
            }
        }
        .frame(height: blockHeight)
        .opacity(flashing ? 0.82 : 1)
        .animation(
            flashing ? .easeInOut(duration: 0.5).repeatForever(autoreverses: true) : .default,
            value: flashing
        )
    }
}

extension Comparable {
    func clamped(to r: ClosedRange<Self>) -> Self {
        min(max(self, r.lowerBound), r.upperBound)
    }
}

// MARK: - 中文排版
//
// 中文用系统字体（PingFang SC）。像素字库只覆盖 ASCII，
// 所以中文走系统字体 + 可调字距，两种字体混排时靠字距对齐。

struct CJK: View {
    let text: String
    var size: CGFloat = 15
    var weight: Font.Weight = .regular
    var color: Color = PX.star
    var tracking: CGFloat = 0.5
    var lineSpacing: CGFloat = 6
    var align: TextAlignment = .leading

    init(_ text: String,
         size: CGFloat = 15,
         weight: Font.Weight = .regular,
         color: Color = PX.star,
         tracking: CGFloat = 0.5,
         lineSpacing: CGFloat = 6,
         align: TextAlignment = .leading) {
        self.text = text
        self.size = size
        self.weight = weight
        self.color = color
        self.tracking = tracking
        self.lineSpacing = lineSpacing
        self.align = align
    }

    var body: some View {
        Text(text)
            .font(.system(size: size, weight: weight))
            .tracking(tracking)
            .foregroundColor(color)
            .lineSpacing(lineSpacing)
            .multilineTextAlignment(align)
            .fixedSize(horizontal: false, vertical: true)
    }
}

// MARK: - 时间格式

enum Fmt {
    /// 秒 → "MM:SS"，超过 99 分钟也只显示两位数分钟
    static func clock(_ seconds: Int) -> String {
        let s = max(0, seconds)
        return String(format: "%02d:%02d", s / 60, s % 60)
    }

    /// 分钟 → "4H12M" / "42M"
    static func span(_ minutes: Int) -> String {
        if minutes >= 60 {
            return "\(minutes / 60)H\(minutes % 60)M"
        }
        return "\(minutes)M"
    }

    /// 统计页一次刷新会查上千天，formatter 必须复用
    private static let dayFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = .current
        return f
    }()

    static func formatDay(_ d: Date) -> String {
        if dayFormatter.timeZone != TimeZone.current { dayFormatter.timeZone = .current }
        return dayFormatter.string(from: d)
    }

    /// 用当地日历的边界时刻判断归属，避免夏令时当天直接减小时造成错日。
    static func logicalDayStart(_ d: Date = Date(), startHour: Int = 0) -> Date {
        let cal = Calendar.current
        let midnight = cal.startOfDay(for: d)
        let boundary = cal.date(bySettingHour: min(23, max(0, startHour)), minute: 0,
                                second: 0, of: d) ?? midnight
        return d < boundary ? (cal.date(byAdding: .day, value: -1, to: midnight) ?? midnight) : midnight
    }

    static func dayKey(_ d: Date = Date(), startHour: Int = 0) -> String {
        formatDay(logicalDayStart(d, startHour: startHour))
    }
}
