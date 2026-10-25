import AppKit
import LunteCore
import Sparkle
import SwiftUI

/// The whole UI. Onboarding until you've owned your first (test) Boom; then the stick or the Boom on top, one text slot
/// for the message you're looking at, the session's vibe, the session as dots, the Club, a gear.
struct PopoverView: View {
    @ObservedObject var model: GameModel
    let updater: SPUStandardUpdaterController?
    @State private var hovered: Double? // the hovered message's ts, so the slot always shows its latest rating
    @State private var vibeHovered = false

    var body: some View {
        let boom = model.state.boomed ? model.state.booms.last : nil
        let firstBoom = model.connected && !model.onboarded
        VStack(alignment: .leading, spacing: 12) {
            if model.detector == .notInstalled && !model.detectorLater {
                DetectorLanding(model: model) // a new Mac starts here
            } else if !model.connected {
                OnboardingView(model: model)
            } else if firstBoom {
                FirstBoomCard(model: model)
            } else {
                if let boom {
                    BoomHeader(model: model, boom: boom)
                } else {
                    StickBar(left: model.state.left)
                    if model.heldTogether { HeldLine() }
                }
                MessageSlot(model: model, event: hovered.flatMap { ts in model.session.first { $0.ts == ts } } ?? fallback(boom), boom: boom, vibe: vibeHovered ? model.vibe : nil)
                if let boom { JustifyRow(model: model, boom: boom) }
                if model.vibesOn { VibeLine(vibe: model.vibe, isNew: model.vibeIsNew).onHover { vibeHovered = $0 && model.vibe != nil } }
                Strip(model: model, hovered: $hovered)
                Text(model.session.count == 1 ? "1 message from Claude Code" : "\(model.session.count) messages from Claude Code")
                    .font(.caption2).foregroundStyle(.tertiary)
                ForEach(model.clubFeed.suffix(2).reversed(), id: \.seq) { Text(model.describe($0)).font(.caption).foregroundStyle(.secondary) }
            }
            Divider()
            Footer(model: model, updater: updater)
        }
        .padding(16)
        .frame(width: 290)
        .background { if boom != nil || firstBoom { BoomTint() } } // snaps on with the Boom, no fade
    }

    /// With nothing hovered: the message that set off the Boom, else the hottest one still burning, else your latest.
    private func fallback(_ boom: Boom?) -> Event? {
        if let boom { return boom.litBy.last }
        let now = Date().timeIntervalSince1970
        return model.state.currentBurns.max { $0.heat(at: now) < $1.heat(at: now) } ?? model.session.last
    }
}

/// A red wash from the top, for the Boom.
private struct BoomTint: View {
    var body: some View {
        LinearGradient(colors: [Color.red.opacity(0.17), Color.red.opacity(0.05)], startPoint: .top, endPoint: UnitPoint(x: 0.5, y: 0.6))
    }
}

/// The first screen on a new Mac: what the Heat Detector is, that your messages stay here, and one button.
private struct DetectorLanding: View {
    @ObservedObject var model: GameModel

