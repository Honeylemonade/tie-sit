import SwiftUI
import AppKit

// MARK: - 飞行场景
//
// 飞船从左向右飞向星球，抵达即该起身。
// 星球由透明像素纹理生成，50 颗互不相同。

// MARK: 星球

struct Planet: Identifiable, Equatable {
    let id: Int
    let name: String

    /// 50 颗，素材在 Resources/Planets/planet_XX.png
    static let all: [Planet] = {
        let names = [
            "塔图因", "科洛桑", "纳布", "霍斯", "恩多", "贝斯平", "雅文四号", "奥德朗",
            "达戈巴", "卡米诺", "吉奥诺西斯", "穆斯塔法", "曼达洛", "科瑞利亚", "蒙卡拉马里",
            "里什", "阿纳克西斯", "亚汶", "索罗苏布", "克罗鲁斯", "波利斯马萨", "鲁蒂亚",
            "芬达", "奇兰", "洛思", "辛达", "卡希克", "塞伦诺", "特拉利斯", "巴库拉",
            "丹图因", "兰多", "阿戈拉", "赫特", "达索米尔", "德尔塔", "马拉凯", "格利恩",
            "伊里德", "索林", "塔利斯", "维伦", "诺瓦", "卡拉丁", "泽尔图", "奥利安",
            "赫利俄斯", "阿卡迪亚", "塞莱斯", "瓦尔基里",
        ]
        return (0..<50).map { Planet(id: $0, name: names[$0]) }
    }()

    var image: NSImage? { Planet.imageCache[id] }

    // 真正的透明像素精灵。旧 PNG 是生成器截图，包含背景和参数栏。
    private static let imageCache: [Int: NSImage] = Dictionary(uniqueKeysWithValues:
        all.map { ($0.id, PlanetTexture.make(seed: $0.id)) })

}

// MARK: 飞船精灵
//
// 32 列 × 24 行。机头朝右，设置、驾驶舱与休息站共用纹理。

enum ShipShape: String, CaseIterable {
    case xwing, interceptor, bomber, scout, gunship
    case shuttle, fighter, speeder, corvette, dart

    var label: String {
        switch self {
        case .xwing: return "X 翼"
        case .interceptor: return "拦截机"
        case .bomber: return "轰炸机"
        case .scout: return "侦察机"
        case .gunship: return "炮艇"
        case .shuttle: return "穿梭机"
        case .fighter: return "战斗机"
        case .speeder: return "高速艇"
        case .corvette: return "护卫舰"
        case .dart: return "飞镖"
        }
    }

    var cells: [String] { ShipSprites.rows[self]! }
}

// 设置中的缩略图和场景共用像素纹理，最近邻缩放保证边缘清晰。
struct ShipPreview: View {
    var ship: ShipShape
    var body: some View {
        Canvas { ctx, size in
            let cell = min(size.width / 32, size.height / 24)
            ShipSprites.draw(ship, in: &ctx, center: CGPoint(x: size.width / 2, y: size.height / 2), cell: cell)
        }
        .accessibilityLabel(ship.label)
    }
}

// MARK: 确定性噪声

private func hash2(_ x: Int, _ y: Int, _ seed: Int) -> Double {
    var h = Int32(truncatingIfNeeded: x &* 374_761_393)
    h = h &+ Int32(truncatingIfNeeded: y &* 668_265_263)
    h = h &+ Int32(truncatingIfNeeded: seed &* 69_069)
    h = (h ^ (h >> 13)) &* 1_274_126_177
    h = h ^ (h >> 16)
    return Double(UInt32(bitPattern: h)) / 4_294_967_295.0
}

// MARK: 场景布局

struct FlightLayout {
    let planetRect: CGRect
    let shipCenter: CGPoint
    let cell: CGFloat

    init(size: CGSize, progress: Double) {
        let p = min(1, max(0, progress))
        let scale = size.width / 360
        let radius = min((36 + p * p * 58) * scale, max(1, size.height / 2 - 24))
        let cx = size.width - 100 * scale
        let cy = size.height / 2
        planetRect = CGRect(x: cx - radius, y: cy - radius,
                            width: radius * 2, height: radius * 2)
        cell = 2 * scale
        // 整艘船和尾焰从起点就可见；沿单调航线向右靠近目的地。
        shipCenter = CGPoint(x: (64 + p * 62) * scale, y: cy)
    }
}

