import AppKit
import LunteCore
import Sparkle
import SwiftUI

/// The whole UI: onboarding until the first Boom, then the stick (or the Boom card), the vibe strip, the Club, a gear.
struct PopoverView: View {
    @ObservedObject var model: GameModel
    let updater: SPUStandardUpdaterController?

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            if !model.connected {
                OnboardingView(model: model)
            } else if model.state.boomed, let boom = model.state.booms.last {
                BoomCard(model: model, boom: boom)
            } else {
                StickView(model: model)
                Text(model.sentence).font(.callout)
            }
            if model.connected { VibeStrip(model: model) }
            if model.club != nil, !model.recent.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(model.recent.suffix(3).reversed(), id: \.seq) { Text(model.describe($0)).font(.caption) }
                }
            }
            Divider()
            Footer(model: model, updater: updater)
        }
        .padding(16)
        .frame(width: 290)
    }
}

private struct OnboardingView: View {
    @ObservedObject var model: GameModel
    static let phrase = "this is a test 3 2 1 pow"

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Light your first fuse").font(.headline)
            Step(done: model.pluginInstalled || model.connected, title: "Connect to Claude Code") {
                if !model.pluginInstalled {
                    Button(model.connecting ? "Connecting…" : "Connect", action: model.connect).disabled(model.connecting)
                }
                if let error = model.connectError {
                    Text(error).font(.caption).foregroundStyle(.red).textSelection(.enabled)
                }
            }
            Step(done: false, title: "Open a new Claude Code chat and type") {
                HStack(spacing: 6) {
                    Text(Self.phrase).font(.system(.callout, design: .monospaced)).textSelection(.enabled)
                        .padding(.horizontal, 6).padding(.vertical, 3)
                        .background(Color.secondary.opacity(0.12), in: RoundedRectangle(cornerRadius: 4))
                    Button { copyToClipboard(Self.phrase) } label: { Image(systemName: "doc.on.doc") }
                        .buttonStyle(.borderless).help("Copy")
                }
            }
            Step(done: false, title: "Hear your first Boom") { EmptyView() }
        }
    }
}

private struct Step<Content: View>: View {
    let done: Bool
    let title: String
    @ViewBuilder let content: Content

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: done ? "checkmark.circle.fill" : "circle")
                .foregroundStyle(done ? Color.green : Color.secondary)
            VStack(alignment: .leading, spacing: 6) {
                Text(title).font(.callout).foregroundStyle(done ? .secondary : .primary)
                content
            }
        }
    }
}

/// The fuse as segments: what's left is filled, what burned is faint. Orange once one outburst would blow it.
/// Hovering shows the break countdown.
private struct StickView: View {
    @ObservedObject var model: GameModel

    var body: some View {
        let state = model.state
        TimelineView(.periodic(from: .now, by: 1)) { context in
            HStack(spacing: 8) {
                Text("🧨").font(.title2)
                HStack(spacing: 4) {
                    ForEach(0..<max(state.fuse, 1), id: \.self) { i in
                        RoundedRectangle(cornerRadius: 3)
                            .fill(i < state.pieces ? (state.pieces <= 2 ? Color.orange : Color.primary.opacity(0.7)) : Color.secondary.opacity(0.15))
                            .frame(height: 10)
                    }
                }
                if state.pieces == 1 { Text("✨") }
            }
            .contentShape(Rectangle())
            .help(model.breakLeft(at: context.date).map { "Step away \(countdown($0)) for a fresh stick" } ?? "")
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(state.pieces) of \(state.fuse) pieces of fuse left")
    }
}

/// Your last hour as dots that wrap: grey normal, orange told off, red lost it, 💥 where it blew.
/// Hovering a dot shows its time, kind, signals and the message (read from Claude's transcript, never stored).
/// The dots touch (no dead space between them) and the detail area keeps its height, so hovering never jumps.
private struct VibeStrip: View {
    @ObservedObject var model: GameModel
    @State private var hovered: Event?
    @State private var texts: [Double: String] = [:]
    @State private var missing: Set<Double> = []

    private let cell: CGFloat = 18

