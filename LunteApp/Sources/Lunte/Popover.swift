import AppKit
import FuseKit
import LunteCore
import Sparkle
import SwiftUI

/// Everything but the fuse, which lives in the menu bar. Onboarding until you've owned your first (test) Boom; then one
/// block for you: "Lunte" and what's left of the fuse, the way Battery shows its charge, a line or two of text, and the
/// session as dots. Under it today's earlier sessions, then the ones before behind Previously, then the Club and
/// Settings, a row each, with the margins of the system's own menus. Between sessions, the first open shows the last
/// session instead.
struct PopoverView: View {
    @ObservedObject var model: GameModel
    let updater: SPUStandardUpdaterController?
    @State private var hovered: Double? // the hovered message's ts, so the line always shows its latest rating

    var body: some View {
        let boom = model.state.boomed ? model.state.booms.last : nil
        let firstBoom = model.connected && !model.onboarded
        VStack(alignment: .leading, spacing: 10) {
            if !model.connected {
                OnboardingView(model: model) // a new Mac starts here
            } else if firstBoom {
                FirstBoomCard(model: model)
            } else {
                // The top is the session you're in, and only that; a finished one waits in Today.
                if model.state.sitting != nil {
                    FuseHeader(model: model, boom: boom, hovered: hovered)
                    Strip(model: model, boom: boom, hovered: $hovered)
                } else {
                    TitleRow(trailing: percent(model.state.left))
                }
                History(model: model, sessions: model.past)
                Divider()
                ClubRow(model: model)
            }
            Divider()
            Footer(model: model, updater: updater)
        }
        .padding(.horizontal, 14).padding(.top, 12).padding(.bottom, 9)
        .frame(width: 308)
        .background { if boom != nil || firstBoom { BoomTint() } } // snaps on with the Boom, no fade
    }
}

/// A row you can click, lit while the pointer is on it, like the rows in the system's own menus. The light reaches
/// past the row, so it never moves the layout.
struct Lit: ViewModifier {
    @State private var on = false

    func body(content: Content) -> some View {
        content
            .contentShape(Rectangle())
            .onHover { on = $0 }
            .background {
                RoundedRectangle(cornerRadius: 6).fill(Color.primary.opacity(on ? 0.08 : 0)).padding(.horizontal, -7).padding(.vertical, -3)
            }
    }
}

/// A red wash from the top, for the Boom.
private struct BoomTint: View {
    var body: some View {
        LinearGradient(colors: [Color.red.opacity(0.17), Color.red.opacity(0.05)], startPoint: .top, endPoint: UnitPoint(x: 0.5, y: 0.6))
    }
}

/// Where the Club sits in the footer, while the Heat Detector isn't ready: the download's progress, or a way to start it.
private struct DetectorStatus: View {
    @ObservedObject var model: GameModel

    var body: some View {
        switch model.detector {
        case .downloading(let share):
            HStack(spacing: 6) {
                ProgressView(value: share).frame(width: 90)
                Text("\(Int((share * 100).rounded()))%").font(.caption.monospacedDigit()).foregroundStyle(.secondary)
            }
            .help("Downloading the Heat Detector")
        case .settingUp:
            HStack(spacing: 6) { ProgressView().controlSize(.small); Text("Setting up…").font(.caption).foregroundStyle(.secondary) }
                .help("Getting the Heat Detector ready on this Mac. Only the first time.")
        case .failed(let why):
            Button("Retry download", action: model.installDetector).buttonStyle(.borderless).font(.callout).help(why)
        default:
            Button("Get the Heat Detector", action: model.installDetector).buttonStyle(.borderless).font(.callout)
        }
    }
}

/// Onboarding, until your first (test) Boom: the title row, the game in one line, and three steps as rows, like
/// networks in Wi-Fi, one at a time: the one you're on is blue and shows what to do, a done one has a check. Once the
/// download has started you can move on: one ring fills around its circle, the download to 80 % and the install the
/// rest, and tuning starts by itself once the model is in, filling a ring of its own. Then one row: ready for your first
/// Boom? A step that finishes collapses as the next one opens, with the panel.
// Why: a visible checklist, the download honestly a step of its own (hq: docs/research/game-feel-and-motivation.md)
private struct OnboardingView: View {
    @ObservedObject var model: GameModel
    static let phrase = "3 2 1 boom"
    @State private var copied = false