    var body: some View {
        VStack(spacing: 10) {
            Text("🧨").font(.system(size: 40))
            Text("Install the Heat Detector").font(.headline)
            Text("Lunte reads the heat in your messages with a small model that runs on this Mac, so your messages stay on this computer.")
                .font(.callout).foregroundStyle(.secondary).multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            Button(action: model.installDetector) {
                Text("Download · " + ByteCountFormatter.string(fromByteCount: HeatDetector.totalBytes, countStyle: .file))
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent).controlSize(.large)
            Button("Not now", action: model.detectorNotNow).buttonStyle(.borderless).font(.caption).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 6)
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

private struct OnboardingView: View {
    @ObservedObject var model: GameModel
    static let phrase = "3 2 1 pow"
    @State private var copied = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Light your first fuse").font(.headline)
                Text("Lunte hears how you talk to your AI. Lose your temper, and it blows.")
                    .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
            // Each step has a to-do and a done title, written to read well together as you go down the list.
            Step(done: model.pluginInstalled || model.connected, todo: "Listen for new messages", doneTitle: "Listening for new messages") {
                if !model.pluginInstalled {
                    Button(model.connecting ? "Connecting…" : "Connect", action: model.connect).disabled(model.connecting)
                }
                if let error = model.connectError {
                    Text(error).font(.caption).foregroundStyle(.red).textSelection(.enabled)
                }
            }
            Step(done: model.fuse.isTuned, todo: "Activate the heat detector", doneTitle: "Heat detector on") {
                if !model.fuse.isTuned {
                    Button(copied ? "Copied. Paste it in Claude Code" : "Copy prompt") { model.copySetupPrompt(); copied = true }
                }
                if let line = model.fuseLine {
                    Text(line).font(.caption).foregroundStyle(model.fuse.isFailed ? Color.red : Color.secondary)
                }
            }
            // Your AI's last line in the chat tells you the test phrase; it shows here too, as a backup, once you're tuned.
            Step(done: false, todo: "Turn the heat up", doneTitle: "Heat turned up") {
                if model.fuse.isTuned {
                    HStack(spacing: 6) {
                        Text("Type").font(.caption).foregroundStyle(.secondary)
                        Text(Self.phrase).font(.system(.callout, design: .monospaced)).textSelection(.enabled)
                            .padding(.horizontal, 6).padding(.vertical, 3)
                            .background(Color.secondary.opacity(0.12), in: RoundedRectangle(cornerRadius: 4))
                        Button { copyToClipboard(Self.phrase) } label: { Image(systemName: "doc.on.doc") }
                            .buttonStyle(.borderless).help("Copy")
                    }
                }
            }
        }
    }
}

private struct Step<Content: View>: View {
    let done: Bool
    let todo: String
    let doneTitle: String
    @ViewBuilder let content: Content

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: done ? "checkmark.circle.fill" : "circle")
                .foregroundStyle(done ? Color.green : Color.secondary)
            VStack(alignment: .leading, spacing: 6) {
                Text(done ? doneTitle : todo).font(.callout).foregroundStyle(done ? .secondary : .primary)
                content
            }
        }
    }
}

/// Onboarding's last two steps: the test Boom, owned with "it was a test", then a fresh stick in 10 seconds.
private struct FirstBoomCard: View {
    @ObservedObject var model: GameModel
    @State private var line = "it was a test"

    var body: some View {
        VStack(spacing: 8) {
            Text("💥").font(.system(size: 44))
            if let owned = model.ownedTest {
                Text("Your first Boom").font(.headline)
                Text("“\(owned.line)”").font(.system(.callout, design: .serif))
                TimelineView(.periodic(from: .now, by: 1)) { context in
                    Text("Fresh stick in " + countdown(max(0, owned.freshAt.timeIntervalSince(context.date))))
                        .font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                }
            } else {
                Text("Your first Boom").font(.headline)
                Text("“\(OnboardingView.phrase)”").font(.system(.callout, design: .serif)).italic()
                Text("Everyone heard that. Comment:").font(.caption).foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading).padding(.top, 6)
                HStack {
                    TextField("", text: $line).textFieldStyle(.roundedBorder).onSubmit(own)
                    Button("Comment", action: own).disabled(trimmed.isEmpty)
                }
            }
        }
        .frame(maxWidth: .infinity)
    }

    private var trimmed: String { String(line.trimmingCharacters(in: .whitespacesAndNewlines).prefix(GameModel.justifyLimit)) }
    private func own() { if !trimmed.isEmpty { model.ownTest(trimmed) } }
}

/// The fuse in three pieces: what's left is filled, what burned is faint. Orange past half, red near the end, ✨ on the
/// last third. The last third, by the 🧨, always has a faint red edge, so you see the danger before you're in it.
private struct StickBar: View {
    let left: Double

