import SwiftUI

struct CurfewView: View {
    @ObservedObject var engine: SitEngine
    var onEndShift: () -> Void = {}
    var sceneTime: Double? = nil
    @State private var confirming = false
    @State private var completed = false

    var body: some View {
        GeometryReader { geo in
            let layout = RestPageLayout(size: geo.size)
            ZStack {
                RestHarborScene(planet: engine.destination, ship: engine.shipShape, motionEnabled: engine.settings.sceneMotionOn, renderTime: sceneTime)
                VStack(alignment: layout.wide ? .leading : .center, spacing: layout.compact ? 18 : 24) {
                    PixelCJK("\(engine.destination.name)的夜色，留给自己", grid: 12, color: RestTheme.mint)
                    PixelCJK(layout.wide ? "今天，\n就到这里吧。" : "今天就到这里吧。", scale: layout.wide ? (layout.compact ? 2 : 3) : 2,
                             color: RestTheme.text, spacing: 12, alignment: layout.wide ? .leading : .center)
                    PixelCJK("已经努力了很久。\n合上电脑，去享受自己的时间。", color: RestTheme.secondary,
                             spacing: 9, alignment: layout.wide ? .leading : .center)
                    HStack(spacing: 20) {
                        PixelCJK("今天的旅程 \(Fmt.span(engine.daySitMinutes))", grid: 12, color: RestTheme.quiet)
                        PixelCJK("\(engine.today.stands) 次起身", grid: 12, color: RestTheme.quiet)
                    }
                    VStack(alignment: layout.wide ? .leading : .center, spacing: 14) {
                        Button {
                            guard !completed else { return }
                            if confirming {
                                completed = true
                                engine.endShift()
                                onEndShift()
                            } else { confirming = true }
                        } label: {
                            VStack(spacing: 8) {
                                PixelCJK(confirming ? "确认下班，好好生活" : "结束今天的旅程", color: RestTheme.text)
                                PixelCJK(confirming ? "再点一次，确认结束" : "今天不再计时，明天自动恢复", grid: 12, color: RestTheme.secondary)
                            }
                            .frame(width: layout.contentWidth, height: 84)
                            .background(Rectangle().fill(RestTheme.mint.opacity(confirming ? 0.14 : 0.07)))
                            .overlay(Rectangle().strokeBorder(RestTheme.mint.opacity(0.5), lineWidth: 2))
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("end-shift")
                        PixelCJK("今天的计时停在这里，明天再出发。", grid: 12, color: RestTheme.secondary)
                    }
                    .padding(.top, layout.compact ? 2 : 8)
                }
                .frame(width: layout.contentWidth, alignment: layout.wide ? .leading : .center)
                .position(layout.contentCenter)

                VStack {
                    HStack(spacing: 20) {
                        RestHeader(subtitle: "今天辛苦了")
                        if engine.isPreview {
                            Button { engine.cancelPreview(); onEndShift() } label: {
                                PixelCJK("退出预览", grid: 12, color: RestTheme.secondary)
                            }.buttonStyle(.plain)
                        }
                    }
                    Spacer()
                    HStack {
                        PixelCJK("明天的星空，也会在这里。", grid: 12, color: RestTheme.quiet)
                        Spacer()
                    }
                    .font(.system(size: 11)).foregroundColor(RestTheme.quiet)
                }
                .padding(layout.compact ? 24 : 36)
            }
        }
    }
}