    var body: some View {
        let done = [model.detector == .ready, model.pluginInstalled || model.connected, model.fuse.isTuned]
        let downloading = model.detector == .settingUp || model.detector.share != nil
        // The first step not done, passing the download while it runs, unless it's all that's left.
        let now = done.indices.first { !done[$0] && !($0 == 0 && downloading) } ?? done.firstIndex(of: false)
        let tuning: Double? = if case .tuning(let n, let of) = model.fuse { Double(n) / Double(max(of, 1)) } else { nil }
        VStack(alignment: .leading, spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                TitleRow(trailing: now == nil ? "Ready" : "\(done.filter { $0 }.count) of 3")
                Text("Keep it cool. Or go boom.").foregroundStyle(.secondary)
            }
            Divider()
            VStack(alignment: .leading, spacing: 14) {
                if now == nil {
                    Step(symbol: "flame", title: "Ready for your first Boom?", now: true) {
                        Text("Open Claude Code and type “\(Self.phrase)”.").textSelection(.enabled)
                    } action: {
                        Button { copyToClipboard(Self.phrase) } label: { Image(systemName: "doc.on.doc") }.buttonStyle(.borderless).help("Copy")
                    }
                } else {
                    Text("Set up").fontWeight(.medium).foregroundStyle(.secondary)
                    // One ring: the download to 80 %, then the install, which takes about 20 s, creeping on to 97 %.
                    Step(symbol: "arrow.down", title: done[0] ? "Heat Detector installed" : "Heat Detector", done: done[0], now: now == 0,
                         progress: model.detector == .settingUp ? 0.97 : model.detector.share.map { $0 * 0.8 },
                         takes: model.detector == .settingUp ? 20 : 0.3) {
                        detector
                    } action: {
                        detectorAction
                    }
                    Step(symbol: "link", title: done[1] ? "Connected to Claude Code" : "Connect to Claude Code", done: done[1], now: now == 1) {
                        if let error = model.connectError { Text(error).foregroundStyle(.red).textSelection(.enabled) }
                        else { Text("Adds Lunte's plugin, so it hears your prompts. Then start a new chat.") }
                    } action: {
                        Button(model.connecting ? "Connecting…" : "Connect", action: model.connect).disabled(model.connecting)
                    }
                    Step(symbol: "slider.horizontal.3", title: done[2] ? "Tuned to you" : "Tune hot and cool", done: done[2], now: now == 2,
                         progress: tuning) {
                        if let line = model.fuseLine, model.fuse.isFailed { Text(line).foregroundStyle(.red) }
                        else if tuning == nil {
                            Text("Paste the prompt into a new Claude Code chat. Your AI rates your recent prompts, and the model learns what hot and cool are for you.")
                        }
                    } action: {
                        if tuning == nil { Button(copied ? "Copied" : "Copy prompt") { model.copySetupPrompt(); copied = true } }
                    }
                }
            }
            .animation(MenuPanel.expand, value: [now ?? 3] + done.map { $0 ? 1 : 0 })
        }
    }

    /// What the Heat Detector is, with a link to it, or why it failed. While it downloads, the ring says how far.
    @ViewBuilder private var detector: some View {
        switch model.detector {
        case .downloading, .settingUp, .ready: EmptyView()
        case .failed(let why): Text(why).foregroundStyle(.red)
        case .notInstalled:
            Text(.init("Download a local model that measures the heat in your prompts, right on this Mac. "
                + ByteCountFormatter.string(fromByteCount: HeatDetector.totalBytes, countStyle: .file)
                + " from [Hugging Face](\(HeatDetector.page))."))
        }
    }

    @ViewBuilder private var detectorAction: some View {
        switch model.detector {
        case .downloading, .settingUp, .ready: EmptyView()
        case .failed: Button("Retry", action: model.installDetector)
        case .notInstalled: Button("Download", action: model.installDetector)
        }
    }
}

/// One onboarding step as a row: its symbol in a circle, blue while it's the one you're on, a check once it's done,
/// and while it runs, a blue ring filling around a grey circle, each move over `takes` seconds. Only the step you're on
/// shows its button and a line under it on what to do.
private struct Step<Detail: View, Action: View>: View {
    let symbol: String
    let title: String
    var done = false
    let now: Bool
    var progress: Double?
    var takes = 0.3
    @ViewBuilder let detail: Detail
    @ViewBuilder let action: Action

