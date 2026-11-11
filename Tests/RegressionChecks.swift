import SwiftUI

@MainActor
final class RegressionTests {
    var temporaryDirectories: [URL] = []
    func cleanup() { for dir in temporaryDirectories { try? FileManager.default.removeItem(at: dir) } }
    @MainActor
    func testFlightStaysVisibleAndMovesTowardPlanet() {
        for height in [240.0, 300, 340] {
            for ship in ShipShape.allCases {
                var previousX = 0.0
                for i in 0...100 {
                    let layout = FlightLayout(size: CGSize(width: 360, height: height), progress: Double(i) / 100)
                    let halfWidth = CGFloat(ship.cells.map(\.count).max()!) * layout.cell / 2
                    XCTAssertGreaterThanOrEqual(layout.shipCenter.x - halfWidth - 4 * layout.cell, 0)
                    XCTAssertLessThan(layout.shipCenter.x + halfWidth, layout.planetRect.minX)
                    XCTAssertGreaterThanOrEqual(layout.shipCenter.x, previousX)
                    XCTAssertGreaterThanOrEqual(layout.planetRect.minY, 0)
                    XCTAssertLessThanOrEqual(layout.planetRect.maxX, 360)
                    XCTAssertLessThanOrEqual(layout.planetRect.maxY, height)
                    previousX = layout.shipCenter.x
                }
            }
        }
    }

    @MainActor
    func testShipSpritesAndExhaustPorts() {
        var sprites = Set<Data>()
        let alphabet = Set(".xsmhbcre")
        for shape in ShipShape.allCases {
            let rows = shape.cells
            XCTAssertEqual(rows.count, 24)
            XCTAssertTrue(rows.allSatisfy { $0.count == 32 && Set($0).isSubset(of: alphabet) })
            let image = ShipSprites.images[shape]!
            XCTAssertEqual(image.width, 32)
            XCTAssertEqual(image.height, 24)
            let ports = ShipSprites.exhaustPorts[shape]!
            XCTAssertTrue(!ports.isEmpty)
            for port in ports {
                XCTAssertEqual(Array(rows[Int(port.y)])[Int(port.x)], "e")
                XCTAssertLessThan(port.x, 16)
            }
            let bytes = image.dataProvider!.data! as Data
            XCTAssertEqual(bytes[3], 0)
            sprites.insert(bytes)
        }
        XCTAssertEqual(sprites.count, 10)
    }

    @MainActor
    func testSceneMotionSurvivesReducedMotionAndStaysInBounds() throws {
        let a = FlightMotion(time: 0, reducedMotion: true)
        let b = FlightMotion(time: 2, reducedMotion: true)
        XCTAssertTrue(a.planetOffset != b.planetOffset)
        XCTAssertTrue(a.shipOffset != b.shipOffset)
        for height in [240.0, 300, 340] {
            for progress in [0.0, 0.5, 1.0] {
                let layout = FlightLayout(size: CGSize(width: 360, height: height), progress: progress)
                for time in stride(from: 0.0, to: 18, by: 0.5) {
                    let motion = FlightMotion(time: time, reducedMotion: false)
                    let planet = layout.planetRect.offsetBy(dx: motion.planetOffset.width, dy: motion.planetOffset.height)
                    XCTAssertGreaterThanOrEqual(planet.minY, 0)
                    XCTAssertLessThanOrEqual(planet.maxY, height)
                    XCTAssertLessThan(layout.shipCenter.x + motion.shipOffset.width + 32, planet.minX)
                    XCTAssertGreaterThanOrEqual(layout.shipCenter.x + motion.shipOffset.width - 32 - 24, 0)
                }
            }
        }
        let settings = try JSONDecoder().decode(SitSettings.self, from: Data("{}".utf8))
        XCTAssertTrue(settings.sceneMotionOn)
        var disabled = settings
        disabled.sceneMotionOn = false
        XCTAssertTrue(!(try JSONDecoder().decode(SitSettings.self, from: JSONEncoder().encode(disabled))).sceneMotionOn)
    }

