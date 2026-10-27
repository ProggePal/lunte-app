#if DEBUG
import AppKit
import FuseKit
import LunteCore
import SwiftUI

/// The popover in every state worth looking at, made from made-up sessions that end just now. Xcode previews them, and
/// `scripts/render-popover.sh` draws the same states to PNG, light and dark.
@MainActor
enum PopoverPreviews {
    static var all: [(name: String, model: GameModel)] {
        [
            ("1-working", working), ("2-last-third", lastThird), ("3-held", held), ("4-blown", blown()),
            ("5-blown-line", blown(line: true)), ("5b-blown-line-sent", blown(line: true, reactions: false)), ("6-last-session", lastSession), ("7-long", long), ("8-fresh", fresh),
        ] + onboarding
    }

    /// Onboarding, a step each: the Heat Detector, connecting, tuning, ready, the test Boom, and owning it.
    static var onboarding: [(name: String, model: GameModel)] {
        [
            ("10-detector", GameModel(onboarding: .notInstalled)),
            ("11-connect", GameModel(onboarding: .downloading(0.42))),
            ("11b-tune-while-downloading", GameModel(onboarding: .downloading(0.8), plugin: true)),
            ("12-tuning", GameModel(onboarding: .ready, plugin: true, fuse: .tuning(done: 140, of: 212))),
            ("12b-installing", GameModel(onboarding: .settingUp, plugin: true)),
            ("13-ready", GameModel(onboarding: .ready, plugin: true, fuse: .tuned(tuned))),
            ("14-first-boom", GameModel(onboarding: .ready, plugin: true, fuse: .tuned(tuned), connected: true)),
            ("15-first-boom-owned", GameModel(onboarding: .ready, plugin: true, fuse: .tuned(tuned), connected: true, owned: "it was a test")),
        ]
    }

    /// A fuse that's been tuned, as far as onboarding can tell.
    static let tuned = try! JSONDecoder().decode(PersonalFuse.self, from: Data("""
        {"v": 1, "probes": [], "mean": [], "sd": [], "weights": [], "bias": 0, "cuts": [null, null, null], "floor": 0,
         "lambda": 1, "trainedOn": 300, "made": "preview"}
        """.utf8))

    /// A slow burn: three warm prompts over 14 minutes, a little more than half the fuse left.
    static var working: GameModel {
        var s = Session()
        s.earlier()
        s.calm(40, 15, cool: [34, 20])
        s.add(14, heat: 0.4, "why is the test still failing")
        s.calm(13, 10)
        s.add(9, heat: 0.45, "you broke the build again")
        s.calm(8, 4)
        s.add(3, heat: 0.3, "no. read the error first")
        s.calm(2, 1)
        return GameModel(preview: s.events, texts: s.texts, feed: feed)
    }

    static var lastThird: GameModel {
        var s = Session()
        s.calm(25, 7, cool: [18])
        s.add(6, heat: 0.6, "WHY would you delete that file")
        s.calm(5, 3)
        s.add(2, heat: 0.6, "put it back. now.")
        return GameModel(preview: s.events, texts: s.texts)
    }

    /// Into the last third, and back out with a cool prompt six minutes ago.
    static var held: GameModel {
        var s = Session()
        s.calm(45, 16)
        s.add(15, .tell, "this is the third time I've asked")
        s.add(12, .tell, "are you even reading what I write")
        s.calm(11, 1, cool: [6])
        return GameModel(preview: s.events, texts: s.texts)
    }

    /// Boomed 12 minutes ago, then a Chain reaction 5 minutes later; still at it.
    static func blown(line: Bool = false, reactions: Bool = true) -> GameModel {
        var s = Session()
        s.calm(35, 21, cool: [28])
        s.add(20, .tell, "stop touching the migrations")
        s.add(15, heat: 0.7, "you touched the migrations")
        s.add(12, .lose, "you deleted my db AGAIN")
        s.calm(11, 10)
        s.add(9, heat: 0.6, "how do I even undo this")
        s.add(7, heat: 0.5, "unbelievable")
        s.calm(6, 1, cool: [2])
        return GameModel(preview: s.events, texts: s.texts, feed: feed, line: line ? "it deleted my migrations again" : nil,
                         reactions: line && reactions ? ["😂 Ola", "😂 Kari", "🫂 Ola", "😂 Sindre"] : [])
    }