    var body: some View {
        let lit = now && progress == nil // a running step stays grey, so its ring shows
        HStack(alignment: .top, spacing: 9) {
            ZStack {
                Circle().fill(lit ? Color.accentColor : Color.primary.opacity(0.08))
                if let progress {
                    Circle().trim(from: 0, to: progress).stroke(Color.accentColor, style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
                        .rotationEffect(.degrees(-90)).padding(1.25).animation(.linear(duration: takes), value: progress)
                }
                Image(systemName: done ? "checkmark" : symbol).font(.system(size: 12, weight: .medium))
                    .foregroundStyle(lit ? Color.white : now ? Color.accentColor : .secondary)
            }
            .frame(width: 26, height: 26)
            VStack(alignment: .leading, spacing: 3) {
                HStack {
                    Text(title).foregroundStyle(now ? .primary : .secondary)
                    Spacer(minLength: 6)
                    if now { action.controlSize(.small) }
                }
                .frame(minHeight: 26)
                if now { detail.font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true) }
            }
        }
    }
}

/// Onboarding's last two steps: the test Boom, in the same words and field as a real one, owned with "it was a
/// test", then a fresh fuse in 10 seconds.
private struct FirstBoomCard: View {
    @ObservedObject var model: GameModel
    @State private var line = "it was a test"

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                TitleRow(trailing: "Boom")
                if let owned = model.ownedTest {
                    Text("Your first Boom").foregroundStyle(.secondary)
                    Text("“\(owned.line)”")
                    TimelineView(.periodic(from: .now, by: 1)) { context in
                        Text("Fresh fuse in " + countdown(max(0, owned.freshAt.timeIntervalSince(context.date)))).monospacedDigit().foregroundStyle(.secondary)
                    }
                } else {
                    Text("Your first Boom. Everyone heard that.").foregroundStyle(.secondary)
                    Text("“\(OnboardingView.phrase)”")
                }
            }
            if model.ownedTest == nil { LineField(line: $line, send: own) }
        }
    }

    private func own() {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty { model.ownTest(trimmed) }
    }
}

/// The line about a Boom: a plain field with a faint "What happened?" until the first letter, at most 40 characters,
/// sent with return or the return button. Nothing labels it.
struct LineField: View {
    @Binding var line: String
    let send: () -> Void

    var body: some View {
        HStack(spacing: 6) {
            TextField("", text: $line).textFieldStyle(.plain).onSubmit(send)
                .overlay(alignment: .leading) { // an example, faint, gone at the first letter
                    if line.isEmpty { Text("What happened?").foregroundStyle(.tertiary).allowsHitTesting(false) }
                }
                .onChange(of: line) { _, new in if new.count > GameModel.justifyLimit { line = String(new.prefix(GameModel.justifyLimit)) } }
            Button(action: send) { Image(systemName: "return") }
                .buttonStyle(.borderless).foregroundStyle(line.isEmpty ? .tertiary : .secondary)
                .accessibilityLabel("Send")
        }
        .padding(.horizontal, 8).padding(.vertical, 5)
        .background(Color.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 7))
    }
}

/// "Lunte" on the left and, on the right, what's left of the fuse, the way Battery shows its charge; once it's empty,
/// a word for what happened since.
struct TitleRow: View {
    let trailing: String

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text("Lunte").font(.headline)
            Spacer()
            Text(trailing).monospacedDigit().foregroundStyle(.secondary)
        }
    }
}

/// The title row, then one place for text: on its own it says what the fuse is doing and when the session ends, and
/// the prompt still burning it most; point at a dot and it shows that prompt. Blown, the Boom stays picked until you
/// point at another dot. Its height is fixed, so pointing never makes the popover jump.
private struct FuseHeader: View {
    @ObservedObject var model: GameModel
    let boom: Boom?
    let hovered: Double?

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            let now = context.date.timeIntervalSince1970
            let picked = hovered ?? boom?.ts
            VStack(alignment: .leading, spacing: 2) {
                TitleRow(trailing: trailing)
                ZStack(alignment: .topLeading) { // a ZStack, not a background, so the room counts toward the height
                    if model.state.sitting != nil { Room(ratings: model.showRatings) }
                    VStack(alignment: .leading, spacing: 2) {
                        if let e = picked.flatMap({ ts in model.session.first { $0.ts == ts } }) {
                            PromptLines(model: model, event: e, boom: boom, now: now, picked: hovered == nil)
                        } else {
                            Text(state(now)).foregroundStyle(.secondary)
                                .help("If you send nothing else. Every prompt starts the \(Int(Game.sittingGap / 60)) minutes over.")
                            if let hottest = model.state.currentBurns.max(by: { $0.heat(at: now) < $1.heat(at: now) }) {
                                PromptText(model: model, event: hottest, lines: 1).foregroundStyle(.secondary)
                            }
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .topLeading)
            }
        }
    }