    @MainActor
    func testHarborLayoutAndMotion() {
        for size in [CGSize(width:1440,height:900),CGSize(width:1024,height:640),CGSize(width:720,height:1100)] {
            let page = RestPageLayout(size:size)
            XCTAssertGreaterThanOrEqual(page.contentCenter.x - page.contentWidth / 2, 20)
            XCTAssertLessThanOrEqual(page.contentCenter.x + page.contentWidth / 2, size.width - 20)
            let harbor = HarborLayout(size:size,compact:false)
            XCTAssertGreaterThanOrEqual(harbor.planetCenter.y - harbor.planetRadius - 4,0)
            XCTAssertLessThanOrEqual(harbor.planetCenter.x + harbor.planetRadius,size.width)
        }
        // 停泊时角色与飞船分处平台两侧，脚和支架落到同一台面。
        for (size, compact) in [(CGSize(width: 1440, height: 900), false),
                                (CGSize(width: 1024, height: 640), false),
                                (CGSize(width: 720, height: 1100), false),
                                (CGSize(width: 360, height: 300), true)] {
            let harbor = HarborLayout(size: size, compact: compact)
            let lookout = CoffeeLookoutLayout(harbor: harbor, compact: compact)
            XCTAssertLessThan(lookout.shipCenter.x + harbor.shipWidth / 2,
                              lookout.personFoot.x - 12 * lookout.personCell)
            XCTAssertGreaterThanOrEqual(lookout.personFoot.x - 12 * lookout.personCell, harbor.dockCenter.x - harbor.dockWidth / 2)
            XCTAssertLessThanOrEqual(lookout.personFoot.x + 12 * lookout.personCell, harbor.dockCenter.x + harbor.dockWidth / 2)
            XCTAssertLessThanOrEqual(abs(lookout.personFoot.y - lookout.groundY), 0.5)
            XCTAssertGreaterThanOrEqual(lookout.personFoot.y - 32 * lookout.personCell, 0)
        }
        XCTAssertEqual(CoffeeVisitor.cupLift(at: 0), 0)
        XCTAssertEqual(CoffeeVisitor.cupLift(at: 6), 0.5)
        XCTAssertEqual(CoffeeVisitor.cupLift(at: 8), 1)
        XCTAssertEqual(CoffeeVisitor.cupLift(at: 11), 0.5)
        XCTAssertEqual(CoffeeVisitor.cupLift(at: 14), 0)
        XCTAssertEqual(CoffeeVisitor.rows.count, 32)
        XCTAssertTrue(CoffeeVisitor.rows.allSatisfy { $0.count == 24 })
        let a = HarborMotion(time:0,reducedMotion:true)
        let b = HarborMotion(time:3,reducedMotion:true)
        XCTAssertTrue(a.planetY != b.planetY && a.shipY != b.shipY)
        XCTAssertTrue(a.orbitAngle != b.orbitAngle)
    }

    @MainActor
    func testAllPlanetsAreDistinctTransparentSprites() {
        var textures = Set<Data>()
        for planet in Planet.all {
            let cg = planet.image!.cgImage(forProposedRect: nil, context: nil, hints: nil)!
            let data = cg.dataProvider!.data! as Data
            XCTAssertEqual(data[3], 0, "Corners must be transparent")
            XCTAssertEqual(data[(32 * 64 + 32) * 4 + 3], 255)
            textures.insert(data)
        }
        XCTAssertEqual(textures.count, 50)
    }

    @MainActor
    private func fixture(now: Date = Date(), store: Store = Store()) throws -> (SitEngine, URL) {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        temporaryDirectories.append(dir)
        let url = dir.appendingPathComponent("data.json")
        try JSONEncoder().encode(store).write(to: url)
        return (SitEngine(dataURL: url, now: now, startAutomatically: false), url)
    }

    @MainActor
    func testThresholdUnlockAndRestCycle() throws {
        let now = Calendar.current.startOfDay(for: Date()).addingTimeInterval(43200)
        var store = Store()
        store.settings.thresholdMin = 25
        let (engine, _) = try fixture(now: now, store: store)
        var alerts = 0
        var restEnds = 0
        engine.onAlert = { alerts += 1 }
        engine.onRestEnd = { restEnds += 1 }
        for second in 1...1500 { engine.tick(now: now.addingTimeInterval(Double(second)), idleSeconds: 0) }
        XCTAssertEqual(engine.state, .alert)
        XCTAssertEqual(alerts, 1)
        XCTAssertEqual(engine.alertSnapshot.totalToday, 25)
        let end = now.addingTimeInterval(1500)
        engine.unlock(now: end)
        engine.unlock(now: end) // Repeat callback cannot record twice.
        XCTAssertEqual(engine.today.stands, 1)
        XCTAssertEqual(engine.today.total, 25)
        XCTAssertEqual(engine.state, .resting)
        engine.tick(now: end.addingTimeInterval(301), idleSeconds: 999)
        XCTAssertEqual(engine.state, .sitting)
        XCTAssertEqual(engine.elapsed, 0)
        XCTAssertEqual(restEnds, 1)
    }