struct FlightMotion {
    let planetOffset: CGSize
    let shipOffset: CGSize
    init(time: Double, reducedMotion: Bool) {
        let scale = reducedMotion ? 0.7 : 1.0
        planetOffset = CGSize(width: sin(time * 2 * .pi / 17) * 1.5 * scale,
                              height: sin(time * 2 * .pi / 9) * 5 * scale)
        shipOffset = CGSize(width: sin(time * 2 * .pi / 11) * 1.5 * scale,
                            height: sin(time * 2 * .pi / 4.8) * 4 * scale)
    }
}

// MARK: 场景视图

struct FlightScene: View {
    var progress: Double
    var planet: Planet
    var ship: ShipShape
    var flying: Bool = true
    var motionEnabled = true
    var renderTime: Double? = nil
    @State private var animationStart = Date()
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Group {
            if motionEnabled && renderTime == nil {
                // 周期刷新独立于系统的隐式动画开关，减少动态效果只降低运动幅度。
                TimelineView(.periodic(from: animationStart, by: 1.0 / 24)) { frame in
                    scene(time: max(0, frame.date.timeIntervalSince(animationStart)))
                }
            } else {
                scene(time: motionEnabled ? (renderTime ?? 0) : 0)
            }
        }
        .overlay(alignment: .bottom) {
            CJK("目的地 · \(planet.name)", size: 11, color: PX.hull)
                .padding(.bottom, 10)
        }
    }

    private func scene(time: Double) -> some View {
        Canvas { ctx, size in
            let p = min(1, max(0, progress))
            let motion = FlightMotion(time: time, reducedMotion: reduceMotion)
            let layout = FlightLayout(size: size, progress: p)
            ctx.fill(Path(CGRect(origin: .zero, size: size)), with: .color(PX.void))
            drawStars(&ctx, size: size, tick: time * 60 * (reduceMotion ? 0.45 : 0.7), progress: p)
            if let img = planet.image {
                let rect = layout.planetRect.offsetBy(dx: motion.planetOffset.width, dy: motion.planetOffset.height)
                ctx.withCGContext { cg in
                    cg.interpolationQuality = .none
                    cg.translateBy(x: rect.minX, y: rect.maxY)
                    cg.scaleBy(x: 1, y: -1)
                    if let bitmap = img.cgImage(forProposedRect: nil, context: nil, hints: nil) {
                        cg.draw(bitmap, in: CGRect(origin: .zero, size: rect.size))
                    }
                }
            }
            drawShip(&ctx, layout: layout, tick: time * 60, motion: motion)
        }
    }

    private func drawStars(_ ctx: inout GraphicsContext,
                           size: CGSize, tick: Double, progress p: Double) {
        guard size.width > 0 else { return }
        let speed = flying ? 0.2 + p * p * 1.2 : 0.06
        let layers: [(Int, Int, Double, CGFloat, Color)] = [
            (34, 4, 0.35, 1, PX.bay),
            (22, 9, 0.85, 1, PX.hull),
            (12, 21, 1.8, 2, PX.star),
        ]
        for (count, seed, mult, dot, color) in layers {
            for i in 0..<count {
                let y = 8 + hash2(i, 2, seed) * max(0, size.height - 16)
                let spd = speed * mult * (0.5 + hash2(i, 3, seed) * 1.5)
                var x = hash2(i, 1, seed) * size.width - tick * spd
                x = x.truncatingRemainder(dividingBy: size.width)
                if x < 0 { x += size.width }
                ctx.fill(Path(CGRect(x: floor(x), y: floor(y), width: dot, height: dot)),
                         with: .color(color))
            }
        }
    }

    private func drawShip(_ ctx: inout GraphicsContext, layout: FlightLayout,
                          tick: Double, motion: FlightMotion) {
        let k = layout.cell
        let center = CGPoint(x: layout.shipCenter.x + (flying ? motion.shipOffset.width : 0),
                             y: layout.shipCenter.y + motion.shipOffset.height)
        if flying {
            let origin = CGPoint(x: center.x - 16 * k, y: center.y - 12 * k)
            for port in ShipSprites.exhaustPorts[ship]! {
                let pulse = sin(tick / 60 * .pi * 4 + port.y) * 1.1 + sin(tick / 60 * .pi * 7) * 0.6
                let length = 9 + Int(pulse.rounded())
                for i in 1...length {
                    let color: Color
                    switch i {
                    case 1...2: color = Color(rgb: 0xFFF1B6)
                    case 3...5: color = Color(rgb: 0xFFD070)
                    case 6...8: color = Color(rgb: 0xF39A4E)
                    default: color = Color(rgb: 0xD76D3B).opacity(0.85)
                    }
                    ctx.fill(Path(CGRect(x: origin.x + (port.x - CGFloat(i)) * k,
                                         y: origin.y + port.y * k, width: k, height: k)), with: .color(color))
                }
            }
        }
        ShipSprites.draw(ship, in: &ctx, center: center, cell: k)
    }
}