    /// What's left while there's any. Blown, the menu bar's word for what happened since: the tier's name, then Still
    /// burning or Calmed down.
    private var trailing: String { boom == nil ? percent(model.state.left) : model.fuseLook.word }

    /// What the fuse is doing in a word, or "Held it together" for a while after a close call, never coloured; and in
    /// the last 10 minutes, when the session ends if nothing else is sent.
    private func state(_ now: Double) -> String {
        guard let sitting = model.state.sitting else { return "Your next prompt starts a session" }
        // Why: competence, and relief right after the act (docs/why.md#close-call)
        let word = model.heldTogether ? "Held it together" : Game.word(model.state, now: now)
        let left = sitting.end + Game.sittingGap - now
        return left < Self.soon ? word + " · session ends in " + minutes(left) : word
    }

    /// How close the fresh fuse has to be before the popover counts down to it.
    static let soon: Double = 600
}

/// The room the lines under the title always take while a session is open, whatever they show: two lines (and the
/// model's numbers, when they're on).
private struct Room: View {
    let ratings: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(" \n ")
            if ratings { Text(" \n \n ").font(.caption2) }
        }
        .hidden()
    }
}

/// One prompt, under the title: how long ago and its heat in a word, then its text. The Boom, picked because you're
/// blown and pointing at nothing, says when it went off and when a fresh fuse comes, and shows your line about it once
/// you've written one.
private struct PromptLines: View {
    @ObservedObject var model: GameModel
    let event: Event
    let boom: Boom?
    let now: Double
    let picked: Bool

    var body: some View {
        let heat = event.heat(at: now), rating = event.awaitingRating(at: now), cool = isCool(event)
        let setItOff = boom?.ts == event.ts, cooled = heat >= 0.15 && !model.state.currentBurns.contains { $0.ts == event.ts }
        VStack(alignment: .leading, spacing: 2) {
            if setItOff && picked {
                // Why: a fresh start, when the session closes (docs/why.md#fresh-start)
                let quiet = Int(Game.sittingGap / 60)
                let fresh = model.freshLeft(at: Date(timeIntervalSince1970: now)).flatMap { $0 >= FuseHeader.soon ? nil : $0 > 0 ? "fresh fuse in " + countdown($0) : "fresh fuse any second" }
                Text(([ago(event.ts, now: now)] + [fresh].compactMap { $0 }).joined(separator: " · "))
                    .monospacedDigit().foregroundStyle(.secondary).lineLimit(1)
                    .help("Every prompt starts the \(quiet) minutes over. Then the session closes, and the next one starts on a fresh fuse.")
            } else {
                // A neutral message gets no word: heatWord's "cool" would read as the cool score.
                let word = rating ? "rating…" : heat < 0.15 ? (cool ? "cool" : nil) : Game.heatWord(heat) + (cool ? " and cool" : "")
                Text(([ago(event.ts, now: now)] + [word].compactMap { $0 } + (cooled ? ["cooled off"] : []) + (setItOff ? ["set it off"] : [])).joined(separator: " · "))
                    .foregroundStyle(.secondary).lineLimit(1)
            }
            // Your line about the Boom stays in the dots, where you wrote it; up here, the prompt that set it off.
            PromptText(model: model, event: event, lines: 1)
                .foregroundStyle(heat < 0.15 && !setItOff ? .secondary : .primary)
            if model.showRatings {
                HStack(alignment: .top, spacing: 4) {
                    if rating { ProgressView().controlSize(.mini) }
                    Text(debug(heat: heat, rating: rating)).font(.caption2.monospacedDigit()).foregroundStyle(.secondary).lineLimit(3)
                }
            }
        }
    }