    @MainActor
    func testIdleAndSleepDoNotAccumulateSitting() throws {
        let now = Calendar.current.startOfDay(for: Date()).addingTimeInterval(43200)
        let (engine, _) = try fixture(now: now)
        engine.tick(now: now.addingTimeInterval(1), idleSeconds: 301)
        XCTAssertEqual(engine.elapsed, 0)
        engine.tick(now: now.addingTimeInterval(3600), idleSeconds: 0)
        XCTAssertEqual(engine.elapsed, 0)
        engine.tick(now: now.addingTimeInterval(3601), idleSeconds: 0)
        XCTAssertEqual(engine.elapsed, 1)
    }

    @MainActor
    func testCheckpointPreservesRunAndDoesNotCountDowntime() throws {
        let now = Calendar.current.startOfDay(for: Date()).addingTimeInterval(43200)
        let (engine, url) = try fixture(now: now)
        for second in 1...90 { engine.tick(now: now.addingTimeInterval(Double(second)), idleSeconds: 0) }
        let restored = SitEngine(dataURL: url, now: now.addingTimeInterval(600), startAutomatically: false)
        XCTAssertEqual(restored.elapsed, 90)
        restored.tick(now: now.addingTimeInterval(601), idleSeconds: 0)
        XCTAssertEqual(restored.elapsed, 91)
    }

    @MainActor
    func testCurfewPersistsOffDutyAcrossRestart() throws {
        let now = Calendar.current.startOfDay(for: Date()).addingTimeInterval(43200)
        var store = Store()
        store.settings.forceEndOfDay = true
        store.days[Fmt.dayKey(now)] = DayRecord(total: 599)
        let (engine, url) = try fixture(now: now, store: store)
        engine.tick(now: now.addingTimeInterval(60), idleSeconds: 0)
        XCTAssertEqual(engine.state, .endOfDay)
        engine.endShift(now: now.addingTimeInterval(60))
        XCTAssertEqual(engine.today.total, 600)
        let restored = SitEngine(dataURL: url, now: now.addingTimeInterval(120), startAutomatically: false)
        XCTAssertEqual(restored.state, .offDuty)
        restored.tick(now: now.addingTimeInterval(121), idleSeconds: 0)
        XCTAssertEqual(restored.elapsed, 0)
    }

    @MainActor
    func testRolloverRecordsPendingRunAndClosesStaleAlert() throws {
        let cal = Calendar.current
        let now = cal.startOfDay(for: Date()).addingTimeInterval(86390)
        var store = Store()
        store.checkpoint = RunCheckpoint(dayKey: Fmt.dayKey(now), savedAt: now,
                                        state: .alert, elapsed: 1500, restRemaining: 0)
        let (engine, _) = try fixture(now: now, store: store)
        var closed = false
        engine.onCurfewExpired = { closed = true }
        engine.tick(now: now.addingTimeInterval(11), idleSeconds: 999)
        XCTAssertTrue(closed)
        XCTAssertEqual(engine.state, .sitting)
        XCTAssertEqual(engine.today.total, 0)
        let result = try JSONDecoder().decode(Store.self, from: engine.exportJSON()!)
        XCTAssertEqual(result.days[Fmt.dayKey(now)]?.total, 25)
        XCTAssertEqual(result.days[Fmt.dayKey(now)]?.stands, 0)
    }

    @MainActor
    func testRestSurvivesRestartAndDayBoundary() throws {
        let now = Calendar.current.startOfDay(for: Date()).addingTimeInterval(86390)
        var store = Store()
        store.checkpoint = RunCheckpoint(dayKey: Fmt.dayKey(now), savedAt: now,
                                        state: .resting, elapsed: 0, restRemaining: 300)
        let (engine, _) = try fixture(now: now.addingTimeInterval(60), store: store)
        XCTAssertEqual(engine.state, .resting)
        XCTAssertEqual(engine.restRemaining, 240)
        engine.handleWake(now: now.addingTimeInterval(301))
        XCTAssertEqual(engine.state, .sitting)
    }