    /// A session that closed an hour ago, waiting in Today with its dot: a slow burn, a Boom, and cooled off by the end.
    static var lastSession: GameModel {
        var s = Session()
        s.earlier()
        s.calm(200, 171, cool: [190, 180])
        s.add(170, heat: 0.4, "that's not what I asked for")
        s.calm(169, 162)
        s.add(161, heat: 0.6, "read the spec. again.")
        s.calm(160, 156, cool: [158])
        s.add(155, .lose, "WHAT DID YOU DO")
        s.calm(154, 100, cool: [130, 120, 110])
        s.add(97, heat: 0.4, "close, try once more")
        s.calm(95, 90, cool: [92])
        return GameModel(preview: s.events, texts: s.texts, line: "it rewrote my README as a pirate")
    }

    /// A session that closed an hour ago: a burn into the last third, then the comeback.
    static var comeback: GameModel {
        var s = Session()
        s.calm(150, 121)
        s.add(120, .tell, "this is the third time I've asked")
        s.add(118, heat: 0.75, "WHY THE FUCK DID YOU DELETE MY MIGRATIONS")
        s.calm(117, 112)
        s.add(111, cool: 1, "ok king, you nailed it 🫡 thank you")
        s.calm(110, 95)
        return GameModel(preview: s.events, texts: s.texts)
    }

    /// Three hours and 150 prompts: the oldest fold into a heat line.
    static var long: GameModel {
        var s = Session()
        s.calm(180, 25, step: 1.05, cool: [150, 120, 90, 60, 40])
        s.add(24, heat: 0.45, "that broke the other test")
        s.calm(23, 1, step: 1.05)
        return GameModel(preview: s.events, texts: s.texts, feed: feed)
    }

    /// No session open, the last one already seen, no Club; a Boom yesterday.
    static var fresh: GameModel {
        var s = Session()
        s.earlier(boom: true)
        s.calm(300, 240, cool: [270])
        return GameModel(preview: s.events, texts: s.texts, club: nil)
    }

    /// A Club with a day and a bit behind it: joins, a Boom nobody owned, Ola's line with laughs on it, one of yours,
    /// and a fresh one nobody has reacted to yet.
    static var club: GameModel {
        let now = Date().timeIntervalSince1970, h = 3600.0
        var seq = 0
        func e(_ type: String, _ hoursAgo: Double, boom: String? = nil, emoji: String? = nil, text: String? = nil, from: String? = nil) -> ClubEvent {
            seq += 1
            return ClubEvent(seq: seq, type: type, boom: boom, ts: now - hoursAgo * h, emoji: emoji, text: text, from: from)
        }
        let feed = [
            e("join", 30, from: "Kari"), e("join", 29.5, from: "Ola"), e("join", 29, from: "Paal"),
            e("boom", 26, boom: "a"), e("react", 25.9, boom: "a", emoji: "🧯", from: "Kari"),
            e("join", 5, from: "Sindre"),
            e("boom", 2.4, boom: "b"), e("why", 2.3, boom: "b", text: "it rewrote my README as a pirate", from: "Ola"),
            e("react", 2.2, boom: "b", emoji: "😂", from: "Kari"), e("react", 2.1, boom: "b", emoji: "😂", from: "Sindre"),
            e("react", 2, boom: "b", emoji: "😂", from: "Paal"), e("react", 1.9, boom: "b", emoji: "🫂", from: "Kari"),
            e("boom", 0.7, boom: "c"), e("why", 0.65, boom: "c", text: "it deleted my migrations again", from: "Paal"),
            e("react", 0.6, boom: "c", emoji: "😂", from: "Ola"), e("react", 0.5, boom: "c", emoji: "🐐", from: "Sindre"),
            e("boom", 0.2, boom: "d"),
        ]
        return GameModel(preview: [], texts: [:], feed: feed, members: ["Kari", "Ola", "Paal", "Sindre"], mine: ["c"])
    }

    static var feed: [ClubEvent] {
        let now = Date().timeIntervalSince1970
        return [
            ClubEvent(seq: 1, type: "join", ts: now - 7200, from: "Kari"),
            ClubEvent(seq: 2, type: "boom", boom: "1", ts: now - 2400),
            ClubEvent(seq: 3, type: "why", boom: "1", ts: now - 2300, text: "it rewrote my README as a pirate", from: "Ola"),
        ]
    }

