import SwiftUI

// MARK: - 设置
//
// 飞行外观、计时与系统偏好，修改后立即生效。

struct SettingsView: View {

    @ObservedObject var engine: SitEngine
    /// 返回驾驶舱（由 AppDelegate 注入）
    var onClose: () -> Void = {}

    @State private var shipsExpanded = false
    @State private var planetsExpanded = false

    private var s: SitSettings { engine.settings }

    var body: some View {
        ZStack {
            PX.void.ignoresSafeArea()

            VStack(spacing: 0) {
                header
                Rectangle().fill(PX.bay).frame(height: 2)

                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        group("飞行外观") {
                            appearancePicker
                        }
                        group("计时") {
                            segmented("触发阈值",
                                      subtitle: "连续在座多久触发警报",
                                      options: [25, 45, 60, 90],
                                      unit: "MIN",
                                      selected: s.thresholdMin) { v in
                                var n = s; n.thresholdMin = v; engine.apply(n)
                            }
                            segmented("休息时长",
                                      subtitle: "解除后强制站立的时间",
                                      options: [0, 2, 5, 10],
                                      unit: "MIN",
                                      selected: s.restMin) { v in
                                var n = s; n.restMin = v; engine.apply(n)
                            }
                            segmented("长按要求",
                                      subtitle: "需要按住多久才能解除",
                                      options: [3, 5, 8],
                                      unit: "SEC",
                                      selected: s.holdSec) { v in
                                var n = s; n.holdSec = v; engine.apply(n)
                            }
                        }

                        group("系统") {
                            toggleRow("开机自动启动",
                                      subtitle: "登录时在后台运行，不打开窗口",
                                      on: s.launchAtLogin) { v in
                                var n = s; n.launchAtLogin = v; engine.apply(n)
                                LaunchAtLogin.set(v)
                            }
                            toggleRow("8-bit 音效",
                                      subtitle: "按钮音、休息结束提示音（全屏提醒保持安静）",
                                      on: s.soundOn) { v in
                                var n = s; n.soundOn = v
                                Chiptune.shared.enabled = v
                                engine.apply(n)
                            }
                            toggleRow("场景动效",
                                      subtitle: "星球浮动、飞船喷火、停泊港动画",
                                      on: s.sceneMotionOn) { v in
                                var n = s; n.sceneMotionOn = v; engine.apply(n)
                            }
                            toggleRow("CRT 扫描线",
                                      subtitle: "老式显示器的横向条纹",
                                      on: s.scanlinesOn) { v in
                                var n = s; n.scanlinesOn = v; engine.apply(n)
                            }
                            toggleRow("强制下班",
                                      subtitle: "当天累计在座超 \(Fmt.span(curfewLimitMin)) 时弹出下班令",
                                      on: s.forceEndOfDay) { v in
                                var n = s; n.forceEndOfDay = v; engine.apply(n)
                            }
                        }

                        group("口径") {
                            segmented("一天从几点算",
                                      subtitle: "熬夜的人建议改成凌晨 4 点",
                                      options: [0, 2, 4],
                                      unit: "时",
                                      selected: s.dayStartHour) { v in
                                var n = s; n.dayStartHour = v; engine.apply(n)
                            }
                        }

                        // 权限说明
                        VStack(alignment: .leading, spacing: 8) {
                            CJK("关于「不可关闭」", size: 13, weight: .semibold,
                                color: PX.chalk, tracking: 0.8)
                            CJK("警报窗口没有关闭按钮，Cmd+Q、ESC、空格全部被拦截。强制退出（Cmd+Option+Esc）仍然可行——这是 macOS 留给用户的最终保险，任何 App 都绕不过，也不应该试图绕。",
                                size: 12, color: PX.hull, tracking: 0.5, lineSpacing: 6)
                        }
                        .padding(12)
                        .pixelFrame(PX.bay)
                    }
                    .padding(14)
                }

                Rectangle().fill(PX.bay).frame(height: 2)
                footer
            }
        }
        .frame(width: CockpitView.panelSize.width, height: CockpitView.panelSize.height)
        .overlay(Group { if s.scanlinesOn { Scanlines(opacity: 0.3) } })
    }

    private var header: some View {
        HStack(spacing: 12) {
            PixelText("SETUP", scale: 2.2, color: PX.chalk)
            CJK("设置", size: 14, color: PX.hull, tracking: 2)
            Spacer()
            Button {
                Chiptune.shared.click()
                onClose()
            } label: {
                PixelText("DONE", scale: 1.3, color: PX.order)
                    .padding(.horizontal, 10).padding(.vertical, 6)
                    .pixelFrame(PX.order.opacity(0.5))
            }
            .buttonStyle(.plain)
            .keyboardShortcut(.escape, modifiers: [])
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
    }

    private var footer: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let issue = engine.storageIssue {
                HStack(alignment: .top, spacing: 10) {
                    Text(issue).font(.system(size: 11)).foregroundColor(PX.order)
                        .fixedSize(horizontal: false, vertical: true)
                    Button("重试") { engine.persist() }
                        .buttonStyle(.plain).font(.system(size: 11)).foregroundColor(PX.sys)
                }
            }
            HStack {
                PixelText("TIE-SIT v0.1", scale: 1.1, color: PX.bay)
                Spacer()
                PixelText("LOCAL ONLY", scale: 1.1, color: PX.bay)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
    }

    // MARK: 飞行外观

    private var appearancePicker: some View {
        VStack(spacing: 0) {
            Button { shipsExpanded.toggle() } label: {
                HStack(spacing: 14) {
                    ShipPreview(ship: engine.shipShape).frame(width: 56, height: 36)
                    VStack(alignment: .leading, spacing: 4) {
                        Text("飞船造型").font(.system(size: 13)).foregroundColor(PX.chalk)
                        Text(engine.shipShape.label).font(.system(size: 11)).foregroundColor(PX.hull)
                    }
                    Spacer()
                    Image(systemName: shipsExpanded ? "chevron.up" : "chevron.down").foregroundColor(PX.hull)
                }
                .padding(12).contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("飞船造型，当前为\(engine.shipShape.label)")
            .accessibilityValue(shipsExpanded ? "已展开" : "已收起")

            if shipsExpanded {
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 3), spacing: 8) {
                    ForEach(ShipShape.allCases, id: \.self) { shape in
                        Button { engine.selectShip(shape) } label: {
                            VStack(spacing: 8) {
                                ShipPreview(ship: shape).frame(height: 48)
                                Text(shape.label).font(.system(size: 10))
                            }
                            .frame(maxWidth: .infinity).padding(.vertical, 10)
                            .foregroundColor(engine.shipShape == shape ? PX.order : PX.hull)
                            .background(engine.shipShape == shape ? PX.order.opacity(0.12) : .clear)
                            .pixelFrame(engine.shipShape == shape ? PX.order : PX.bay)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(shape.label)
                        .accessibilityAddTraits(engine.shipShape == shape ? .isSelected : [])
                    }
                }
                .padding([.horizontal, .bottom], 12)
            }

            Rectangle().fill(PX.bay.opacity(0.7)).frame(height: 1)
            Button { planetsExpanded.toggle() } label: {
                HStack(spacing: 14) {
                    planetThumbnail(engine.destination).frame(width: 56, height: 40)
                    VStack(alignment: .leading, spacing: 4) {
                        Text("目的地星球").font(.system(size: 13)).foregroundColor(PX.chalk)
                        Text(engine.fixedDestinationID == nil ? "每程随机探索" : engine.destination.name)
                            .font(.system(size: 11)).foregroundColor(PX.hull)
                    }
                    Spacer()
                    Image(systemName: planetsExpanded ? "chevron.up" : "chevron.down").foregroundColor(PX.hull)
                }
                .padding(12).contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("目的地星球，\(engine.fixedDestinationID == nil ? "每程随机探索" : engine.destination.name)")
            .accessibilityValue(planetsExpanded ? "已展开" : "已收起")

            if planetsExpanded {
                VStack(alignment: .leading, spacing: 12) {
                    Button { engine.selectRandomPlanet() } label: {
                        HStack {
                            Text("每程随机探索")
                            Spacer()
                            if engine.fixedDestinationID == nil { Image(systemName: "checkmark") }
                        }
                        .font(.system(size: 12))
                        .foregroundColor(engine.fixedDestinationID == nil ? PX.order : PX.hull)
                        .padding(12)
                        .pixelFrame(engine.fixedDestinationID == nil ? PX.order : PX.bay)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    Text("或选择一颗固定星球；立即生效，不影响当前计时。")
                        .font(.system(size: 11)).foregroundColor(PX.hull)
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 3), spacing: 8) {
                        ForEach(Planet.all) { planet in
                            Button { engine.selectPlanet(planet) } label: {
                                VStack(spacing: 6) {
                                    planetThumbnail(planet).frame(height: 40)
                                    Text(planet.name).font(.system(size: 10)).lineLimit(1).minimumScaleFactor(0.7)
                                }
                                .frame(maxWidth: .infinity).padding(.vertical, 10)
                                .foregroundColor(engine.fixedDestinationID == planet.id ? PX.order : PX.hull)
                                .background(engine.fixedDestinationID == planet.id ? PX.order.opacity(0.12) : .clear)
                                .pixelFrame(engine.fixedDestinationID == planet.id ? PX.order : PX.bay)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel(planet.name)
                            .accessibilityAddTraits(engine.fixedDestinationID == planet.id ? .isSelected : [])
                        }
                    }
                }
                .padding([.horizontal, .bottom], 12)
            }
        }
    }

    private func planetThumbnail(_ planet: Planet) -> some View {
        Group {
            if let image = planet.image {
                Image(nsImage: image).resizable().interpolation(.none).scaledToFit()
            }
        }
        .accessibilityHidden(true)
    }

    // MARK: 组件

    private func group<C: View>(_ title: String, @ViewBuilder content: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                Rectangle().fill(PX.order).frame(width: 4, height: 14)
                CJK(title, size: 14, weight: .semibold, color: PX.chalk, tracking: 1.2)
            }
            .padding(.bottom, 12)

            VStack(spacing: 0) { content() }
                .pixelFrame(PX.bay)
        }
    }

    private func segmented(_ label: String,
                           subtitle: String,
                           options: [Int],
                           unit: String,
                           selected: Int,
                           onPick: @escaping (Int) -> Void) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 3) {
                    CJK(label, size: 13, color: PX.chalk, tracking: 0.8)
                    CJK(subtitle, size: 11, color: PX.bay, tracking: 0.4)
                }
                Spacer()
            }

            HStack(spacing: 0) {
                ForEach(options, id: \.self) { v in
                    Button {
                        Chiptune.shared.click()
                        onPick(v)
                    } label: {
                        VStack(spacing: 3) {
                            PixelText(v == 0 && unit == "MIN" ? "OFF" : "\(v)",
                                      scale: 1.7,
                                      color: selected == v ? PX.void : PX.hull)
                            // 单位可能是中文（时），像素字库只有 ASCII，要走 CJK
                            if unit == "时" {
                                CJK(unit, size: 10,
                                    color: selected == v ? PX.void.opacity(0.7) : PX.bay,
                                    tracking: 0)
                            } else {
                                PixelText(unit, scale: 0.9,
                                          color: selected == v ? PX.void.opacity(0.6) : PX.bay)
                            }
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 9)
                        .background(selected == v ? PX.order : Color.clear)
                        .overlay(alignment: .trailing) {
                            Rectangle().fill(PX.bay).frame(width: 1)
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
            .pixelFrame(PX.bay)
        }
        .padding(12)
        .overlay(alignment: .bottom) {
            Rectangle().fill(PX.bay.opacity(0.7)).frame(height: 1)
        }
    }

    private func toggleRow(_ label: String,
                           subtitle: String,
                           on: Bool,
                           onChange: @escaping (Bool) -> Void) -> some View {
        Button {
            Chiptune.shared.click()
            onChange(!on)
        } label: {
            HStack(spacing: 14) {
                VStack(alignment: .leading, spacing: 3) {
                    CJK(label, size: 13, color: PX.chalk, tracking: 0.8)
                    CJK(subtitle, size: 11, color: PX.bay, tracking: 0.4)
                }
                Spacer()
                // 像素开关
                ZStack(alignment: on ? .trailing : .leading) {
                    Rectangle()
                        .fill(on ? PX.ok.opacity(0.18) : PX.bay.opacity(0.25))
                        .frame(width: 46, height: 22)
                        .pixelFrame(on ? PX.ok : PX.bay, width: 2)
                    Rectangle()
                        .fill(on ? PX.ok : PX.bay)
                        .frame(width: 18, height: 16)
                        .padding(.horizontal, 2)
                }
                .frame(width: 46)
            }
            .padding(12)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .overlay(alignment: .bottom) {
            Rectangle().fill(PX.bay.opacity(0.7)).frame(height: 1)
        }
    }
}