    @MainActor
    func testAppearanceChangesPersistWithoutResettingTimer() throws {
        let now = Calendar.current.startOfDay(for: Date()).addingTimeInterval(43200)
        let suite = "TIESitTests.Appearance.\(UUID().uuidString)"
        let preferences = UserDefaults(suiteName: suite)!
        defer { preferences.removePersistentDomain(forName: suite) }
        var store = Store()
        store.settings.restMin = 0
        store.checkpoint = RunCheckpoint(dayKey: Fmt.dayKey(now), savedAt: now,
                                        state: .alert, elapsed: 1500, restRemaining: 0)
        let (_, url) = try fixture(now: now, store: store)
        let engine = SitEngine(dataURL: url, now: now, startAutomatically: false, preferences: preferences)
        engine.selectShip(.bomber)
        engine.selectPlanet(Planet.all[0])
        XCTAssertEqual(engine.shipShape, .bomber)
        XCTAssertEqual(engine.destination.id, 0)
        XCTAssertEqual(engine.elapsed, 1500)
        XCTAssertEqual(engine.state, .alert)
        let restored = SitEngine(dataURL: url, now: now, startAutomatically: false, preferences: preferences)
        XCTAssertEqual(restored.shipShape, .bomber)
        XCTAssertEqual(restored.fixedDestinationID, 0)
        XCTAssertEqual(restored.destination.id, 0)
        restored.unlock(now: now)
        XCTAssertEqual(restored.state, .sitting)
        XCTAssertEqual(restored.destination.id, 0, "Fixed planet must remain for next run")
        restored.selectRandomPlanet()
        XCTAssertEqual(restored.fixedDestinationID, nil)
        let randomized = SitEngine(dataURL: url, now: now, startAutomatically: false, preferences: preferences)
        XCTAssertEqual(randomized.fixedDestinationID, nil)
        XCTAssertEqual(randomized.shipShape, .bomber)
    }

    @MainActor
    func testPreviewDoesNotChangeRealProgressOrStatistics() throws {
        let now = Date()
        var store = Store()
        store.checkpoint = RunCheckpoint(dayKey: Fmt.dayKey(now), savedAt: now,
                                        state: .sitting, elapsed: 30, restRemaining: 0)
        let (engine, _) = try fixture(now: now, store: store)
        engine.debugTriggerAlert()
        engine.persist(now: now)
        let saved = try JSONDecoder().decode(Store.self, from: engine.exportJSON()!)
        XCTAssertEqual(saved.checkpoint?.state, .sitting, "Preview must never persist as a real alert")
        XCTAssertEqual(saved.checkpoint?.elapsed, 30)
        engine.unlock(now: now)
        XCTAssertEqual(engine.state, .sitting)
        XCTAssertEqual(engine.elapsed, 30)
        XCTAssertEqual(engine.today.total, 0)
        XCTAssertEqual(engine.today.stands, 0)
        engine.debugTriggerCurfew()
        var settings = engine.settings
        settings.soundOn.toggle()
        engine.apply(settings, now: now)
        XCTAssertEqual(engine.state, .endOfDay, "Unrelated setting changes must not break preview state")
        engine.endShift(now: now)
        XCTAssertEqual(engine.state, .sitting)
        XCTAssertEqual(engine.elapsed, 30)
        XCTAssertEqual(engine.today.stands, 0)
    }

    @MainActor
    func testRandomDestinationRemainsSameAfterRestart() throws {
        let now = Date()
        let suite = "TIESitTests.Destination.\(UUID().uuidString)"
        let preferences = UserDefaults(suiteName: suite)!
        defer { preferences.removePersistentDomain(forName: suite) }
        let (_, url) = try fixture(now: now)
        let engine = SitEngine(dataURL: url, now: now, startAutomatically: false, preferences: preferences)
        engine.persist(now: now)
        let destinationID = engine.destination.id
        for _ in 0..<10 {
            let restored = SitEngine(dataURL: url, now: now, startAutomatically: false, preferences: preferences)
            XCTAssertEqual(restored.destination.id, destinationID, "Restart must continue the same journey")
        }
    }