    /// Prompts `minutes` before now, with their text.
    struct Session {
        var events: [Event] = []
        var texts: [Double: String] = [:]
        let now = Date().timeIntervalSince1970
        let calmLines = ["add a loading state to the button", "now the empty state", "make the list scroll", "rename it to fuse",
                         "run the tests", "ok commit that", "what does this regex do", "move it into its own file"]

        mutating func add(_ minutes: Double, _ burn: Burn = .none, heat: Double? = nil, cool: Double = 0, _ text: String) {
            let ts = now - minutes * 60
            events.append(Event(ts: ts, burn: burn, heat: heat ?? (burn == .none ? 0 : nil), cool: cool))
            texts[ts] = text
        }

        /// Earlier sessions, for Today and Previously: two this morning (cool, then a close call) and two before today
        /// (one with a Boom, if `boom`), plus one three days ago.
        mutating func earlier(boom: Bool = false) {
            calm(520, 500, cool: [510])
            calm(420, 412)
            add(411, .tell, "this is the third time I've asked")
            add(409, .tell, "are you even reading what I write")
            calm(408, 392, cool: [400])
            calm(1560, 1540)
            if boom { add(1539, .lose, "WHAT DID YOU DO") }
            calm(1538, 1520)
            calm(1700, 1660)
            calm(4400, 4330, step: 3)
        }

        /// Neutral prompts from `from` to `to` minutes ago, about one a minute; the ones in `cool` banter.
        mutating func calm(_ from: Double, _ to: Double, step: Double = 1.4, cool: [Double] = []) {
            var m = from
            while m >= to {
                add(m, text: calmLines[events.count % calmLines.count])
                m -= step
            }
            for c in cool { add(c - 0.37, cool: 0.7, "lets gooo, ship it bud") } // off the beat, so no two share a time
            events.sort { $0.ts < $1.ts }
        }

        private mutating func add(_ minutes: Double, text: String) { add(minutes, heat: 0, text) }
    }
}

/// `Lunte -PopoverShots DIR`: draws every preview state and the Club's window, light and dark, to DIR/<state>-light.png
/// and -dark.png, then quits. Nothing is watched, polled or sent. `-PopoverOnly "9b pill"` draws just the states whose
/// names start with those; the lab's replay frames only so ("replay"), as they take minutes.
@MainActor
enum PopoverShots {
    static func render(to dir: String) {
        try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        let popovers = PopoverPreviews.all.map { ($0.name, AnyView(PopoverView(model: $0.model, updater: nil))) }
        let fresh = PopoverPreviews.fresh
        let last = PopoverPreviews.lastSession, back = PopoverPreviews.comeback
        let windows = [("9-previously", AnyView(History(model: fresh, sessions: fresh.past, span: .all, opened: .constant(nil)).padding(14).frame(width: 308))),
                       ("9b-opened", AnyView(History(model: last, sessions: last.past, opened: .constant(last.past.last?.start)).padding(14).frame(width: 308))),
                       ("9c-comeback", AnyView(History(model: back, sessions: back.past, opened: .constant(back.past.last?.start)).padding(14).frame(width: 308))),
                       ("pill-lab", AnyView(PillLab())), ("heat-lab", AnyView(HeatLab())),
                       ] + (0..<120).map { (String(format: "replay-%02d", $0), AnyView(PillLab(replay: Double($0) / 15))) } + [
                       ("club", AnyView(ClubView(model: PopoverPreviews.club))), ("club-none", AnyView(ClubView(model: fresh))),
                       ("settings", AnyView(SettingsView(model: fresh, updater: nil)))]
        Task {
            let only = (UserDefaults.standard.string(forKey: "PopoverOnly") ?? "").split(separator: " ")
            for (name, content) in popovers + windows where only.isEmpty ? !name.hasPrefix("replay-") : only.contains(where: { name.hasPrefix($0) }) {
                for dark in [false, true] {
                    let view = NSHostingView(rootView: content.background(Color(nsColor: .windowBackgroundColor)))
                    let window = NSWindow(contentRect: NSRect(x: 40, y: 40, width: 290, height: 400), styleMask: [.borderless], backing: .buffered, defer: false)
                    window.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
                    window.contentView = view
                    window.orderFront(nil)
                    try? await Task.sleep(for: .milliseconds(500)) // the prompts' text loads
                    window.setContentSize(view.fittingSize)
                    try? await Task.sleep(for: .milliseconds(100))
                    guard let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { continue }
                    view.cacheDisplay(in: view.bounds, to: rep)
                    try? rep.representation(using: .png, properties: [:])?
                        .write(to: URL(fileURLWithPath: dir).appending(path: "\(name)-\(dark ? "dark" : "light").png"))
                    window.orderOut(nil)
                }
            }
            NSApp.terminate(nil)
        }
    }
}

