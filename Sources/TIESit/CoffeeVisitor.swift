import SwiftUI
import AppKit

struct CoffeeLookoutLayout {
    let personFoot: CGPoint
    let personCell: CGFloat
    let shipCenter: CGPoint
    let groundY: CGFloat
    init(harbor: HarborLayout, compact: Bool) {
        let depth: CGFloat = compact ? 15 : 24
        groundY = harbor.dockCenter.y - depth / 2
        personCell = compact ? (harbor.dockWidth >= 180 ? 2 : 1) : (harbor.dockWidth >= 320 ? 3 : 2)
        personFoot = CGPoint(x: (harbor.dockCenter.x + harbor.dockWidth * (compact ? 0.36 : 0.20)).rounded(),
                             y: groundY.rounded())
        shipCenter = CGPoint(x: (harbor.dockCenter.x - harbor.dockWidth * 0.23).rounded(),
                             y: (groundY - harbor.shipWidth * 0.375 - 4).rounded())
    }
}

enum CoffeeVisitor {
    // 原创 24×32 侧视宇航员，面罩朝向星球，背包在右侧。
    static let rows = [
        "........................",
        "..........oooooooo......",
        "........oowwwwwwwooo....",
        ".......owwwccccccsso....",
        "......owwvvvvvvwccsso...",
        ".....owvggggggvvccsso...",
        ".....ovghhggggdvccsso...",
        ".....ovghggggddvccsso...",
        ".....ovgggggdddvcssso...",
        ".....ovggggddddvcssso...",
        "......ovdddddvvccssso...",
        "......osvvvvvcccssso....",
        ".......oosssssssssoo....",
        ".........oorrrrroo......",
        "........owcccccsoo......",
        "........owcccccssobboo..",
        "........occcscsssobbbso.",
        "........occcscsssobbrso.",
        "........occcccsssobbbso.",
        "........occcccsssobbbso.",
        "........osccccsssobbbso.",
        "........osccccsssoooo...",
        "........osssssssso......",
        "........orrrrrrsso......",
        "........occcsscssso.....",
        "........occcsscssso.....",
        "........occcoscssso.....",
        "........occso.ossso.....",
        "........orsso.osrso.....",
        "........obboo.obboo.....",
        ".......owbbbo.owbbbo....",
        ".......oooooo.oooooo....",
    ]

    static let image: CGImage = {
        let palette: [Character: UInt32] = [
            "o": 0x243743, "w": 0xFFF1D8, "c": 0xDDDCC9, "s": 0xA1B4B5,
            "v": 0x6C6B62, "g": 0xBE915D, "d": 0x80604D, "h": 0xF4D5A0,
            "r": 0xBF795E, "b": 0x586F7B,
        ]
        var rgba = [UInt8]()
        for row in rows {
            for character in row {
                if let rgb = palette[character] {
                    rgba += [UInt8((rgb >> 16) & 255), UInt8((rgb >> 8) & 255), UInt8(rgb & 255), 255]
                } else { rgba += [0, 0, 0, 0] }
            }
        }
        return CGImage(width: 24, height: 32, bitsPerComponent: 8, bitsPerPixel: 32,
                       bytesPerRow: 24 * 4, space: CGColorSpaceCreateDeviceRGB(),
                       bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.last.rawValue),
                       provider: CGDataProvider(data: Data(rgba) as CFData)!, decode: nil,
                       shouldInterpolate: false, intent: .defaultIntent)!
    }()

    // 一次完整的「端杯—举杯—放下」循环，角色本身始终站稳。
    static func cupLift(at time: Double) -> CGFloat {
        let phase = max(0, time).truncatingRemainder(dividingBy: 14)
        if phase < 5 { return 0 }
        if phase < 7 { return CGFloat((phase - 5) / 2) }
        if phase < 10 { return 1 }
        if phase < 12 { return CGFloat(1 - (phase - 10) / 2) }
        return 0
    }

    static func draw(in context: inout GraphicsContext, foot: CGPoint, cell k: CGFloat, time: Double) {
        let origin = CGPoint(x: (foot.x - 12 * k).rounded(), y: (foot.y - 32 * k).rounded())
        context.withCGContext { cg in
            cg.interpolationQuality = .none
            cg.translateBy(x: origin.x, y: foot.y)
            cg.scaleBy(x: 1, y: -1)
            cg.draw(image, in: CGRect(x: 0, y: 0, width: 24 * k, height: 32 * k))
        }
        let lift = cupLift(at: time)
        let elbow = CGPoint(x: 7, y: (19 - 3 * lift).rounded())
        let wrist = CGPoint(x: (5 + lift).rounded(), y: (19 - 5 * lift).rounded())
        func block(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat, _ color: Color) {
            context.fill(Path(CGRect(x: origin.x + x * k, y: origin.y + y * k,
                                     width: w * k, height: h * k)), with: .color(color))
        }
        // 用阶梯色块构成手臂，举杯时脚步保持不动。
        for step in 0...4 {
            let t = CGFloat(step) / 4
            block((9 + (elbow.x - 9) * t).rounded(), (15 + (elbow.y - 15) * t).rounded(), 3, 3, Color(rgb: 0xA1B4B5))
            block((elbow.x + (wrist.x - elbow.x) * t).rounded(), (elbow.y + (wrist.y - elbow.y) * t).rounded(), 3, 2, Color(rgb: 0xDDDCC9))
        }
        block(wrist.x, wrist.y, 2, 2, Color(rgb: 0x586F7B))
        let cup = CGPoint(x: wrist.x - 3, y: wrist.y - 2)
        block(cup.x, cup.y, 4, 4, Color(rgb: 0xECD6A6))
        block(cup.x, cup.y, 4, 1, Color(rgb: 0x8B6049))
        block(cup.x + 4, cup.y + 1, 1, 2, Color(rgb: 0xECD6A6))
        for i in 0..<3 {
            let rise = (time * 0.22 + Double(i) / 3).truncatingRemainder(dividingBy: 1)
            let drift = CGFloat(sin(time * 0.8 + Double(i)) * 1.2).rounded()
            block(cup.x + 1 + drift, cup.y - 1 - CGFloat(Int(rise * 8)), 1, 2,
                  RestTheme.text.opacity((1 - rise) * 0.45))
        }
    }
}