    @MainActor
    func testExpiredRestStartsNewJourneyOnRestart() throws {
        let now = Calendar.current.startOfDay(for: Date()).addingTimeInterval(43200)
        let suite = "TIESitTests.RestResume.\(UUID().uuidString)"
        let preferences = UserDefaults(suiteName: suite)!
        defer { preferences.removePersistentDomain(forName: suite) }
        var store = Store()
        store.checkpoint = RunCheckpoint(dayKey: Fmt.dayKey(now), savedAt: now,
                                        state: .resting, elapsed: 0, restRemaining: 120,
                                        destinationID: 7)
        let (_, url) = try fixture(now: now, store: store)
        let engine = SitEngine(dataURL: url, now: now.addingTimeInterval(121), startAutomatically: false, preferences: preferences)
        XCTAssertEqual(engine.state, .sitting)
        XCTAssertTrue(engine.destination.id != 7)
        var finishes = 0
        engine.onRestEnd = { finishes += 1 }
        engine.handleWake(now: now.addingTimeInterval(600))
        XCTAssertEqual(finishes, 0)
        XCTAssertEqual(engine.elapsed, 0)
        preferences.set(7, forKey: "tiesit.planet")
        let fixed = SitEngine(dataURL: url, now: now.addingTimeInterval(121), startAutomatically: false, preferences: preferences)
        XCTAssertEqual(fixed.destination.id, 7)
    }

    @MainActor
    func testLogicalDayAcrossDaylightSavingTransitions() {
        let previous = NSTimeZone.default
        NSTimeZone.default = TimeZone(identifier: "America/New_York")!
        defer { NSTimeZone.default = previous }
        let parser = ISO8601DateFormatter()
        for (date, hour, expected) in [
            ("2026-11-01T03:30:00-05:00", 4, "2026-10-31"),
            ("2026-03-08T04:15:00-04:00", 4, "2026-03-08"),
            ("2026-03-08T03:15:00-04:00", 2, "2026-03-08"),
            ("2026-11-01T01:30:00-04:00", 2, "2026-10-31"),
            ("2026-11-01T01:30:00-05:00", 2, "2026-10-31"),
            ("2026-11-01T02:15:00-05:00", 2, "2026-11-01"),
        ] {
            XCTAssertEqual(Fmt.dayKey(parser.date(from: date)!, startHour: hour), expected, date)
        }
    }

    @MainActor
    func testSessionRecordsStartTimeWithoutAddingPhantomMinutes() throws {
        let now = Calendar.current.startOfDay(for: Date()).addingTimeInterval(43200)
        var store = Store()
        store.settings.restMin = 0
        store.checkpoint = RunCheckpoint(dayKey: Fmt.dayKey(now), savedAt: now,
                                        state: .alert, elapsed: 1500, restRemaining: 0)
        let (engine, _) = try fixture(now: now, store: store)
        engine.unlock(now: now.addingTimeInterval(120))
        XCTAssertEqual(engine.today.sessions.first?.date, now.addingTimeInterval(-1500), "Timeline needs the session start, not unlock time")
        store.settings.forceEndOfDay = true
        store.days[Fmt.dayKey(now)] = DayRecord(total: 600)
        store.checkpoint = RunCheckpoint(dayKey: Fmt.dayKey(now), savedAt: now,
                                        state: .endOfDay, elapsed: 1, restRemaining: 0)
        let (shift, _) = try fixture(now: now, store: store)
        shift.endShift(now: now)
        XCTAssertEqual(shift.today.total, 600, "A one-second remainder must not become an extra minute")
    }

    @MainActor
    func testLiveStatisticsDoNotDoubleCountAndRespectDayStart() throws {
        let now = Date()
        var store = Store()
        store.settings.restMin = 0
        store.checkpoint = RunCheckpoint(dayKey: Fmt.dayKey(now), savedAt: now,
                                        state: .alert, elapsed: 1500, restRemaining: 0)
        let (engine, _) = try fixture(now: now, store: store)
        XCTAssertEqual(engine.today.total, 0)
        XCTAssertEqual(engine.todayIncludingCurrentRun.total, 25)
        XCTAssertEqual(engine.avg7, 25)
        let exported = try JSONDecoder().decode(Store.self, from: engine.exportJSON()!)
        XCTAssertEqual(exported.days[Fmt.dayKey(now)]?.total, 0)
        engine.unlock(now: now)
        XCTAssertEqual(engine.todayIncludingCurrentRun.total, 25)
        XCTAssertEqual(engine.todayIncludingCurrentRun.sessions.count, 1)
        let session = SitSession(hour: 1, minute: 0, minutes: 25, date: now)
        XCTAssertEqual(TimelineBar.startMinute(for: session, dayStartHour: 4), 1260)
    }