// ponytail: a lab to see the heat line at every length; delete it with the pill lab.
/// The opened session's heat line for sessions from one prompt to five hours, all starting at 14:05, and one with a
/// prompt pointed at.
struct HeatLab: View {
    var body: some View {
        let start = Calendar.current.startOfDay(for: Date()).timeIntervalSince1970 + 14 * 3600 + 5 * 60
        let made = { (minutes: Double, count: Int) in
            (0..<count).map { i in
                Event(ts: start + (count > 1 ? Double(i) / Double(count - 1) : 0) * minutes * 60, burn: .none,
                      heat: [0.1, 0.05, 0.4, 0.1, 0, 0.7, 0.2, 0.05, 0.95, 0.1][i % 10], cool: i % 7 == 3 ? 0.8 : 0)
            }
        }
        let rows = [("One prompt", made(0, 1), nil), ("10 min", made(10, 6), nil), ("30 min", made(30, 12), nil),
                    ("2 h", made(120, 40), nil), ("5 h", made(300, 100), nil), ("2 h, pointing at one", made(120, 40), 15)]
        // A session played through the real game, its pill and its line at the same moment of the replay.
        let events = made(120, 40).enumerated().map { var e = $1; e.heat = $0 == 30 ? 1 : $0 == 12 ? 0.8 : e.heat; return e }
        let sitting = Game.replay(events, now: events.last!.ts + 7200).sittings[0], line = Array(Game.fuseLine(sitting, events, now: events.last!.ts + 7200).dropLast())
        let levels = line.map(\.left), times = line.map(\.ts), boomed = sitting.boom != nil
        VStack(alignment: .leading, spacing: 4) {
            ForEach([0.2, 0.45, 0.7, 0.88], id: \.self) { p in
                HStack { SessionFuse(levels: levels, boomed: boomed, replay: p); Text("replay \(p, specifier: "%.2f")").font(.caption).foregroundStyle(.secondary) }
                let shown = sitting.boom.map { b in events.filter { $0.ts <= b.ts + 1800 } } ?? events
                HeatLine(events: shown, impacts: shown.map { _ in 0 }, reading: nil, boom: sitting.boom?.ts, now: events.last!.ts + 7200, at: 0, shown: 0,
                         story: p, intro: p, moment: { SessionFuse.moment(at: $0, levels, times, boomed: boomed) })
                    .frame(height: 42).padding(.bottom, 8) // the line's own height and its headroom
            }
            ForEach([("A stretch dragged out", 60.0...190.0), ("A narrow one", 120.0...140.0)], id: \.0) { name, stretch in
                Text(name).font(.caption).foregroundStyle(.secondary)
                HeatLine(events: made(120, 40), impacts: made(120, 40).map { _ in 0 }, reading: nil, boom: nil, now: Date().timeIntervalSince1970,
                         at: 0, shown: 0, stretch: stretch)
                    .frame(height: 42).padding(.bottom, 8)
            }
            ForEach(rows.indices, id: \.self) { i in
                Text(rows[i].0).font(.caption).foregroundStyle(.secondary)
                HeatLine(events: rows[i].1, impacts: rows[i].1.map { _ in 0 }, reading: rows[i].2, boom: nil, now: Date().timeIntervalSince1970,
                         at: rows[i].1[rows[i].2 ?? 0].ts + 40, shown: rows[i].2 == nil ? 0 : 1)
                    .frame(height: 42).padding(.bottom, 8) // the line's own height and its headroom
            }
        }
        .padding(14)
        .frame(width: 308)
    }
}

// ponytail: a lab to pick the pill by eye; delete it once one is picked.
/// The pill on every made-up session, and a few made-up extremes, frame by frame through its replay, and at rest
/// without its green.
struct PillLab: View {
    static let frames = [0, 0.15, 0.3, 0.45, 0.6, 0.75, 0.9, 1.0]
    var replay: Double? // just a few, this many seconds into their replay, then a breeze: a frame of a GIF