// MARK: 像素星球纹理（缓存后每帧只绘制一张图片）

enum PlanetTexture {
    static func make(seed: Int) -> NSImage {
        let side = 64
        let palettes: [[UInt32]] = [
            [0x122840, 0x235673, 0x397c83, 0x55994b, 0x91bd65, 0xdfebc4],
            [0x322542, 0x67445c, 0xa76b58, 0xd49b68, 0xedc88b, 0xffe3b0],
            [0x172d50, 0x32557c, 0x578aaa, 0x88c4d1, 0xc2e4ea, 0xf4faf0],
            [0x291c34, 0x513349, 0x914637, 0xce6735, 0xf6a54b, 0xffdc8d],
            [0x252338, 0x46445c, 0x70647c, 0x9c889b, 0xc6b1b4, 0xeee0d0],
        ]
        let palette = palettes[seed % palettes.count]
        var pixels = [UInt8](repeating: 0, count: side * side * 4)
        for y in 0..<side {
            for x in 0..<side {
                let nx = (Double(x) + 0.5 - 32) / 31
                let ny = (Double(y) + 0.5 - 32) / 31
                let d2 = nx * nx + ny * ny
                guard d2 <= 1 else { continue }
                let z = sqrt(1 - d2)
                let light = max(0, -nx * 0.45 - ny * 0.55 + z * 0.7)
                let terrain = sin(nx * 8 + Double(seed) + sin(ny * 7))
                    + cos(ny * 11 + Double(seed) * 0.7 + sin(nx * 5))
                let bands = sin(ny * 25 + sin(nx * 5) * 1.8 + Double(seed))
                let detail = hash2(x / 2, y / 2, seed + 1)
                let surface = seed % 5 == 1 ? bands : terrain
                let value = light * 0.65 + surface * 0.12 + detail * 0.12
                let index = min(5, max(0, Int(value * 6)))
                let rgb = palette[index]
                let offset = (y * side + x) * 4
                pixels[offset] = UInt8((rgb >> 16) & 255)
                pixels[offset + 1] = UInt8((rgb >> 8) & 255)
                pixels[offset + 2] = UInt8(rgb & 255)
                pixels[offset + 3] = 255
            }
        }
        let data = Data(pixels) as CFData
        let provider = CGDataProvider(data: data)!
        let cg = CGImage(width: side, height: side, bitsPerComponent: 8, bitsPerPixel: 32,
                         bytesPerRow: side * 4, space: CGColorSpaceCreateDeviceRGB(),
                         bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.last.rawValue),
                         provider: provider, decode: nil, shouldInterpolate: false,
                         intent: .defaultIntent)!
        return NSImage(cgImage: cg, size: NSSize(width: side, height: side))
    }
}

// MARK: 目的地池

enum DestinationPool {
    private static let key = "tiesit.destinations"

    static func load(preferences: UserDefaults = .standard) -> Set<Int> {
        guard let raw = preferences.array(forKey: key) as? [Int] else {
            return Set(Planet.all.map(\.id))
        }
        return Set(raw).intersection(Set(Planet.all.map(\.id)))
    }

    static func save(_ ids: Set<Int>) {
        UserDefaults.standard.set(Array(ids).sorted(), forKey: key)
    }

    /// 从池子里抽一个，尽量和上次不同
    static func pick(excluding previous: Planet?, preferences: UserDefaults = .standard) -> Planet {
        let selected = load(preferences: preferences)
        let candidates = Planet.all.filter { selected.contains($0.id) }
        guard !candidates.isEmpty else { return Planet.all[0] }
        if candidates.count == 1 { return candidates[0] }

        return candidates.filter { $0.id != previous?.id }.randomElement()!

    }
}