    /// The numbers behind a dot: the model's heat (or the word list's), what it burns, the mood, and what the word list saw.
    private func debug(heat: Double, rating: Bool) -> String {
        let words = model.cachedPrompt(event).map(Classifier.signals).flatMap { $0.isEmpty ? nil : $0.joined(separator: ", ") } ?? event.burn.rawValue
        if rating { return "Laya is rating it…\nwords: " + words }
        let source = event.heat != nil ? "Laya" : event.rated == true ? "word list, Laya didn't answer" : "word list"
        return "heat \(Int((heat * 100).rounded()))% (\(source)) · burns \(Int((heat * heat * 100).rounded()))%"
            + (event.mood.map { " · \($0)" } ?? "") + "\nwords: " + words
    }
}

/// A prompt's text in quotes, read from Claude Code's history the first time it shows, and kept in memory only.
struct PromptText: View {
    @ObservedObject var model: GameModel
    let event: Event
    var lines = 2
    @State private var texts: [Double: String] = [:]
    @State private var missing: Set<Double> = []

    var body: some View {
        Group {
            if let text = texts[event.ts] { Text("“\(text)”") }
            else { Text(missing.contains(event.ts) ? "Couldn’t find this message in Claude’s history." : "…") }
        }
        .lineLimit(lines).truncationMode(.tail)
        .task(id: event.ts) {
            guard texts[event.ts] == nil, !missing.contains(event.ts) else { return }
            if let found = await model.promptText(event) { texts[event.ts] = found } else { missing.insert(event.ts) }
        }
    }
}

/// The open session as dots that wrap, oldest first: grey neutral, orange heated, red boiling, a soft green ember for
/// cool, and the tier's emoji where it blew. Right after the Boom's dot the dots make room for your line about it, then
/// for the Club's reactions, and carry on after. Past eight rows they scroll, newest at the bottom, fading out at the top;
/// past 15 prompts, a caption counts them. The dots touch (no dead space between them), so moving across them never
/// drops the hover.
// Why: persistence; the whole session stays readable (docs/why.md#whole-session-dots)
private struct Strip: View {
    @ObservedObject var model: GameModel
    let boom: Boom?
    @Binding var hovered: Double?
    @State private var height: CGFloat = 0
    private let cell: CGFloat = 18
    static let rows: CGFloat = 8