    var body: some View {
        let made = { (name: String, levels: [Double]) in
            (name: name, boomed: levels.last == 0, story: levels.enumerated().map { (ts: Double($0.offset) * 600, left: $0.element) })
        }
        let rows = [PopoverPreviews.fresh, PopoverPreviews.lastSession].flatMap { m in
            m.past.map { s in (name: m.names[s.start] ?? "Session", boomed: s.boom != nil,
                               story: Array(Game.fuseLine(s, m.messages(in: s), now: Date().timeIntervalSince1970).dropLast())) }
        } + [made("Kept its cool", [1, 1.1, 1.2, 1.25]), made("Up and down", [1, 0.6, 1, 0.5, 1, 0.4, 1, 0.7, 1.25, 0.8, 1.2]),
             made("Close call", [1, 0.6, 0.2, 0.1, 0.5]), made("Hanging by a thread", [1, 0.5, 0.12]),
             made("Burnt out", [1, 0.7, 0.4, 0.2, 0]), made("Long and churny", [1, 0.4, 1, 0.4, 1, 0.4, 1, 0.4, 1, 0.4, 1, 0.6, 1.1])]
        if let replay {
            VStack(alignment: .leading, spacing: 8) {
                ForEach(rows.indices.filter { ["Kept its cool", "Good company", "Kaboom", "Burnt out", "Close call", "Up and down", "Long and churny"].contains(rows[$0].name) }, id: \.self) { i in
                    HStack(spacing: 9) {
                        let levels = rows[i].story.map(\.left), boomed = rows[i].boomed, d = SessionFuse.duration(levels, boomed: boomed)
                        SessionFuse(levels: levels, boomed: boomed, replay: min(1, replay / d), gustAt: replay > 4.6 ? replay - 4.6 : nil)
                        Text(rows[i].name)
                    }
                }
            }
            .padding(14)
            .frame(width: 260, alignment: .leading)
            .fixedSize()
        } else {
        Grid(alignment: .leading, horizontalSpacing: 10, verticalSpacing: 8) {
            GridRow {
                Text("")
                ForEach(Self.frames, id: \.self) { Text(String(format: "%.2f", $0)).font(.caption).foregroundStyle(.secondary) }
                Text("Neutral").font(.caption).foregroundStyle(.secondary)
            }
            ForEach(rows.indices, id: \.self) { i in
                GridRow {
                    Text(rows[i].name).lineLimit(1)
                    ForEach(Self.frames, id: \.self) { SessionFuse(levels: rows[i].story.map(\.left), boomed: rows[i].boomed, replay: $0) }
                    SessionFuse(levels: rows[i].story.map(\.left), boomed: rows[i].boomed, green: false)
                }
            }
        }
        .padding(14)
        .fixedSize()
        }
    }
}

#Preview("Working") { PopoverView(model: PopoverPreviews.working, updater: nil) }
#Preview("Last third") { PopoverView(model: PopoverPreviews.lastThird, updater: nil) }
#Preview("Held it together") { PopoverView(model: PopoverPreviews.held, updater: nil) }
#Preview("Blown") { PopoverView(model: PopoverPreviews.blown(), updater: nil) }
#Preview("Blown, line written") { PopoverView(model: PopoverPreviews.blown(line: true), updater: nil) }
#Preview("Last session") { PopoverView(model: PopoverPreviews.lastSession, updater: nil) }
#Preview("A session opened") { let m = PopoverPreviews.lastSession; History(model: m, sessions: m.past, opened: .constant(m.past.last?.start)).padding(14).frame(width: 308) }
#Preview("Long session") { PopoverView(model: PopoverPreviews.long, updater: nil) }
#Preview("Fresh, no Club") { PopoverView(model: PopoverPreviews.fresh, updater: nil) }
#Preview("Onboarding, every step") {
    ScrollView(.horizontal) {
        HStack(alignment: .top) { ForEach(PopoverPreviews.onboarding, id: \.name) { PopoverView(model: $0.model, updater: nil) } }
    }
}
#Preview("Previously, open") { History(model: PopoverPreviews.fresh, sessions: PopoverPreviews.fresh.past, span: .all, opened: .constant(nil)).padding(14).frame(width: 308) }
#Preview("Settings") { SettingsView(model: PopoverPreviews.fresh, updater: nil) }
#Preview("Club window") { ClubView(model: PopoverPreviews.club) }
#Preview("Club window, no Club") { ClubView(model: PopoverPreviews.fresh) }
#endif