    var body: some View {
        HStack(spacing: 8) {
            Text("🧨").font(.title2)
            HStack(spacing: 4) {
                ForEach(0..<3, id: \.self) { i in
                    RoundedRectangle(cornerRadius: 3)
                        .fill(Double(i) < piecesLeft(left) ? fuseColor(left) : Color.secondary.opacity(0.15))
                        .frame(height: 10)
                        // Why: a close call needs the danger in sight (docs/why.md#close-call)
                        .overlay { if i == 0 { RoundedRectangle(cornerRadius: 3).strokeBorder(Color.red.opacity(0.5), lineWidth: 1) } }
                }
            }
            if left <= 1.0 / 3 { Text("✨") }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(Int((left * 100).rounded()))% of the fuse left")
    }
}

/// Just after a close call, for your eyes only: no sound, no notification.
// Why: competence, and relief right after the act (docs/why.md#close-call)
private struct HeldLine: View {
    var body: some View {
        Text("Held it together").font(.callout.weight(.medium)).foregroundStyle(.green)
            .help("The fuse got into its last third and you cooled off without a Boom: a close call.")
    }
}

/// After a Boom: its tier (💥 Boom, 💥💥 Chain reaction, ☢️ Meltdown), when it last went off, and one timer to the
/// fresh stick. Once you've justified, tapping the emoji is the hurry easter egg.
// Why: venting feeds anger, so a tier changes the name and emoji, never the volume (docs/why.md#tiers-flavour-not-volume)
private struct BoomHeader: View {
    @ObservedObject var model: GameModel
    let boom: Boom

    var body: some View {
        let level = tier(boom.tier), quiet = Int(Game.sittingGap / 60)
        VStack(spacing: 2) {
            Button { if !model.canJustify(boom.id) { model.hurry() } } label: { Text(level.emoji).font(.system(size: 44)) }
                .buttonStyle(.plain)
            TimelineView(.periodic(from: .now, by: 1)) { context in
                VStack(spacing: 2) {
                    (Text(level.name + " ").font(.headline) + Text(Date(timeIntervalSince1970: boom.escalations.last ?? boom.ts).formatted(.relative(presentation: .named))).foregroundStyle(.secondary))
                    if let left = model.freshLeft(at: context.date) {
                        // Why: a fresh start, when the session closes (docs/why.md#fresh-start)
                        Text(left > 0 ? "Fresh stick after \(quiet) quiet minutes · \(countdown(left))" : "Fresh stick any second")
                            .font(.caption.monospacedDigit()).foregroundStyle(.secondary).lineLimit(1)
                            .help("Every prompt starts the \(quiet) minutes over. Then the session closes, and the next one starts on a fresh stick.")
                    }
                }
            }
        }
        .frame(maxWidth: .infinity)
    }
}

/// The one place text lives: the hovered message (or the one that set off the Boom), or the vibe's story.
/// Its height is fixed, so hovering never makes the popover jump.
private struct MessageSlot: View {
    @ObservedObject var model: GameModel
    let event: Event?
    let boom: Boom?
    let vibe: Vibe?
    @State private var texts: [Double: String] = [:]
    @State private var missing: Set<Double> = []