    var body: some View {
        let session = model.session, now = Date().timeIntervalSince1970
        let id = boom.map(model.litID)
        let room = id // the field, then your line and the Club's reactions, for as long as you're blown
        let split = room.flatMap { _ in boom.flatMap { b in session.firstIndex { $0.ts == b.ts }.map { $0 + 1 } } }
        VStack(alignment: .leading, spacing: 6) {
            ScrollView {
                VStack(alignment: .leading, spacing: 4) {
                    if let split, let room {
                        dots(session[..<split], now: now, id: id)
                        BoomRow(model: model, boom: room)
                        if split < session.count { dots(session[split...], now: now, id: id) }
                    } else {
                        dots(session[...], now: now, id: id)
                    }
                }
                .padding(.bottom, cell) // a free row for the next dots, at every length, so a new row never moves anything
                .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { height = $0 }
            }
            .defaultScrollAnchor(.bottom)
            .scrollIndicators(.never) // the fade says there's more; a scroller only gets in the way
            .modifier(EdgeFade(depth: cell))
            .frame(height: min(height, Self.rows * cell))
            .onHover { if !$0 { hovered = nil } } // leaving the dots clears it, not leaving one dot
            // Always a line's room under the dots, so the count coming in at 16 never moves anything.
            if let start = session.first?.ts {
                Text(session.count > 15 ? "\(session.count) prompts in the last \(minutes(now - start))" : " ").font(.caption2).foregroundStyle(.tertiary)
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("\(session.count) messages this session, \(session.filter { $0.heat(at: now) >= 0.35 }.count) of them heated, \(session.filter(isCool).count) cool")
    }

    private func dots(_ events: ArraySlice<Event>, now: Double, id: String?) -> some View {
        let marks = blasts()
        return LazyVGrid(columns: [GridItem(.adaptive(minimum: cell, maximum: cell), spacing: 0)], alignment: .leading, spacing: 0) {
            ForEach(events, id: \.ts) { e in
                Group {
                    if let mark = marks[e.ts] { Text(mark).font(.system(size: 12)) }
                    else if e.awaitingRating(at: now) { RatingDot() }
                    else { Dot(heat: e.heat(at: now), cool: isCool(e)) }
                }
                .frame(width: cell, height: cell)
                .background(hovered == e.ts || (hovered == nil && boom?.ts == e.ts) ? Color.secondary.opacity(0.18) : .clear, in: RoundedRectangle(cornerRadius: 4))
                .contentShape(Rectangle())
                .onHover { if $0 { hovered = e.ts } }
                // Easter egg: once you've written your line, each tap on the Boom shaves a little off the wait.
                .onTapGesture { if e.ts == boom?.ts, let id, !model.canJustify(id) { model.hurry() } }
            }
        }
        .accessibilityHidden(true)
    }

    /// Where it blew, and where it went up a tier: 💥, 💥 again, ☢️ (one emoji per dot).
    private func blasts() -> [Double: String] {
        var marks: [Double: String] = [:]
        for boom in model.state.booms {
            for (i, ts) in ([boom.ts] + boom.escalations).enumerated() { marks[ts] = tier(i + 1).emoji.last.map(String.init) ?? "💥" }
        }
        return marks
    }
}

/// In the dots, right after the Boom: a line about it, if you want, sent with return. Nothing labels it and nothing
/// asks twice. Sent, it pops out as your bubble, blue and on the right like a message you sent, and stays; the Club's
/// reactions pop in under it, counted, and pointing at one says who threw it. That's the reward, so it never goes away
/// while you're blown. It's saved on this Mac either way.
// ponytail: silence is the mystery, so nothing invites staying quiet
private struct BoomRow: View {
    @ObservedObject var model: GameModel
    let boom: String // the id its fuse was lit for
    @State private var line = ""
    @State private var sending = false
    @State private var pointed: String? // the reaction pointed at, whose names show

    var body: some View {
        let mine = model.justifications[boom], reacted = model.reacted(boom)
        VStack(alignment: .trailing, spacing: 5) {
            if let mine {
                // Sent: your bubble, as the Club sees it, and it stays.
                Text(mine).foregroundStyle(.white)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 11).padding(.vertical, 6)
                    .background(Color.accentColor, in: UnevenRoundedRectangle(topLeadingRadius: 14, bottomLeadingRadius: 14,
                                                                               bottomTrailingRadius: 4, topTrailingRadius: 14, style: .continuous))
                    .padding(.leading, 40) // a long one still keeps to the right
                    .transition(.scale(scale: 0.5, anchor: .bottomTrailing).combined(with: .opacity))
            } else {
                LineField(line: $line, send: send).transition(.opacity)
            }
            if let reacted {
                HStack(spacing: 4) {
                    if let who = reacted.first(where: { $0.emoji == pointed }) {
                        Text(who.names.joined(separator: ", ")).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                            .transition(.opacity)
                    }
                    ForEach(reacted, id: \.emoji) { r in
                        Text("\(r.emoji) \(r.n)").monospacedDigit()
                            .padding(.horizontal, 7).padding(.vertical, 2)
                            .background(Capsule().fill(Color.accentColor.opacity(0.14)))
                            .onHover { pointed = $0 ? r.emoji : pointed == r.emoji ? nil : pointed }
                            .transition(.scale(scale: 0.3).combined(with: .opacity))
                    }
                }
                .animation(.easeOut(duration: 0.15), value: pointed)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(reacted.map { "\($0.emoji) \($0.n), from \($0.names.joined(separator: ", "))" }.joined(separator: "; "))
            }
        }
        .frame(maxWidth: .infinity, alignment: .trailing)
        .padding(.vertical, 4)
        .animation(MenuPanel.expand, value: mine)
        .animation(.spring(duration: 0.35, bounce: 0.3), value: model.reactions[boom]?.count)
    }

    private func send() {
        guard !line.trimmingCharacters(in: .whitespaces).isEmpty, !sending else { return }
        sending = true
        Task {
            if let error = await model.justify(boom, line) { Alerts.tell("Saved, but your Club didn't get it", error) }
            sending = false
        }
    }
}

/// A scroll view's ends fade out softly where there's more to scroll, like the system's own lists, instead of cutting
/// the rows off hard: at the top once you've scrolled down, at the bottom while there's more below.
struct EdgeFade: ViewModifier {
    var depth: CGFloat = 16
    @State private var more = (top: false, bottom: false)