    @MainActor
    func testPartialSettingsKeepHistoricalData() throws {
        let now = Date()
        let (_, url) = try fixture(now: now)
        let record: [String: Any] = ["sessions": [], "stands": 2, "maxRun": 25, "total": 50]
        let payload: [String: Any] = ["settings": ["thresholdMin": 25], "days": [Fmt.dayKey(now): record]]
        try JSONSerialization.data(withJSONObject: payload).write(to: url)
        let engine = SitEngine(dataURL: url, now: now, startAutomatically: false)
        XCTAssertEqual(engine.today.total, 50, "Missing optional settings must not reset statistics")
        XCTAssertEqual(engine.settings.thresholdMin, 25)
        XCTAssertEqual(engine.settings.restMin, 5)
    }

    @MainActor
    func testCorruptDataIsBackedUpBeforeReplacement() throws {
        let now = Date()
        let (_, url) = try fixture(now: now)
        let original = Data("{broken-json".utf8)
        try original.write(to: url)
        let engine = SitEngine(dataURL: url, now: now, startAutomatically: false)
        XCTAssertTrue(engine.storageIssue != nil)
        engine.persist(now: now)
        let files = try FileManager.default.contentsOfDirectory(at: url.deletingLastPathComponent(), includingPropertiesForKeys: nil)
        let backup = files.first { $0.lastPathComponent.hasPrefix("data.recovery-") }!
        XCTAssertEqual(try Data(contentsOf: backup), original)
        _ = try JSONDecoder().decode(Store.self, from: Data(contentsOf: url))
    }