    var body: some View {
        let center = boom != nil && vibe == nil
        VStack(alignment: center ? .center : .leading, spacing: 2) {
            if let vibe {
                (Text(vibe.label + ". ") + Text(vibe.story).foregroundStyle(.secondary)).font(.system(.callout, design: .serif))
            } else if let e = event {
                let now = Date().timeIntervalSince1970, heat = e.heat(at: now), text = texts[e.ts]
                let setItOff = boom?.ts == e.ts, cooled = heat >= 0.15 && !model.state.currentBurns.contains { $0.ts == e.ts }
                let rating = e.awaitingRating(at: now), cool = isCool(e)
                // A neutral message gets no word: heatWord's "cool" would read as the cool score.
                let word = rating ? "rating…" : heat < 0.15 ? (cool ? "cool" : nil) : Game.heatWord(heat) + (cool ? " and cool" : "")
                Text(([clock(e.ts)] + [word].compactMap { $0 } + (cooled ? ["cooled off"] : []) + (setItOff ? ["set it off"] : [])).joined(separator: " · "))
                    .font(.caption).foregroundStyle(.secondary)
                Group {
                    if let text { Text("“\(text)”") } else { Text(missing.contains(e.ts) ? "Couldn’t find this message in Claude’s history." : "…") }
                }
                .font(setItOff ? .system(.callout, design: .serif).italic() : .callout)
                .foregroundStyle(heat < 0.15 && !setItOff ? .secondary : .primary)
                .lineLimit(2).truncationMode(.tail)
                if model.showRatings {
                    HStack(alignment: .top, spacing: 4) {
                        if rating { ProgressView().controlSize(.mini) }
                        Text(debug(e, heat: heat, text: text, rating: rating)).font(.caption2.monospacedDigit()).foregroundStyle(.secondary).lineLimit(3)
                    }
                }
            }
        }
        .multilineTextAlignment(center ? .center : .leading)
        .frame(maxWidth: .infinity, alignment: center ? .center : .leading)
        .frame(height: model.showRatings ? 92 : 52, alignment: .top)
        .task(id: event?.ts) {
            guard let e = event, texts[e.ts] == nil, !missing.contains(e.ts) else { return }
            if let found = await model.promptText(e) { texts[e.ts] = found } else { missing.insert(e.ts) }
        }
    }

    /// The numbers behind a dot: the model's heat (or the word list's), what it burns, the mood, and what the word list saw.
    private func debug(_ e: Event, heat: Double, text: String?, rating: Bool) -> String {
        let words = text.map(Classifier.signals).flatMap { $0.isEmpty ? nil : $0.joined(separator: ", ") } ?? e.burn.rawValue
        if rating { return "Laya is rating it…\nwords: " + words }
        let source = e.heat != nil ? "Laya" : e.rated == true ? "word list, Laya didn't answer" : "word list"
        return "heat \(Int((heat * 100).rounded()))% (\(source)) · burns \(Int((heat * heat * 100).rounded()))%"
            + (e.mood.map { " · \($0)" } ?? "") + "\nwords: " + words
    }
}

/// Owning a Boom, open from the start: one short line, or stay a mystery. The Club's reactions sit beside it.
private struct JustifyRow: View {
    @ObservedObject var model: GameModel
    let boom: Boom
    @State private var why = ""
    @State private var error: String?
    @State private var sending = false

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            if model.canJustify(boom.id) {
                HStack {
                    TextField("it deleted my migrations again", text: $why).textFieldStyle(.roundedBorder).onSubmit(send)
                        .onChange(of: why) { _, new in if new.count > GameModel.justifyLimit { why = String(new.prefix(GameModel.justifyLimit)) } }
                    Button("Comment", action: send).disabled(why.isEmpty || sending)
                }
            } else if let line = model.justifications[boom.id] {
                Text("“\(line)”").font(.callout).frame(maxWidth: .infinity)
            }
            HStack {
                if model.canJustify(boom.id) { Text("or stay a mystery") }
                Spacer()
                if let reacted = model.reactionSummary(boom.id) { Text(reacted) }
            }
            .font(.caption).foregroundStyle(.secondary)
            if let error { Text(error).font(.caption).foregroundStyle(.red) }
        }
    }

    private func send() {
        guard !why.isEmpty, !sending else { return }
        sending = true
        Task {
            error = await model.justify(boom.id, why)
            sending = false
            why = "" // it's saved either way; error only says the Club missed it
        }
    }
}