    var body: some View {
        let events = model.lastHour
        let boomTimes = Set(model.state.booms.map(\.ts))
        VStack(alignment: .leading, spacing: 6) {
            Text("Your last hour").font(.caption).foregroundStyle(.secondary)
            if events.isEmpty {
                Text("Nothing yet. Every message you send Claude shows up here.").font(.caption).foregroundStyle(.secondary)
            } else {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: cell, maximum: cell), spacing: 0)], alignment: .leading, spacing: 0) {
                    ForEach(events, id: \.ts) { e in
                        Group {
                            if boomTimes.contains(e.ts) { Text("💥").font(.system(size: 12)) }
                            else { Circle().fill(color(e.burn)).frame(width: 12, height: 12) }
                        }
                        .frame(width: cell, height: cell)
                        .background(shown == e ? Color.secondary.opacity(0.18) : .clear, in: RoundedRectangle(cornerRadius: 4))
                        .contentShape(Rectangle())
                        .onHover { if $0 { hovered = e } } // leaving the whole grid clears it, not leaving one dot
                    }
                }
                .onHover { if !$0 { hovered = nil } }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("\(events.count) messages in the last hour: " + events.map { word($0.burn) }.joined(separator: ", "))
                detail.frame(height: 32, alignment: .topLeading)
            }
        }
    }

    /// The hovered dot, or your latest message when nothing is hovered.
    private var shown: Event? { hovered ?? model.lastHour.last }

    @ViewBuilder private var detail: some View {
        if let e = shown {
            let text = texts[e.ts]
            VStack(alignment: .leading, spacing: 2) {
                TimelineView(.periodic(from: .now, by: 30)) { context in
                    Text(([ago(e.ts, now: context.date), word(e.burn)] + (text.map(Classifier.signals) ?? [])).joined(separator: " · "))
                        .font(.caption).foregroundStyle(.secondary).lineLimit(1)
                }
                Text(text.map { "“\($0)”" } ?? (missing.contains(e.ts) ? "Couldn’t find this message in Claude’s history." : "…"))
                    .font(.caption).lineLimit(1).truncationMode(.tail)
            }
            .task(id: e.ts) {
                guard texts[e.ts] == nil, !missing.contains(e.ts) else { return }
                if let found = await model.promptText(e) { texts[e.ts] = found } else { missing.insert(e.ts) }
            }
        }
    }

    private func color(_ burn: Burn) -> Color {
        switch burn {
        case .tell: .orange
        case .lose: .red
        default: Color.secondary.opacity(0.35)
        }
    }

    private func word(_ burn: Burn) -> String {
        switch burn {
        case .tell: "told it off"
        case .lose: "lost it"
        default: "normal"
        }
    }
}

/// After a Boom: how long ago, the message that set it off, the Club's reactions, and the break countdown.
/// Tapping the top opens Justify.
private struct BoomCard: View {
    @ObservedObject var model: GameModel
    let boom: Boom
    @State private var finalBlow: String?
    @State private var justifying = false
    @State private var why = ""
    @State private var error: String?
    @State private var sending = false