    func body(content: Content) -> some View {
        Group {
            if #available(macOS 15, *) {
                content.onScrollGeometryChange(for: [Bool].self) { g in
                    [g.visibleRect.minY > 1, g.visibleRect.maxY < g.contentSize.height - 1]
                } action: { _, new in more = (new[0], new[1]) }
            } else {
                content // ponytail: macOS 14 clips hard; it has no scroll geometry to know which end has more
            }
        }
        .mask {
            VStack(spacing: 0) {
                LinearGradient(colors: [.clear, .black], startPoint: .top, endPoint: .bottom).frame(height: more.top ? depth : 0)
                Color.black
                LinearGradient(colors: [.black, .clear], startPoint: .top, endPoint: .bottom).frame(height: more.bottom ? depth : 0)
            }
        }
    }
}

/// One message: grey when neutral, orange when heated, red when boiling. A cool one glows soft green, an ember, over
/// whatever heat it has, so roasting your agent live shows both.
private struct Dot: View {
    let heat: Double
    let cool: Bool

    var body: some View {
        Circle().fill(cool && heat < 0.35 ? Color.green.opacity(0.5) : dotColor(heat))
            .frame(width: 12, height: 12)
            .shadow(color: cool ? Color.green.opacity(0.7) : .clear, radius: 2.5)
    }
}

/// A message Laya is still rating: a grey dot breathing until its colour arrives.
private struct RatingDot: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var faint = false

    var body: some View {
        Circle().fill(Color.secondary.opacity(0.35)).frame(width: 12, height: 12)
            .opacity(faint ? 0.25 : 1)
            .onAppear { if !reduceMotion { withAnimation(.easeInOut(duration: 0.7).repeatForever()) { faint = true } } }
    }
}

/// The Club in one row: a house, blue once you're in one, like the network you're on in Wi-Fi; its name; and a dot when
/// something happened there since you last looked. It opens the Club's window. While the Heat Detector isn't ready,
/// its download sits here instead.
private struct ClubRow: View {
    @ObservedObject var model: GameModel

    var body: some View {
        if model.detector != .ready {
            DetectorStatus(model: model)
        } else {
            Button { ClubWindow.show(model) } label: {
                HStack(spacing: 9) {
                    Image(systemName: "house.fill").font(.system(size: 12)).foregroundStyle(model.club == nil ? Color.secondary : .white)
                        .frame(width: 26, height: 26).background(model.club == nil ? Color.primary.opacity(0.08) : .accentColor, in: Circle())
                    Text(model.club == nil ? "Join a Club" : model.clubName ?? model.club ?? "")
                    Spacer()
                    if model.clubNews {
                        Circle().fill(Color.accentColor).frame(width: 8, height: 8).accessibilityLabel("Something new")
                    }
                }
                .modifier(Lit())
            }
            .buttonStyle(.plain)
        }
    }
}

/// The last row, as in the system's own menus ("Battery Settings…"): Lunte Settings…, which opens its window.
private struct Footer: View {
    @ObservedObject var model: GameModel
    let updater: SPUStandardUpdaterController?

    var body: some View {
        Button { SettingsWindow.show(model, updater) } label: {
            HStack {
                Text("Lunte Settings…")
                Spacer()
            }
            .modifier(Lit())
        }
        .buttonStyle(.plain)
    }
}

/// Lunte's settings in a window of their own: the sound, the model's ratings, onboarding, an idea for Lunte,
/// updates, and Quit.
@MainActor
enum SettingsWindow {
    private static var window: NSWindow?

    static func show(_ model: GameModel, _ updater: SPUStandardUpdaterController?) {
        if window == nil {
            let w = NSWindow(contentViewController: NSHostingController(rootView: SettingsView(model: model, updater: updater)))
            w.title = "Lunte Settings"
            w.styleMask = [.titled, .closable]
            w.isReleasedWhenClosed = false
            w.center()
            window = w
        }
        NSApp.activate()
        window?.makeKeyAndOrderFront(nil)
    }
}

struct SettingsView: View {
    @ObservedObject var model: GameModel
    let updater: SPUStandardUpdaterController?

    var body: some View {
        VStack(spacing: 0) {
            settings
            HStack { // last, as the last thing you'd do, bare at the bottom like a dialog's button
                Spacer()
                Button("Quit Lunte") { NSApp.terminate(nil) }
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 20)
        }
        .frame(width: 400)
        .fixedSize()
    }