/// The session's vibe, with ✨ the first time it ever shows up. Until there's enough to go on: "Reading the room…".
private struct VibeLine: View {
    let vibe: Vibe?
    let isNew: Bool

    var body: some View {
        Group {
            if let vibe {
                (Text(vibe.emoji + " " + vibe.label) + Text(isNew ? "  ✨ new" : "").foregroundStyle(.orange).font(.caption))
                    .font(.callout.weight(.medium))
            } else {
                Text("Reading the room…").font(.callout).foregroundStyle(.secondary)
                    .help("Send \(Vibe.minimumMessages) messages within half an hour to get the session's vibe.")
            }
        }
        .padding(.horizontal, 4).padding(.vertical, 1)
        .contentShape(Rectangle())
    }
}

/// The open session as dots that wrap, oldest first: grey neutral, orange heated, red boiling, a soft green ember for
/// cool, and the tier's emoji where it blew. Past four rows the oldest fold into a heat line, so a long session never
/// grows the popover. The dots touch (no dead space between them), so moving across them never drops the hover.
// Why: persistence; the whole session stays readable (docs/why.md#whole-session-dots)
private struct Strip: View {
    @ObservedObject var model: GameModel
    @Binding var hovered: Double?
    private let cell: CGFloat = 18
    static let dots = 56 // four rows of 14

