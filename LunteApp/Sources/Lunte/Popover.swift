import AppKit
import FuseKit
import LunteCore
import Sparkle
import SwiftUI

/// Everything but the fuse, which lives in the menu bar. Onboarding until you've owned your first (test) Boom; then one
/// block for you: "Lunte" and what's left of the fuse, the way Battery shows its charge, a line or two of text, and the
/// session as dots. Under it your earlier sessions, then a footer, with the margins of the system's own menus. A
/// session you dive into takes the whole popover, as a Control Center module does.
struct PopoverView: View {
    @ObservedObject var model: GameModel
    let updater: SPUStandardUpdaterController?
    @State private var hovered: Double? // the hovered message's ts, so the line always shows its latest rating
    @State private var drift = 0.0 // which way the pointer's heading along the dots, and how fast, for the words to slide
    @State private var moreOverCard = false // the sessions list has more under its fade, just above the card

    var body: some View {
        let boom = model.state.boomed ? model.state.booms.last : nil
        let firstBoom = model.connected && !model.onboarded
        let card = model.connected && !firstBoom && model.diving == nil // the fuse lately's card closes the popover
        VStack(alignment: .leading, spacing: 10) {
            if !model.connected {
                OnboardingView(model: model) // a new Mac starts here
            } else if firstBoom {
                FirstBoomCard(model: model)
            } else {
                // The top is the session you're in, and only that; a finished one waits in Today.
                if model.diving == nil {
                    if model.state.sitting != nil {
                        FuseHeader(model: model, boom: boom, hovered: hovered, drift: drift)
                        Strip(model: model, boom: boom, hovered: $hovered, drift: $drift)
                    } else {
                        TitleRow(trailing: percent(model.state.left))
                    }
                }
                History(model: model, sessions: model.past, opened: $model.diving)
                if model.diving == nil, ![.ready, .loading].contains(model.detector) { Divider(); DetectorStatus(model: model) } // its download, while it lasts
                if model.diving == nil, [.ready, .loading].contains(model.detector), model.coolUntuned || model.fuseLine != nil { Divider(); CoolNudge(model: model) }
            }
            if model.diving == nil {
                let full = model.connected && !firstBoom
                if !full { Divider() } // the fuse lately's card is its own edge
                Footer(model: model, updater: updater, full: full, under: moreOverCard)
            }
        }
        .onPreferenceChange(MoreOverCard.self) { more in withAnimation(.easeOut(duration: 0.15)) { moreOverCard = more } }
        .padding(.horizontal, 14).padding(.top, 12).padding(.bottom, card ? 14 : 9) // the card sits as far from the bottom as from the sides
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
        let done = [[.ready, .loading].contains(model.detector), model.pluginInstalled || model.connected, model.fuse.isTuned && !model.retuning]
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
        case .downloading, .settingUp, .loading, .ready: EmptyView()
        case .failed(let why): Text(why).foregroundStyle(.red)
        case .notInstalled:
            Text(.init("Download a local model that measures the heat in your prompts, right on this Mac. "
                + ByteCountFormatter.string(fromByteCount: HeatDetector.totalBytes, countStyle: .file)
                + " from [Hugging Face](\(HeatDetector.page))."))
        }
    }

    @ViewBuilder private var detectorAction: some View {
        switch model.detector {
        case .downloading, .settingUp, .loading, .ready: EmptyView()
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
                    TimelineView(.animation(minimumInterval: 1, paused: !model.popoverOpen)) { context in
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
    var left: Double? = nil // what's left, when `trailing` says it, so the digits roll up or down the way it went
    var pointing = false // it says an earlier prompt's, not now's: light then, dark for the fuse as it is

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text("Lunte").fontWeight(.medium)
            Spacer()
            Text(trailing).fontWeight(.medium).monospacedDigit().foregroundStyle(pointing ? .secondary : .primary)
                .contentTransition(left.map { .numericText(value: $0) } ?? .numericText())
                .animation(.snappy, value: trailing) // its digits roll, as a battery's would
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
    var drift = 0.0

    var body: some View {
        TimelineView(.animation(minimumInterval: 1, paused: !model.popoverOpen)) { context in
            let now = context.date.timeIntervalSince1970
            let picked = hovered ?? boom?.ts
            VStack(alignment: .leading, spacing: 2) {
                let (trailing, left) = trailing(now)
                TitleRow(trailing: trailing, left: left, pointing: hovered != nil && hovered != model.session.last?.ts) // dark only for now's
                let lines = VStack(alignment: .leading, spacing: 2) {
                    if let e = picked.flatMap({ ts in model.session.first { $0.ts == ts } }) {
                        PromptLines(model: model, event: e, boom: boom, now: now, picked: hovered == nil, drift: drift)
                    } else {
                        Text(state(now)).foregroundStyle(.secondary)
                            .help("If you send nothing else. Every prompt starts the \(Int(Game.sittingGap / 60)) minutes over.")
                        if let hottest = model.state.currentBurns.max(by: { $0.heat(at: now) < $1.heat(at: now) }) {
                            PromptText(model: model, event: hottest, lines: 1).foregroundStyle(.secondary)
                                .id(hottest.ts)
                                .transition(.asymmetric(insertion: .opacity.animation(.easeOut(duration: 0.14).delay(0.05)),
                                        removal: .opacity.animation(.easeIn(duration: 0.05))))
                        }
                    }
                }
                // While a session's open, only the room counts toward the height, never the words over it (an emoji's
                // taller line too), so pointing at a dot never moves anything.
                if model.state.sitting != nil {
                    Room(ratings: model.showRatings).frame(maxWidth: .infinity, alignment: .topLeading).overlay(alignment: .topLeading) { lines }
                } else {
                    lines.frame(maxWidth: .infinity, alignment: .topLeading)
                }
            }
        }
    }

    /// What's left while there's any, or what was left just after the prompt pointed at. Blown, the menu bar's word for
    /// what happened since: the tier's name, then Still burning or Calmed down.
    // Pointing along the dots, it says what each prompt left of the fuse, so a sweep shows what each one did to it.
    private func trailing(_ now: Double) -> (String, Double?) {
        if let hovered, let sitting = model.state.sitting {
            let left = Game.fuseLine(sitting, model.session, now: now).last { $0.ts <= hovered }?.left ?? 1
            return (percent(left), left)
        }
        return boom == nil ? (percent(model.state.left), model.state.left) : (model.fuseLook.word, nil)
    }

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
            Text(" ") // two lines, as the lines over it are: each its own, 2 points apart
            Text(" ")
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
    var drift = 0.0 // points to slide in from: ahead of the pointer, further the faster it moves

    var body: some View {
        let heat = event.heat(at: now), rating = event.awaitingRating(at: now), setItOff = boom?.ts == event.ts
        VStack(alignment: .leading, spacing: 2) {
            if setItOff && picked {
                // Why: a fresh start, when the session closes (docs/why.md#fresh-start)
                let quiet = Int(Game.sittingGap / 60)
                let fresh = model.freshLeft(at: Date(timeIntervalSince1970: now)).flatMap { $0 >= FuseHeader.soon ? nil : $0 > 0 ? "fresh fuse in " + countdown($0) : "fresh fuse any second" }
                let line = ([ago(event.ts, now: now)] + [fresh].compactMap { $0 }).joined(separator: " · ")
                Text(line).monospacedDigit().foregroundStyle(.secondary).lineLimit(1)
                    .help("Every prompt starts the \(quiet) minutes over. Then the session closes, and the next one starts on a fresh fuse.")
            } else {
                // When, and no word for its heat: its dot already says it. Only while it's rated, and for the Boom's own.
                let line = ([ago(event.ts, now: now)] + (rating ? ["rating…"] : []) + (setItOff ? ["set it off"] : [])).joined(separator: " · ")
                Text(line).monospacedDigit().foregroundStyle(.secondary).lineLimit(1)
            }
            // Your line about the Boom stays in the dots, where you wrote it; up here, the prompt that set it off.
            PromptText(model: model, event: event, lines: 1)
                .foregroundStyle(heat < 0.15 && !setItOff ? .secondary : .primary)
                .id(event.ts)
                // The words fade, the old ones gone almost at once and the new in just after, so two never read over each
                // other, and slide a few points the way the pointer's going, like a carousel turning under it.
                .transition(.asymmetric(insertion: .opacity.combined(with: .offset(x: drift)).animation(.spring(response: 0.34, dampingFraction: 0.92).delay(0.03)),
                                        removal: .opacity.combined(with: .offset(x: -drift / 2)).animation(.easeIn(duration: 0.1))))
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
    var gone: String? = nil // shown in grey once Claude's history has lost it, in place of saying so
    @State private var texts: [Double: String] = [:]
    @State private var missing: Set<Double> = []

    var body: some View {
        Group {
            if let text = texts[event.ts] ?? model.cachedPrompt(event) { Text("“\(text)”") }
            else if missing.contains(event.ts), let gone { Text(gone).foregroundStyle(.secondary) }
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
    @Binding var drift: Double
    @State private var last: (index: Int, at: Date)? // the dot pointed at before, and when
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
                let lit = hovered == e.ts || (hovered == nil && boom?.ts == e.ts)
                Group {
                    if let mark = marks[e.ts] { Text(mark).font(.system(size: 12)) }
                    else if e.awaitingRating(at: now) { RatingDot(open: model.popoverOpen).transition(.opacity) }
                    else { Dot(heat: e.heat(at: now), cool: isCool(e)).transition(.opacity) }
                }
                .animation(.easeOut(duration: 0.25), value: e.awaitingRating(at: now)) // its colour comes in once it's rated
                // The one pointed at grows a little, as the line's do, and settles back.
                .scaleEffect(lit ? 1.35 : 1)
                .animation(.spring(response: 0.25, dampingFraction: 0.65), value: lit)
                .frame(width: cell, height: cell)
                .transition(.scale(scale: 0.3).combined(with: .opacity)) // a new prompt pops in
                .contentShape(Rectangle())
                .onHover { if $0 { point(e) } }
                // Easter egg: once you've written your line, each tap on the Boom shaves a little off the wait.
                .onTapGesture { if e.ts == boom?.ts, let id, !model.canJustify(id) { model.hurry() } }
            }
        }
        .animation(.spring(response: 0.35, dampingFraction: 0.7), value: events.count)
        .accessibilityHidden(true)
    }

    /// Points at a dot, and says which way the words above slide in, and how far: only on a quick sweep, past six dots a
    /// second, from where the pointer's heading, a point or two, 3 at most, so the eye follows the change and never
    /// notices the move. Slower, they only fade.
    private func point(_ e: Event) {
        let i = model.session.firstIndex { $0.ts == e.ts } ?? 0, now = Date()
        if let last, last.index != i {
            let speed = Double(abs(i - last.index)) / max(0.03, now.timeIntervalSince(last.at)) // dots a second
            drift = speed < 6 ? 0 : (i > last.index ? 1 : -1) * min(3, 1 + (speed - 6) * 0.15) // a slow look only fades
        }
        last = (i, now)
        hovered = e.ts
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

    var body: some View {
        let mine = model.justifications[boom]
        VStack(alignment: .trailing, spacing: 5) {
            if mine == nil { LineField(line: $line, send: send).transition(.opacity) }
            Said(model: model, boom: boom) // sent: your bubble, as the Club sees it, and it stays
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

/// Your line about a Boom as your bubble, blue and on the right like a message you sent, and the Club's reactions under
/// it, counted; pointing at one says who threw it. In the dots while you're blown, and in the session after.
struct Said: View {
    @ObservedObject var model: GameModel
    let boom: String // the id its fuse was lit for
    @State private var pointed: String? // the reaction pointed at, whose names show

    var body: some View {
        let reacted = model.reacted(boom)
        VStack(alignment: .trailing, spacing: 5) {
            if let mine = model.justifications[boom] {
                Text(mine).foregroundStyle(.white)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 11).padding(.vertical, 6)
                    .background(Color.accentColor, in: UnevenRoundedRectangle(topLeadingRadius: 14, bottomLeadingRadius: 14,
                                                                               bottomTrailingRadius: 4, topTrailingRadius: 14, style: .continuous))
                    .padding(.leading, 40) // a long one still keeps to the right
                    .transition(.scale(scale: 0.5, anchor: .bottomTrailing).combined(with: .opacity))
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
    }
}

/// A scroll view's ends fade out softly where there's more to scroll, like the system's own lists, instead of cutting
/// the rows off hard: at the top once you've scrolled down, at the bottom while there's more below.
struct EdgeFade: ViewModifier {
    var depth: CGFloat = 16
    var overCard = false // the list just above the fuse lately's card: it says when there's more of it under there
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
        .preference(key: MoreOverCard.self, value: overCard && more.bottom)
    }
}

/// Whether the list just above the fuse lately's card has more below its fade, so a hairline keeps the two apart.
struct MoreOverCard: PreferenceKey {
    static let defaultValue = false
    static func reduce(value: inout Bool, nextValue: () -> Bool) { value = value || nextValue() }
}

/// One message: grey when neutral, orange when heated, red when boiling. A cool one glows soft green, an ember, over
/// whatever heat it has, so roasting your agent live shows both.
private struct Dot: View {
    let heat: Double
    let cool: Bool

    var body: some View {
        Circle().fill(dotStyle(heat: heat, cool: cool))
            .frame(width: 12, height: 12)
            .shadow(color: cool ? Color.green.opacity(0.6) : .clear, radius: 2.5)
    }
}

/// A message's dot: grey, orange or red by its heat; a clear green when it was cool; and when it was both, roasting
/// your agent live, its heat running into green, corner to corner, so both read at a glance.
// Why: the move Lunte wants most shows as both (docs/why.md#cool-mends)
func dotStyle(heat: Double, cool: Bool) -> AnyShapeStyle {
    guard cool else { return AnyShapeStyle(dotColor(heat)) }
    if heat < 0.35 { return AnyShapeStyle(Color.green.opacity(0.75)) }
    return AnyShapeStyle(LinearGradient(colors: [dotColor(heat), .green.opacity(0.85)], startPoint: .topLeading, endPoint: .bottomTrailing))
}

/// A message Laya is still rating: a grey dot breathing until its colour arrives. It breathes by the clock, not a
/// repeating animation, so it stops with the popover's other clocks while the panel is closed.
private struct RatingDot: View {
    let open: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        TimelineView(.animation(paused: !open || reduceMotion)) { context in
            // 1 down to 0.25 and back, 0.7 s each way, eased at both ends
            let breath = reduceMotion ? 1 : 0.625 + 0.375 * cos(context.date.timeIntervalSinceReferenceDate * .pi / 0.7)
            Circle().fill(Color.secondary.opacity(0.35)).frame(width: 12, height: 12).opacity(breath)
        }
    }
}

/// The popover's foot, in one row: how many prompts you've sent today on the left; on the right the Club, quietly, a
/// house, its name (or "Join a Club") and a dot when something happened there since you last looked, which opens its
/// window; and a gear for Lunte Settings. Until you're set up, just "Lunte Settings…".
// Why: a glance at the day, never compared or added up (docs/why.md#history-not-a-score)
private struct Footer: View {
    @ObservedObject var model: GameModel
    let updater: SPUStandardUpdaterController?
    let full: Bool
    var under = false // the list above scrolls on under its fade: a hairline over the card keeps them apart
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var lit: String?                  // the control the hover sits under
    @State private var frames: [String: CGRect] = [:] // each control's, in the footer

    static let space = "footer"
    static let control = 30.0 // the house's and the gear's hit area, and their highlight

    var body: some View {
        if full {
            let club = model.club == nil ? "Join a Club" : model.clubName ?? model.club ?? ""
            HStack(spacing: 2) {
                LatelyGlance(score: Int(model.state.lately.rounded()), open: model.popoverOpen, dayStart: Int(model.state.latelyDayStart.rounded()))
                    .padding(.trailing, 4)
                Spacer(minLength: 0) // for a card that hugs what's on it
                Button { ClubWindow.show(model) } label: {
                    Image(systemName: "house").font(.system(size: 14)).foregroundStyle(.secondary)
                        .frame(width: Self.control, height: Self.control)
                        .overlay(alignment: .topTrailing) {
                            if model.clubNews { Circle().fill(Color.accentColor).frame(width: 6, height: 6).offset(x: -7, y: 8) }
                        }
                }
                .buttonStyle(Give())
                .footerControl("club")
                .help(club)
                .accessibilityLabel(club + (model.clubNews ? ", something new" : ""))
                Button { SettingsWindow.show(model, updater) } label: {
                    Image(systemName: "gearshape").font(.system(size: 14)).foregroundStyle(.secondary).frame(width: Self.control, height: Self.control)
                }
                .buttonStyle(Give())
                .footerControl("settings")
                .help("Lunte Settings…")
                .accessibilityLabel("Lunte Settings")
            }
            .padding(.top, 4) // a little more air above the card than between the rows, with the house and the gear on it
            .overlay(alignment: .top) { if under { Divider().offset(y: -3).transition(.opacity) } } // halfway up the gap, so nothing moves
            .coordinateSpace(name: Self.space)
            .onPreferenceChange(FooterFrames.self) { frames = $0 }
            // One highlight for the house and the gear that glides from one to the other instead of blinking off in the
            // gap between them, so you see where a click lands. Only controls get it.
            .onContinuousHover(coordinateSpace: .named(Self.space)) { phase in
                guard case .active(let p) = phase else { lit = nil; return }
                let near = frames.first { $0.value.insetBy(dx: -4, dy: -4).contains(p) }?.key
                if near != lit { lit = near } // every move of the pointer, so only when it changes
            }
            .background(alignment: .topLeading) {
                if let f = lit.flatMap({ frames[$0] }) {
                    Capsule().fill(Color.primary.opacity(0.1)).frame(width: f.width, height: f.height).offset(x: f.minX, y: f.minY)
                        .transition(.opacity)
                }
            }
            .animation(reduceMotion ? nil : .spring(duration: 0.08), value: lit)
        } else {
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
}

/// Where each of the footer's controls sits, for the hover to find.
private struct FooterFrames: PreferenceKey {
    static let defaultValue: [String: CGRect] = [:]
    static func reduce(value: inout [String: CGRect], nextValue: () -> [String: CGRect]) { value.merge(nextValue()) { $1 } }
}

private extension View {
    func footerControl(_ id: String) -> some View {
        background(GeometryReader { g in Color.clear.preference(key: FooterFrames.self, value: [id: g.frame(in: .named(Footer.space))]) })
    }
}

/// A control that gives under the click, on a fast spring; with Reduce Motion it dims instead.
private struct Give: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.94 : 1)
            .opacity(configuration.isPressed && reduceMotion ? 0.6 : 1)
            .animation(.spring(duration: 0.08), value: configuration.isPressed)
    }
}

extension Color {
    /// Lighter than the panel in both appearances: white in light, a lift of white in dark.
    static let latelyRaised = Color(nsColor: NSColor(name: nil) {
        $0.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? NSColor(white: 1, alpha: 0.095) : .white
    })
    /// Green and red that read as text on the popover in both appearances: the system's own in dark, deeper in light,
    /// where the system's green is 2:1 on the panel.
    static let readableGreen = Color(nsColor: NSColor(name: nil) {
        $0.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? .systemGreen : NSColor(srgbRed: 0.12, green: 0.48, blue: 0.2, alpha: 1)
    })
    static let readableRed = Color(nsColor: NSColor(name: nil) {
        $0.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? .systemRed : NSColor(srgbRed: 0.8, green: 0, blue: 0.07, alpha: 1)
    })
}

/// The fuse lately, at the foot of the popover as a glance and not a control: a card of its own where a divider was,
/// as wide as the row leaves beside the house and the gear, inside the popover's margins. On it, you and your agent as
/// two rings and the step's word, green at the top two steps and red at the bottom three. Each time the popover opens,
/// the rings drift from where they were when you last looked (`LatelyMotion`), so little you almost don't notice.
/// Anywhere on the card, they part ways and fade, and the number comes up between them; after a short rest (0.3 s) a
/// card says what it is, and no more: the steps are found by playing. Each session's row says what it did to it.
// Why: feedback about what you did, and the one number that sums it up (docs/why.md#fuse-lately)
struct LatelyGlance: View {
    let score: Int
    let open: Bool
    var film: (from: Double, at: Double)? // the lab's: draw the move from that score, this many seconds in
    var pointed = false                   // the lab's: draw it as under the pointer
    var dayStart: Int?                    // where today began: under the pointer, the number counts from there to now
    var script: Double?                   // the lab's: this many seconds into a hover, on at 0 and off at `held`
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var motion: LatelyMotion?
    @State private var start = Date.distantPast
    @State private var hovered = false
    @State private var frame = CGRect.zero
    @State private var rest: Task<Void, Never>?
    @State private var pointedAt = Date.distantPast
    @State private var counting = false

    /// Green at the top two steps, red at the bottom three, none between.
    static func colour(_ step: Int) -> Color? { step <= 1 ? .readableGreen : step >= 4 ? .readableRed : nil }

    // ponytail: today only; this week's, this month's and all of it wait until today's earns its place (hq's score-over-time note)
    /// The number under the pointer, `t` seconds after it came: where today began, held long enough to read, then rolled
    /// to now on a spring of the rings' family, a touch past and back.
    static let roll = Spring(duration: 0.7, bounce: 0.12)
    static func count(from: Int, to: Int, at t: Double) -> Double {
        t <= 0.35 ? Double(from) : Double(from) + roll.value(target: Double(to - from), time: t - 0.35)
    }

    /// The word's count: it winds back to where today began while the number rolls in, then counts on with it.
    static func rewound(from: Int, to: Int, at t: Double) -> Double {
        t < 0.35 ? Double(to) + Double(from - to) * min(1, flip.value(target: 1, time: t)) : count(from: from, to: to, at: t)
    }

    // Why: sideways means the score moved and nothing else, so the switch to the number goes up and down, the way the
    // number's own wheels turn (docs/why.md#fuse-lately)
    /// Under the pointer the rings roll up out of their window and the number rolls in under them, on the rings' spring;
    /// off it, back. Leaving, the rings come back where today began and move to now, so today's move shows twice.
    static let flip = Spring(duration: 0.35, bounce: 0.1)
    static let travel = 22.0  // how far they roll, a little more than the window
    static let held = 1.8     // the lab's hover, in seconds
    static let backIn = 0.25  // the rings' move waits this long for them to roll back in
    static func swap(at t: Double) -> Double {
        t < 0 ? 0 : t < held ? min(1, flip.value(target: 1, time: t)) : max(0, 1 - flip.value(target: 1, time: t - held))
    }

    var body: some View {
        let colour = Self.colour(Game.latelyStep(score)), part = hovered || pointed
        let swap = script.map(Self.swap) ?? (part ? 1 : 0) // 0 the rings, 1 the number
        let today = Double(dayStart ?? score)
        HStack(spacing: 8) {
            Color.clear.frame(width: LatelyRings.slot, height: 26)
                .overlay {
                    TimelineView(.animation(paused: motion == nil)) { context in
                        let apart = script.map { t in t < Self.held ? LatelyMotion(from: 0, to: Double(score)).still
                                                                    : LatelyMotion(from: today, to: Double(score)).apart(at: t - Self.held - Self.backIn) }
                            ?? film.map { LatelyMotion(from: $0.from, to: Double(score)).apart(at: $0.at) }
                            ?? motion?.apart(at: context.date.timeIntervalSince(start))
                            ?? LatelyMotion(from: 0, to: open ? Double(score) : today).still // closed, it waits where today began
                        LatelyRings(you: apart.you, agent: apart.agent, ink: colour ?? .primary)
                    }
                    .frame(width: LatelyRings.room, height: 26)
                    .offset(y: -swap * Self.travel)
                    .opacity(1 - swap)
                }
                .overlay {
                    TimelineView(.animation(paused: !counting)) { context in
                        let from = reduceMotion ? score : dayStart ?? score
                        RollingNumber(value: Self.count(from: from, to: score, at: script ?? context.date.timeIntervalSince(pointedAt)),
                                      places: String(max(from, score)).count)
                    }
                    .offset(y: (1 - swap) * Self.travel)
                    .opacity(swap)
                }
                .mask { // a window they roll through, soft at the top and the bottom
                    LinearGradient(stops: [.init(color: .clear, location: 0), .init(color: .black, location: 0.2),
                                           .init(color: .black, location: 0.8), .init(color: .clear, location: 1)],
                                   startPoint: .top, endPoint: .bottom)
                        .frame(width: LatelyRings.room + 8)
                }
            let from = reduceMotion ? score : dayStart ?? score
            let pointing = script.map { $0 < Self.held } ?? part
            ZStack(alignment: .leading) {
                // Under the pointer it's as wide as the wider of today's two words, so it never shrinks out from under
                // you and the hover never flickers; out here, where the hover's spring moves the capsule's width.
                if pointing { Text(Game.latelyWord(from)).hidden() }
                Text(Game.latelyWord(score)).hidden()
                TimelineView(.animation(paused: !counting)) { context in
                    let counted = pointing ? Self.rewound(from: from, to: score, at: script ?? context.date.timeIntervalSince(pointedAt)) : Double(score)
                    RollingWord(value: counted, dim: 0.45 * swap) // fades with the switch, where a change of style would snap
                }
            }
        }
        .padding(.leading, 15).padding(.trailing, 16).frame(height: 42)
        // A capsule that hugs what's on it, lifted a little off the panel: the only raised thing in the popover, and
        // the only surface with words on it, so the eye lands there without a colour of its own.
        .background {
            Capsule().fill(Color.latelyRaised).overlay(Capsule().strokeBorder(Color.primary.opacity(0.06), lineWidth: 0.5))
                .shadow(color: .black.opacity(0.055), radius: 2.5, y: 1)
        }
        .contentShape(Capsule()) // its hover is the whole capsule, not just the rings and the word
        .animation(reduceMotion ? .easeOut(duration: 0.12) : .spring(duration: 0.35, bounce: 0.1), value: part)
        .animation(reduceMotion ? nil : .spring(duration: 0.4, bounce: 0.15), value: score) // a new word, a new width
        .onAppear { if open { move(from: Double(dayStart ?? score)) } }
        .onChange(of: open) { _, open in
            if open { return move(from: Double(dayStart ?? score)) } // today's move, each time you look
            // Closed with the pointer still on it: nothing's left pointing, counting or floating when it opens again.
            rest?.cancel()
            (hovered, counting, motion) = (false, false, nil)
            HoverCard.hide()
        }
        .onChange(of: score) { old, _ in if open { move(from: Double(old)) } } // a session moved it while you look
        .task(id: pointedAt) { // the count is over in a second and a bit
            try? await Task.sleep(for: .seconds(1.4))
            if !Task.isCancelled { counting = false }
        }
        .task(id: start) { // still again once the move is over
            try? await Task.sleep(for: .seconds(LatelyMotion.length + max(0, start.timeIntervalSinceNow)))
            if !Task.isCancelled { motion = nil }
        }
        .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { frame = $0 }
        .onHover { on in
            hovered = on
            rest?.cancel()
            if on { pointedAt = .now; counting = true }
            guard on else { // the rings come back where today began, and move to now
                move(from: Double(dayStart ?? score), after: Self.backIn)
                return HoverCard.hide()
            }
            rest = Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(300))
                guard !Task.isCancelled else { return }
                HoverCard.show(LatelyAbout(today: dayStart.map { score - $0 }), above: frame)
            }
        }
        .onDisappear { rest?.cancel(); hovered = false; HoverCard.hide() }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(LatelyAbout.title): \(score), \(Game.latelyWord(score))")
        .accessibilityHint(LatelyAbout.line)
    }

    private func move(from: Double, after delay: Double = 0) {
        guard !reduceMotion, film == nil, script == nil else { return }
        motion = LatelyMotion(from: from, to: Double(score))
        start = .now + delay
    }
}

/// The step's word as a wheel, each in its own step's colour: as the count crosses into another step, the old word
/// rolls out and the new one in, the way the digits do. A pure function of `value`.
struct RollingWord: View {
    let value: Double
    var dim = 0.0 // how far a word with no colour of its own fades, under the pointer

    var body: some View {
        let (lower, upper, part) = Self.roll(value)
        ZStack(alignment: .leading) {
            word(lower).offset(y: -part * RollingNumber.line)
            if part > 0 { word(upper).offset(y: (1 - part) * RollingNumber.line) }
        }
        .frame(height: RollingNumber.line)
        .mask { // soft only while it turns, so a still word keeps its whole height
            if part > 0 {
                LinearGradient(stops: [.init(color: .clear, location: 0), .init(color: .black, location: 0.2),
                                       .init(color: .black, location: 0.8), .init(color: .clear, location: 1)],
                               startPoint: .top, endPoint: .bottom)
            } else {
                Color.black
            }
        }
    }

    func word(_ score: Int) -> some View {
        let colour = LatelyGlance.colour(Game.latelyStep(score))
        return Text(Game.latelyWord(score)).foregroundStyle(colour ?? .primary).opacity(colour == nil ? 1 - dim : 1)
    }

    /// The scores either side of the step `value` is crossing, and how far across it is: within one point below a
    /// step's lowest score it turns, and at that score it's whole.
    static func roll(_ v: Double) -> (Int, Int, Double) {
        for t in Game.latelySteps.dropLast().map(\.from) where v > Double(t - 1) && v < Double(t) {
            return (t - 1, t, v - Double(t - 1))
        }
        let s = Int(v.rounded())
        return (s, s, 0)
    }
}

/// A number whose digits roll like an odometer's: each wheel turns as the one to its right goes past 9, so a value
/// between two whole numbers sits partway and nothing blurs. A pure function of `value`, so a render draws any moment.
struct RollingNumber: View {
    let value: Double
    let places: Int
    var font = Font.system(size: 15, weight: .semibold)

    static let line = 18.0 // a wheel's window: one digit tall

    var body: some View {
        HStack(spacing: 0) {
            ForEach((0..<places).reversed(), id: \.self) { wheel($0) }
        }
        .font(font).monospacedDigit()
        .accessibilityLabel("\(Int(value.rounded()))")
    }

    /// How far a wheel has turned: the ones all the way, each one left of it only through the last unit before it
    /// rolls over.
    func turned(_ place: Int) -> Double {
        let v = max(0, value), unit = pow(10, Double(place))
        guard place > 0 else { return v }
        return (v / unit).rounded(.down) + max(0, v.truncatingRemainder(dividingBy: unit) - (unit - 1))
    }

    func wheel(_ place: Int) -> some View {
        let at = turned(place), whole = at.rounded(.down), part = at - whole
        let leading = place > 0 && place == places - 1 // its 0 is blank, as a number's would be
        let digit = { (n: Double) in leading && n == 0 ? "" : String(Int(n) % 10) }
        return ZStack {
            Text("0").hidden() // as wide as a digit, blank or not
            Text(digit(whole)).offset(y: -part * Self.line)        // going up as the next comes in under it
            Text(digit(whole + 1)).offset(y: (1 - part) * Self.line)
        }
        .frame(height: Self.line)
        .mask(LinearGradient(stops: [.init(color: .clear, location: 0), .init(color: .black, location: 0.2),
                                     .init(color: .black, location: 0.8), .init(color: .clear, location: 1)],
                             startPoint: .top, endPoint: .bottom))
    }
}

// Why: character from physics; two rings that follow each other read as two of you, not a meter (docs/why.md#fuse-lately)
/// How the two rings move once the popover opens, as a pure function of time, so a render draws any moment as the
/// screen does. From how far apart you both were when today began to how far apart you are now, closer when it went up
/// and further when it went down: you first, your agent a beat behind and a touch past before it settles. Unchanged,
/// it doesn't move, so a move means today did something, and it's worth pointing at.
struct LatelyMotion {
    let from: Double
    let to: Double

    static let length = 2.0 // seconds, and still after
    static let you = Spring(duration: 0.8, bounce: 0.3)    // elastic: past the mark and back, so the way it went shows
    static let agent = Spring(duration: 1.0, bounce: 0.4)

    /// How far apart you are at a score, 0 as one to 1 with nothing in line: the square root of its distance from 100,
    /// so they move most where the score spends its days, between 70 and 90.
    static func apart(_ score: Double) -> Double { (1 - min(max(score, 0), 100) / 100).squareRoot() }

    var still: (you: Double, agent: Double) { (Self.apart(to), Self.apart(to)) }

    /// How far apart each ring is, `t` seconds after the popover opened.
    func apart(at t: Double) -> (you: Double, agent: Double) {
        let a0 = Self.apart(from), a1 = Self.apart(to)
        guard abs(a1 - a0) >= 0.02 else { return (a1, a1) } // today hasn't moved it
        // A small move still goes visibly past before it settles: the less it moved, the more it's helped, so a point's
        // change reads as up or down.
        let way = a1 > a0 ? 1.0 : -1.0, kick = max(0, 0.1 - abs(a1 - a0) * 0.5)
        func along(_ spring: Spring, after delay: Double) -> Double {
            guard t > delay else { return a0 }
            let u = t - delay - 0.2 // as it gets there
            return a0 + spring.value(target: a1 - a0, time: t - delay) + (u > 0 ? way * kick * sin(.pi * u / 0.6) * exp(-u / 0.35) : 0)
        }
        return (along(Self.you, after: 0.15), along(Self.agent, after: 0.3))
    }
}

/// You and your agent as two rings, centred on the middle of their frame, each as far apart as `you` and `agent` say.
/// They shrink a little as they part, so a low score never outweighs a high one: one 17-point ring as one, two of 13
/// with a touch of air between them at the bottom, never wider than `slot`. Where they overlap is filled, more strongly
/// the more they share.
struct LatelyRings: View {
    var you: Double
    var agent: Double
    let ink: Color

    static let ring = 17.0   // as one: big enough to read from the corner of your eye
    static let stroke = 1.6  // the session fuse's line, near enough
    static let slot = 28.0   // as wide as the two ever get
    static let room = slot + 8 // and room for your agent to go a touch past

    /// A ring's size, and how far its centre sits from the middle, at how far apart it is.
    static func ring(_ apart: Double) -> (size: Double, off: Double) {
        let size = ring * (1 - 0.25 * apart * apart)
        return (size, 0.575 * size * apart)
    }

    var body: some View {
        Canvas { context, size in
            let mid = CGPoint(x: size.width / 2, y: size.height / 2)
            let (y, x) = (Self.ring(you), Self.ring(agent))
            let a = Path(ellipseIn: CGRect(x: mid.x - y.off - y.size / 2, y: mid.y - y.size / 2, width: y.size, height: y.size))
            let b = Path(ellipseIn: CGRect(x: mid.x + x.off - x.size / 2, y: mid.y - x.size / 2, width: x.size, height: x.size))
            // stronger the more they share: faint where they just touch, half-filled as one
            let shared = max(0, 1 - (y.off + x.off) / ((y.size + x.size) / 2))
            context.fill(a.intersection(b), with: .color(ink.opacity(0.08 + 0.42 * shared)))
            context.stroke(a, with: .color(ink), lineWidth: Self.stroke)
            context.stroke(b, with: .color(ink), lineWidth: Self.stroke)
        }
    }
}

/// What the fuse lately is, in two lines, for the card that floats over the rows while you rest on it.
struct LatelyAbout: View {
    static let title = "Alignment score"
    static let what = "A vibe check between you and your agent."
    static let how = "Every session moves it a little, so it changes over days."
    static let line = what + " " + how
    var today: Int? // how far it's moved since today began, as the number under the pointer counts it

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(Self.title).fontWeight(.semibold)
            if let today, today != 0 { // today's move says how it changes better than a sentence does
                Text(Self.what).font(.system(size: 12)).foregroundStyle(.secondary)
                HStack(spacing: 4) {
                    Text("Today").foregroundStyle(.secondary)
                    LatelyMove(move: Double(today))
                }
                .font(.system(size: 12))
            } else {
                Text(Self.line).font(.system(size: 12)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.horizontal, 12).padding(.vertical, 10).frame(width: 220, alignment: .leading)
    }
}

/// A card that floats over the popover while you rest on something. It's a window of its own, a child of the
/// popover's: the session rows scroll in an AppKit view, which draws over anything SwiftUI puts on top of it.
@MainActor
enum HoverCard {
    private static var card: NSPanel?

    /// `rect` is what's rested on, in the key window's SwiftUI space, which covers the whole popover; the card sits 10
    /// points above it, leading edges lined up, and fades in.
    static func show(_ content: some View, above rect: CGRect) {
        hide()
        guard let parent = NSApp.keyWindow else { return }
        let host = NSHostingView(rootView: content)
        let size = host.fittingSize
        let material = NSVisualEffectView(frame: CGRect(origin: .zero, size: size))
        material.material = .popover
        material.state = .active
        material.maskImage = MenuPanel.rounded(10)
        host.frame = material.bounds
        material.addSubview(host)
        let panel = NSPanel(contentRect: CGRect(x: parent.frame.minX + rect.minX, y: parent.frame.maxY - rect.minY + 10, width: size.width, height: size.height),
                            styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.ignoresMouseEvents = true
        panel.animationBehavior = .none
        panel.appearance = parent.effectiveAppearance
        panel.contentView = material
        panel.alphaValue = 0
        parent.addChildWindow(panel, ordered: .above)
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.1
            panel.animator().alphaValue = 1
        }
        card = panel
    }

    static func hide() {
        guard let panel = card else { return }
        card = nil
        panel.parent?.removeChildWindow(panel)
        panel.orderOut(nil)
    }
}

/// What a session did to the fuse lately, as its row shows it: `+3` in green, `−3` in grey, nothing at 0. The green is
/// the glance's, readable as text.
struct LatelyMove: View {
    let move: Double

    var body: some View {
        let n = Int(move.rounded())
        if n != 0 { Text(n > 0 ? "+\(n)" : "−\(-n)").monospacedDigit().foregroundStyle(n > 0 ? Color.readableGreen : Color.secondary) }
    }
}

/// A quiet line while Lunte can't read your cool, so nothing you send grows your fuse back, with the way to fix it: setup
/// again, whose last step tunes heat and cool together. While that runs it says how far, and once there's a cool model
/// it's gone.
// Why: cool grows the fuse back, and can't without a cool model (docs/why.md#cool-grows)
private struct CoolNudge: View {
    @ObservedObject var model: GameModel

    var body: some View {
        HStack(spacing: 6) {
            if let line = model.fuseLine {
                Text(line).foregroundStyle(model.fuse.isFailed ? .red : .secondary).lineLimit(2)
            } else {
                Text("Lunte can't read your cool yet").foregroundStyle(.secondary).lineLimit(1)
                Spacer(minLength: 6)
                Button("Redo setup", action: model.retune).buttonStyle(.link)
            }
        }
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

/// When a message came: "Just now", "6 min ago", and from an hour on its time, "14:05".
func ago(_ ts: Double, now: Double) -> String {
    let m = Int((now - ts) / 60)
    return m < 1 ? "Just now" : m < 60 ? "\(m) min ago" : clock(ts)
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