    var body: some View {
        VStack(spacing: 8) {
            Button { if model.canJustify(boom.id) { justifying.toggle() } } label: {
                VStack(spacing: 4) {
                    Text("💥").font(.system(size: 40))
                    TimelineView(.periodic(from: .now, by: 30)) { _ in
                        Text("Boom " + Date(timeIntervalSince1970: boom.ts).formatted(.relative(presentation: .named)))
                            .font(.headline)
                    }
                    if let finalBlow {
                        Text("“\(finalBlow)”").font(.caption).foregroundStyle(.secondary).lineLimit(1).truncationMode(.tail)
                    }
                    if model.canJustify(boom.id), !justifying {
                        Text("Tap to justify").font(.caption2).foregroundStyle(.secondary)
                    }
                }
                .frame(maxWidth: .infinity)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .task(id: boom.id) { if let last = boom.litBy.last { finalBlow = await model.promptText(last) } }

            if let reacted = model.reactionSummary(boom.id) {
                Text(reacted).font(.callout)
                    .padding(.horizontal, 8).padding(.vertical, 3)
                    .background(Color.secondary.opacity(0.12), in: RoundedRectangle(cornerRadius: 6))
            }
            if justifying, model.canJustify(boom.id) {
                HStack {
                    TextField("Justify yourself", text: $why).textFieldStyle(.roundedBorder).onSubmit(send)
                    Button("Justify", action: send).disabled(why.isEmpty || sending)
                }
                if let error { Text(error).font(.caption).foregroundStyle(.red) }
            } else if model.whySent.contains(boom.id) {
                Text("Justified.").font(.caption).foregroundStyle(.secondary)
            }
            HurryButton(model: model)
        }
        .frame(maxWidth: .infinity)
    }

    private func send() {
        guard !why.isEmpty, !sending else { return }
        sending = true
        Task {
            error = await model.justify(boom.id, why)
            sending = false
            if error == nil { why = ""; justifying = false }
        }
    }
}

/// The break countdown. Each tap shaves a little less: −10 s, −9 s … −1 s, then "Nice try".
private struct HurryButton: View {
    @ObservedObject var model: GameModel
    @State private var flash: String?
    @State private var taps = 0

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            Button(action: tap) {
                HStack(spacing: 6) {
                    Text(label(context.date)).font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                    if let flash {
                        Text(flash).font(.caption.bold()).foregroundStyle(.orange)
                            .transition(.move(edge: .bottom).combined(with: .opacity))
                    }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Impatient? Each tap shaves a little less.")
        }
    }

    private func label(_ now: Date) -> String {
        guard let left = model.breakLeft(at: now) else { return "" }
        return left > 0 ? "Fresh stick in \(countdown(left)) · tap to hurry" : "Fresh stick any second"
    }

    private func tap() {
        let cut = model.hurry()
        taps += 1
        let mine = taps
        withAnimation(.spring(response: 0.3)) { flash = cut > 0 ? "−\(cut)s" : "Nice try" }
        Task {
            try? await Task.sleep(for: .milliseconds(800))
            if taps == mine { withAnimation { flash = nil } } // only the latest tap clears it
        }
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
            Spacer()
            Menu {
                Button("Test your Boom", action: model.testBoom)
                Button("Connect to Claude Code", action: model.connect)
                Button("Feedback and ideas…") { NSWorkspace.shared.open(URL(string: "https://github.com/ProggePal/lunte-app/issues/new")!) }
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

/// The menu bar icon: 🧨 plus the fuse as tiny segments, orange when one outburst would blow it, 💥 BOOM after.
@MainActor
func menuBarImage(_ state: GameState, connected: Bool) -> NSImage {
    // ponytail: follows the system appearance at render time; re-renders on the next state change after a switch
    let dark = NSApp?.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
    let view = HStack(spacing: 2) {
        Text(state.boomed ? "💥" : "🧨").font(.system(size: 13))
        if !connected {
            Text("?").font(.system(size: 11, weight: .bold))
        } else if state.boomed {
            Text("BOOM").font(.system(size: 10, weight: .heavy)).foregroundStyle(.red)
        } else {
            ForEach(0..<max(state.fuse, 1), id: \.self) { i in
                RoundedRectangle(cornerRadius: 1)
                    .fill(i < state.pieces ? (state.pieces <= 2 ? Color.orange : Color.primary) : Color.primary.opacity(0.2))
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

/// "just now", "4 min ago", "2 h ago".
func ago(_ ts: Double, now: Date = .now) -> String {
    let minutes = Int((now.timeIntervalSince1970 - ts) / 60)
    return minutes < 1 ? "just now" : minutes < 60 ? "\(minutes) min ago" : "\(minutes / 60) h ago"
}

func clock(_ ts: Double) -> String {
    Date(timeIntervalSince1970: ts).formatted(date: .omitted, time: .shortened)
}

/// 523 seconds → "8:43".
func countdown(_ seconds: Double) -> String {
    let s = Int(seconds.rounded(.up))
    return String(format: "%d:%02d", s / 60, s % 60)
}