    var body: some View {
        let session = model.session, now = Date().timeIntervalSince1970
        if session.isEmpty {
            Text("Nothing yet. Every message you send Claude shows up here.").font(.caption).foregroundStyle(.secondary)
        } else {
            let marks = blasts()
            VStack(alignment: .leading, spacing: 4) {
                if session.count > Self.dots {
                    let folded = Array(session.dropLast(Self.dots))
                    HStack(spacing: 6) {
                        Text("\(folded.count) earlier").font(.caption2.monospacedDigit()).foregroundStyle(.tertiary)
                        HeatLine(events: folded).frame(height: 12)
                    }
                    .help("The session's first \(folded.count) messages, folded into a heat line")
                }
                LazyVGrid(columns: [GridItem(.adaptive(minimum: cell, maximum: cell), spacing: 0)], alignment: .leading, spacing: 0) {
                    ForEach(session.suffix(Self.dots), id: \.ts) { e in
                        Group {
                            if let mark = marks[e.ts] { Text(mark).font(.system(size: 12)) }
                            else if e.awaitingRating(at: now) { RatingDot() }
                            else { Dot(heat: e.heat(at: now), cool: isCool(e)) }
                        }
                        .frame(width: cell, height: cell)
                        .background(hovered == e.ts ? Color.secondary.opacity(0.18) : .clear, in: RoundedRectangle(cornerRadius: 4))
                        .contentShape(Rectangle())
                        .onHover { if $0 { hovered = e.ts } } // leaving the whole grid clears it, not leaving one dot
                    }
                }
                .onHover { if !$0 { hovered = nil } }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("\(session.count) messages this session, \(session.filter { $0.heat(at: now) >= 0.35 }.count) of them heated, \(session.filter(isCool).count) cool")
        }
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

/// Sound on the left, the Club in the middle (a house and its name), everything else behind the gear.
private struct Footer: View {
    @ObservedObject var model: GameModel
    let updater: SPUStandardUpdaterController?

    var body: some View {
        HStack {
            Button { model.soundOn.toggle() } label: { Image(systemName: model.soundOn ? "speaker.wave.2" : "speaker.slash") }
                .buttonStyle(.borderless).help(model.soundOn ? "Sound on" : "Sound off")
            Spacer()
            if model.detector != .ready {
                DetectorStatus(model: model)
            } else {
            Menu {
                if let club = model.club {
                    Button("Copy Club code \(club)") { copyToClipboard(club) }
                    Button("Leave Club", action: model.leaveClub)
                } else {
                    Button("Create a Club…", action: model.createClub)
                    Button("Join a Club…", action: model.joinClub)
                }
            } label: {
                Label(model.club == nil ? "No Club" : (model.clubName ?? model.club ?? ""), systemImage: "house")
                    .labelStyle(.titleAndIcon).font(.callout)
            }
            .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
            }
            Spacer()
            Menu {
                // Testing your Boom, connecting and tuning all live in onboarding, so the gear only starts or skips it.
                if model.connected && model.onboarded {
                    Button("Replay onboarding", action: model.replayOnboarding)
                } else {
                    Button("Skip onboarding", action: model.skipOnboarding)
                }
                Toggle("Vibes", isOn: $model.vibesOn)
                Toggle("Show model ratings", isOn: $model.showRatings)
                Button("Submit a prompt…", action: model.submitPrompt)
                Button("Check for updates…") { updater?.checkForUpdates(nil) }.disabled(updater == nil)
                Divider()
                Button("Quit Lunte") { NSApp.terminate(nil) }
            } label: {
                Image(systemName: "gearshape")
            }
            .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
        }
    }
}

/// Grey when calm, orange when heated (telling it off), red when boiling (losing it).
func dotColor(_ heat: Double) -> Color { heat >= 0.85 ? .red : heat >= 0.35 ? .orange : Color.secondary.opacity(0.35) }

/// Talking to your agent like a best bud: your AI's 1 of 3 or more.
func isCool(_ e: Event) -> Bool { (e.cool ?? 0) >= Game.coolPrompt }

/// A Boom tier's emoji and name, by `Boom.tier`: 💥 Boom, 💥💥 Chain reaction, ☢️ Meltdown.
func tier(_ n: Int) -> (emoji: String, name: String) { Game.tiers[min(max(n, 1), Game.tiers.count) - 1] }

func fuseColor(_ left: Double) -> Color { left <= 0.2 ? .red : left <= 0.5 ? .orange : Color.primary.opacity(0.7) }

/// How many of the three pieces are still lit: any part of a third keeps it lit.
func piecesLeft(_ left: Double) -> Double { (left * 3 - 1e-9).rounded(.up) }

/// The menu bar icon: 🧨 and the fuse as three tiny pieces, orange past half and red near the end; 🧨✨ while a Boom's
/// fuse burns; 💥 BOOM after.
@MainActor
func menuBarImage(_ state: GameState, connected: Bool, fusing: Bool, blown: Bool) -> NSImage {
    // ponytail: follows the system appearance at render time; re-renders on the next state change after a switch
    let dark = NSApp?.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
    let view = HStack(spacing: 2) {
        let boomed = (state.boomed || blown) && !fusing
        Text(boomed ? "💥" : "🧨").font(.system(size: 13))
        if !connected {
            Text("?").font(.system(size: 11, weight: .bold))
        } else if fusing {
            Text("✨").font(.system(size: 11))
        } else if boomed {
            Text("BOOM").font(.system(size: 10, weight: .heavy)).foregroundStyle(.red)
        } else {
            ForEach(0..<3, id: \.self) { i in
                RoundedRectangle(cornerRadius: 1)
                    .fill(Double(i) < piecesLeft(state.left) ? (state.left <= 0.5 ? fuseColor(state.left) : .primary) : Color.primary.opacity(0.2))
                    .frame(width: 4, height: 9)
            }
        }
    }
    .padding(.horizontal, 1)
    .environment(\.colorScheme, dark ? .dark : .light)
    let renderer = ImageRenderer(content: view)
    renderer.scale = NSScreen.main?.backingScaleFactor ?? 2
    return renderer.nsImage ?? NSImage()
}

func clock(_ ts: Double) -> String {
    Date(timeIntervalSince1970: ts).formatted(date: .omitted, time: .shortened)
}

/// 523 seconds → "8:43".
func countdown(_ seconds: Double) -> String {
    let s = Int(seconds.rounded(.up))
    return String(format: "%d:%02d", s / 60, s % 60)
}