    private var settings: some View {
        Form {
            Section { // the app and its version, then its settings
                HStack(spacing: 12) {
                    Image(nsImage: NSApp.applicationIconImage).resizable().frame(width: 40, height: 40)
                    VStack(alignment: .leading, spacing: 1) {
                        Text("Lunte").font(.headline)
                        if let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String {
                            Text("Version \(version)").font(.subheadline).foregroundStyle(.secondary)
                        }
                    }
                    Spacer()
                    Button("Check for updates…") { updater?.checkForUpdates(nil) }.disabled(updater == nil)
                }
            }
            Section {
                // Why: the Boom is the only sound unless you ask (docs/why.md#fuse-sounds-opt-in)
                HStack { // one line, like the rows under it; the form would wrap the control under its label
                    Text("Sound effects")
                    Spacer()
                    Picker("Sound effects", selection: $model.sounds) {
                        Text("Boom").tag(Sounds.boom)
                        Text("Sizzle").tag(Sounds.sizzle)
                        Text("Fireworks").tag(Sounds.fireworks)
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .fixedSize()
                }
                volume("Volume", $model.volume) { Bang.play(volume: model.volume) }
            } footer: {
                Text(model.sounds.about).foregroundStyle(.secondary)
            }
            Section {
                Toggle("Show model ratings", isOn: $model.showRatings)
                // Testing your Boom, connecting and tuning all live in onboarding, so Settings only starts or skips it.
                if model.connected && model.onboarded {
                    LabeledContent("Onboarding") { Button("Replay", action: model.replayOnboarding) }
                } else {
                    LabeledContent("Onboarding") { Button("Skip", action: model.skipOnboarding) }
                }
                LabeledContent("Something you want in Lunte?") { Button("Submit a prompt…", action: model.submitPrompt) }
            }
        }
        .formStyle(.grouped)
        .scrollDisabled(true)
    }

    /// A volume slider like the Mac's own, which plays what it sets when you let go.
    private func volume(_ name: String, _ value: Binding<Double>, sample: @escaping () -> Void) -> some View {
        Slider(value: value, in: 0...1) { Text(name) } minimumValueLabel: {
            Image(systemName: "speaker.fill").foregroundStyle(.secondary)
        } maximumValueLabel: {
            Image(systemName: "speaker.wave.3.fill").foregroundStyle(.secondary)
        } onEditingChanged: { editing in
            if !editing { sample() }
        }
    }
}

/// Grey when calm, orange when heated (telling it off), red when boiling (losing it).
func dotColor(_ heat: Double) -> Color { heat >= 0.85 ? .red : heat >= 0.35 ? .orange : Color.secondary.opacity(0.35) }

/// Talking to your agent like a best bud: your AI's 1 of 3 or more.
func isCool(_ e: Event) -> Bool { (e.cool ?? 0) >= Game.coolPrompt }

/// A Boom tier's emoji and name, by `Boom.tier`: 💥 Boom, 💥💥 Chain reaction, ☢️ Meltdown.
func tier(_ n: Int) -> (emoji: String, name: String) { Game.tiers[min(max(n, 1), Game.tiers.count) - 1] }

/// Grey while full, orange while burning, red in the last third.

/// 0.58 → "58 %" (or "58%", in the Mac's language), rounded down so a fuse that isn't full never says 100.
func percent(_ left: Double) -> String { ((left * 100).rounded(.down) / 100).formatted(.percent.precision(.fractionLength(0))) }

/// 400 seconds ago → "6 min ago": "just now", "6 min ago", "2 h ago".
func ago(_ ts: Double, now: Double) -> String {
    let m = Int((now - ts) / 60)
    return m < 1 ? "just now" : m < 60 ? "\(m) min ago" : "\(m / 60) h ago"
}

/// 1080 seconds → "18 min", 10860 → "3 h 1 min", and under a minute "1 min".
func minutes(_ seconds: Double) -> String {
    let m = max(1, Int((seconds / 60).rounded(.up)))
    return m < 60 ? "\(m) min" : "\(m / 60) h" + (m % 60 > 0 ? " \(m % 60) min" : "")
}

func clock(_ ts: Double) -> String {
    Date(timeIntervalSince1970: ts).formatted(date: .omitted, time: .shortened)
}

/// 523 seconds → "8:43".
func countdown(_ seconds: Double) -> String {
    let s = Int(seconds.rounded(.up))
    return String(format: "%d:%02d", s / 60, s % 60)
}