    @MainActor
    func testWriteFailuresAreVisibleAndRetryable() throws {
        let now = Date()
        let (engine, url) = try fixture(now: now)
        try FileManager.default.removeItem(at: url)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: false)
        engine.persist(now: now)
        XCTAssertTrue(engine.storageIssue != nil)
        try FileManager.default.removeItem(at: url)
        engine.persist(now: now)
        XCTAssertEqual(engine.storageIssue, nil)
        _ = try JSONDecoder().decode(Store.self, from: Data(contentsOf: url))
    }

    @MainActor
    func testUnknownCheckpointDoesNotEraseHistory() throws {
        let now = Date()
        let (_, url) = try fixture(now: now)
        let payload: [String: Any] = [
            "settings": ["thresholdMin": 0, "restMin": -9, "holdSec": 0, "dayStartHour": 99],
            "days": [Fmt.dayKey(now): ["sessions": [], "stands": 2, "maxRun": 25, "total": 50]],
            "checkpoint": ["state": "unknown-state"]
        ]
        try JSONSerialization.data(withJSONObject: payload).write(to: url)
        let engine = SitEngine(dataURL: url, now: now, startAutomatically: false)
        XCTAssertEqual(engine.today.total, 50)
        XCTAssertEqual(engine.settings.thresholdMin, 45)
        XCTAssertEqual(engine.settings.restMin, 5)
        XCTAssertEqual(engine.settings.holdSec, 5)
        XCTAssertEqual(engine.settings.dayStartHour, 0)
    }

    @MainActor
    func testReminderTracksDisplayConfigurationChanges() throws {
        _ = NSApplication.shared
        NSApp.setActivationPolicy(.prohibited)
        let (engine, _) = try fixture()
        var frames = [NSRect(x: -10000, y: -10000, width: 1024, height: 640),
                      NSRect(x: -12000, y: -10000, width: 800, height: 600)]
        let controller = AlertWindowController(engine: engine, screenFrames: { frames })
        var closes = 0
        controller.show { closes += 1 }
        func visible() -> [NSWindow] { NSApp.windows.filter { $0 is AlertWindow && $0.isVisible } }
        XCTAssertEqual(visible().count, 2)
        frames.removeLast()
        NotificationCenter.default.post(name: NSApplication.didChangeScreenParametersNotification, object: nil)
        XCTAssertEqual(visible().count, 1)
        XCTAssertEqual(visible().first?.frame, frames.first)
        XCTAssertEqual(closes, 0)
        frames = []
        NotificationCenter.default.post(name: NSApplication.didChangeScreenParametersNotification, object: nil)
        XCTAssertEqual(visible().count, 0)
        XCTAssertTrue(controller.isShowing)
        frames = [NSRect(x: -11000, y: -10000, width: 900, height: 700)]
        NotificationCenter.default.post(name: NSApplication.didChangeScreenParametersNotification, object: nil)
        XCTAssertEqual(visible().count, 1)
        controller.close()
        controller.close()
        XCTAssertEqual(closes, 1)
        XCTAssertEqual(visible().count, 0)
        NotificationCenter.default.post(name: NSApplication.didChangeScreenParametersNotification, object: nil)
        XCTAssertEqual(visible().count, 0)
    }

    @MainActor
    func testPreviewCancelAndMidnightKeepRealData() throws {
        let now = Calendar.current.startOfDay(for: Date()).addingTimeInterval(86390)
        var store = Store()
        store.checkpoint = RunCheckpoint(dayKey: Fmt.dayKey(now), savedAt: now,
                                        state: .sitting, elapsed: 90, restRemaining: 0)
        let (engine, _) = try fixture(now: now, store: store)
        engine.debugTriggerAlert()
        engine.cancelPreview(now: now)
        XCTAssertEqual(engine.elapsed, 90)
        XCTAssertEqual(engine.state, .sitting)
        XCTAssertTrue(!engine.isPreview)
        engine.debugTriggerCurfew()
        var closes = 0
        engine.onCurfewExpired = { closes += 1 }
        engine.tick(now: now.addingTimeInterval(11), idleSeconds: 999)
        XCTAssertEqual(closes, 1)
        XCTAssertTrue(!engine.isPreview)
        XCTAssertEqual(engine.today.total, 0)
        XCTAssertEqual(engine.state, .sitting)
        let result = try JSONDecoder().decode(Store.self, from: engine.exportJSON()!)
        XCTAssertEqual(result.days[Fmt.dayKey(now)]?.total, 1)
        XCTAssertEqual(result.days[Fmt.dayKey(now)]?.stands, 0)
    }

    @MainActor
    func testNonCompliantTodayBreaksStreak() throws {
        let now = Date()
        var store = Store()
        store.settings.thresholdMin = 25
        store.days[Fmt.dayKey(now)] = DayRecord(maxRun: 30)
        let yesterday = Calendar.current.date(byAdding: .day, value: -1, to: now)!
        store.days[Fmt.dayKey(yesterday)] = DayRecord(
            sessions: [SitSession(hour: 12, minute: 0, minutes: 25, date: yesterday)],
            stands: 1, maxRun: 25, total: 25)
        let (engine, _) = try fixture(now: now, store: store)
        XCTAssertEqual(engine.streak, 0)
    }

    @MainActor
    func testChangingRestDurationUpdatesActiveRest() throws {
        let now = Calendar.current.startOfDay(for: Date()).addingTimeInterval(43200)
        var store = Store()
        store.checkpoint = RunCheckpoint(dayKey: Fmt.dayKey(now), savedAt: now,
                                        state: .resting, elapsed: 0, restRemaining: 240)
        let (engine, _) = try fixture(now: now, store: store)
        var settings = engine.settings
        settings.restMin = 2
        engine.apply(settings, now: now)
        XCTAssertEqual(engine.restRemaining, 60)
        XCTAssertEqual(engine.restProgress, 0.5)
        settings.restMin = 0
        engine.apply(settings, now: now)
        XCTAssertEqual(engine.state, .sitting)
    }

    @MainActor
    func testShortSleepIsNotSittingTime() throws {
        let now = Calendar.current.startOfDay(for: Date()).addingTimeInterval(43200)
        let (engine, _) = try fixture(now: now)
        engine.tick(now: now.addingTimeInterval(1), idleSeconds: 0)
        engine.handleWake(now: now.addingTimeInterval(30))
        engine.tick(now: now.addingTimeInterval(31), idleSeconds: 0)
        XCTAssertEqual(engine.elapsed, 2)
    }

    @MainActor
    func testRestartOnNextDayRecordsPendingRunOnce() throws {
        let now = Calendar.current.startOfDay(for: Date()).addingTimeInterval(86390)
        var store = Store()
        store.checkpoint = RunCheckpoint(dayKey: Fmt.dayKey(now), savedAt: now,
                                        state: .sitting, elapsed: 600, restRemaining: 0)
        let (engine, url) = try fixture(now: now.addingTimeInterval(120), store: store)
        engine.persist(now: now.addingTimeInterval(120))
        let restored = SitEngine(dataURL: url, now: now.addingTimeInterval(121), startAutomatically: false)
        let result = try JSONDecoder().decode(Store.self, from: restored.exportJSON()!)
        XCTAssertEqual(result.days[Fmt.dayKey(now)]?.total, 10)
    }
}

