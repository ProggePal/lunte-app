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
                StickView(state: model.state)
                Text(model.sentence).font(.callout)
            }
            if model.connected { VibeStrip(events: model.lastTen, boomTimes: Set(model.state.booms.map(\.ts))) }
            if let club = model.club {
                VStack(alignment: .leading, spacing: 4) {
                    Label("Club \(club)", systemImage: "person.2").font(.caption).foregroundStyle(.secondary)
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
private struct StickView: View {
    let state: GameState

    var body: some View {
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
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(state.pieces) of \(state.fuse) pieces of fuse left")
    }
}

/// Your last 10 messages as dots: grey normal, orange told off, red lost it, 💥 where it blew.
private struct VibeStrip: View {
    let events: [Event]
    let boomTimes: Set<Double>

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Your last 10 messages").font(.caption).foregroundStyle(.secondary)
            HStack(spacing: 6) {
                let pad = 10 - events.count
                ForEach(0..<10, id: \.self) { i in
                    if i < pad {
                        Circle().strokeBorder(Color.secondary.opacity(0.3)).frame(width: 14, height: 14)
                    } else {
                        let e = events[i - pad]
                        Group {
                            if boomTimes.contains(e.ts) { Text("💥").font(.system(size: 12)) }
                            else { Circle().fill(color(e.burn)) }
                        }
                        .frame(width: 14, height: 14)
                        .help(clock(e.ts) + " · " + word(e.burn))
                    }
                }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(events.map { word($0.burn) }.joined(separator: ", "))
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

private struct BoomCard: View {
    @ObservedObject var model: GameModel
    let boom: Boom
    @State private var why = ""
    @State private var error: String?
    @State private var sending = false

    var body: some View {
        VStack(spacing: 8) {
            Text("💥").font(.system(size: 40))
            Text("Boom at \(clock(boom.ts))").font(.headline)
            Text("Lit by: " + Game.litByText(boom)).font(.caption).foregroundStyle(.secondary).multilineTextAlignment(.center)
            if let reacted = model.reactionSummary(boom.id) {
                Text(reacted).font(.callout)
                    .padding(.horizontal, 8).padding(.vertical, 3)
                    .background(Color.secondary.opacity(0.12), in: RoundedRectangle(cornerRadius: 6))
            }
            if model.canSayWhy(boom.id) {
                HStack {
                    TextField("What lit it?", text: $why).textFieldStyle(.roundedBorder).onSubmit(send)
                    Button("Say why", action: send).disabled(why.isEmpty || sending)
                }
                if let error { Text(error).font(.caption).foregroundStyle(.red) }
            } else if model.whySent.contains(boom.id) {
                Text("Your Club knows why.").font(.caption).foregroundStyle(.secondary)
            }
            Text("Fresh stick after a 30-minute break.").font(.caption).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }

    private func send() {
        guard !why.isEmpty, !sending else { return }
        sending = true
        Task {
            error = await model.sayWhy(boom.id, why)
            sending = false
            if error == nil { why = "" }
        }
    }
}

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
                Divider()
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

func clock(_ ts: Double) -> String {
    Date(timeIntervalSince1970: ts).formatted(date: .omitted, time: .shortened)
}