private func XCTAssertEqual<T: Equatable>(_ actual: T, _ expected: T, _ message: String = "", file: StaticString = #file, line: UInt = #line) {
    if actual != expected { fatalError("Expected \(expected), got \(actual). \(message)", file: file, line: line) }
}
private func XCTAssertTrue(_ value: Bool, file: StaticString = #file, line: UInt = #line) {
    if !value { fatalError("Expected true", file: file, line: line) }
}
private func XCTAssertLessThan<T: Comparable>(_ lhs: T, _ rhs: T, file: StaticString = #file, line: UInt = #line) {
    if !(lhs < rhs) { fatalError("Expected \(lhs) < \(rhs)", file: file, line: line) }
}
private func XCTAssertLessThanOrEqual<T: Comparable>(_ lhs: T, _ rhs: T, file: StaticString = #file, line: UInt = #line) {
    if !(lhs <= rhs) { fatalError("Expected \(lhs) <= \(rhs)", file: file, line: line) }
}
private func XCTAssertGreaterThanOrEqual<T: Comparable>(_ lhs: T, _ rhs: T, file: StaticString = #file, line: UInt = #line) {
    if !(lhs >= rhs) { fatalError("Expected \(lhs) >= \(rhs)", file: file, line: line) }
}

@main
struct RunRegressionChecks {
    @MainActor static func main() throws {
        let checks = RegressionTests()
        defer { checks.cleanup() }
        let scenarios: [(String, () throws -> Void)] = [
            ("layout", { checks.testFlightStaysVisibleAndMovesTowardPlanet() }),
            ("ships", { checks.testShipSpritesAndExhaustPorts() }),
            ("scene-motion", { try checks.testSceneMotionSurvivesReducedMotionAndStaysInBounds() }),
            ("harbor", { checks.testHarborLayoutAndMotion() }),
            ("textures", { checks.testAllPlanetsAreDistinctTransparentSprites() }),
            ("cycle", { try checks.testThresholdUnlockAndRestCycle() }),
            ("idle", { try checks.testIdleAndSleepDoNotAccumulateSitting() }),
            ("checkpoint", { try checks.testCheckpointPreservesRunAndDoesNotCountDowntime() }),
            ("curfew", { try checks.testCurfewPersistsOffDutyAcrossRestart() }),
            ("rollover", { try checks.testRolloverRecordsPendingRunAndClosesStaleAlert() }),
            ("restart-day", { try checks.testRestartOnNextDayRecordsPendingRunOnce() }),
            ("rest-day", { try checks.testRestSurvivesRestartAndDayBoundary() }),
            ("short-sleep", { try checks.testShortSleepIsNotSittingTime() }),
            ("rest-settings", { try checks.testChangingRestDurationUpdatesActiveRest() }),
            ("streak", { try checks.testNonCompliantTodayBreaksStreak() }),
            ("appearance", { try checks.testAppearanceChangesPersistWithoutResettingTimer() }),
            ("destination-restart", { try checks.testRandomDestinationRemainsSameAfterRestart() }),
            ("expired-rest", { try checks.testExpiredRestStartsNewJourneyOnRestart() }),
            ("dst", { checks.testLogicalDayAcrossDaylightSavingTransitions() }),
            ("session-time", { try checks.testSessionRecordsStartTimeWithoutAddingPhantomMinutes() }),
            ("live-stats", { try checks.testLiveStatisticsDoNotDoubleCountAndRespectDayStart() }),
            ("partial-data", { try checks.testPartialSettingsKeepHistoricalData() }),
            ("corrupt-data", { try checks.testCorruptDataIsBackedUpBeforeReplacement() }),
            ("write-failure", { try checks.testWriteFailuresAreVisibleAndRetryable() }),
            ("unknown-checkpoint", { try checks.testUnknownCheckpointDoesNotEraseHistory() }),
            ("displays", { try checks.testReminderTracksDisplayConfigurationChanges() }),
            ("preview-midnight", { try checks.testPreviewCancelAndMidnightKeepRealData() }),
            ("preview", { try checks.testPreviewDoesNotChangeRealProgressOrStatistics() }),
        ]
        let selected = CommandLine.arguments.dropFirst()
        var count = 0
        for (name, run) in scenarios where selected.isEmpty || selected.contains(name) {
            try run()
            count += 1
            print("PASS: \(name)")
        }
        precondition(count > 0, "Unknown scenario")
        print("PASS: \(count) regression scenarios")
    }
}
