import AppKit
import SwiftUI

/// The Club's own window, opened from its row in the popover, so the popover stays about you.
@MainActor
enum ClubWindow {
    private static var window: NSWindow?

    static func show(_ model: GameModel) {
        if window == nil {
            let w = NSWindow(contentViewController: NSHostingController(rootView: ClubView(model: model)))
            w.styleMask = [.titled, .closable, .fullSizeContentView]
            w.titlebarAppearsTransparent = true
            w.titleVisibility = .hidden // the name is the page's own heading
            w.isReleasedWhenClosed = false
            w.center()
            window = w
        }
        window?.title = model.clubName ?? "Club"
        model.clubSeen()
        NSApp.activate()
        window?.makeKeyAndOrderFront(nil)
    }
}

/// The Club as a place, read like a group chat: who's in it, then what happened, by day, the newest at the bottom. Each
/// Boom shows when it went off, its owner's line as their bubble, if they wrote one, and the Club's reactions, which
/// you can add to on anyone else's. Booms never carry a name; only a
/// line its owner chose to write does. Without a Club: what a Club is, and a way in.
// Why: the rewards come from people, and nobody is ever outed (docs/why.md#feedback-not-reward, docs/why.md#silent-pings)
struct ClubView: View {
    @ObservedObject var model: GameModel

    var body: some View {
        Group {
            if let club = model.club { place(club) } else { welcome }
        }
        .frame(width: 360, height: 500)
        .onChange(of: model.clubFeed) { model.clubSeen() } // open and looking: nothing new to flag
    }

    private func place(_ club: String) -> some View {
        let items = ClubItem.all(model.clubFeed, mine: model.isMine)
        return VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 10) {
                Text(model.clubName ?? club).font(.title2.weight(.semibold))
                People(names: model.members)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 20).padding(.top, 34).padding(.bottom, 14) // clear of the window's buttons
            Divider()
            ScrollView {
                LazyVStack(spacing: 14) {
                    ForEach(days(items), id: \.title) { day in
                        Text(day.title).font(.caption.weight(.semibold)).foregroundStyle(.secondary).padding(.top, 4)
                        ForEach(day.items) { item in
                            if item.boom == nil {
                                Text("\(item.who ?? "Someone") joined · \(clock(item.ts))").font(.caption).foregroundStyle(.secondary)
                            } else {
                                BoomBubble(model: model, item: item)
                            }
                        }
                    }
                }
                .padding(16)
            }
            .defaultScrollAnchor(.bottom) // like a chat: the newest at the bottom, where it opens
            .overlay {
                if items.isEmpty {
                    Text("Quiet so far. When someone in \(model.clubName ?? "your Club") blows up, it lands here, and you can throw them something.")
                        .multilineTextAlignment(.center).foregroundStyle(.secondary).padding(32)
                }
            }
            Divider()
            HStack(spacing: 8) {
                Text("Invite code").foregroundStyle(.secondary)
                Text(club).font(.body.monospaced()).textSelection(.enabled)
                Button("Copy") { copyToClipboard(club) }.controlSize(.small)
                Spacer()
                Menu {
                    Button("Leave Club", role: .destructive, action: model.leaveClub)
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
                .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
                .accessibilityLabel("More")
            }
            .padding(.horizontal, 20).padding(.vertical, 12)
        }
    }

    private var welcome: some View {
        VStack(spacing: 14) {
            Image(systemName: "house.fill").font(.system(size: 34)).foregroundStyle(.secondary)
            Text("Play with your people").font(.title2.weight(.semibold))
            Text("When one of you blows up, the rest of your Club hears about it, never who. Laugh at your agents together.")
                .multilineTextAlignment(.center).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            HStack {
                Button("Join a Club…", action: model.joinClub).buttonStyle(.borderedProminent)
                Button("Create a Club…", action: model.createClub)
            }
            .controlSize(.large)
            .padding(.top, 4)
        }
        .padding(32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    /// Oldest day first, titled "Today", "Yesterday" or the weekday and date.
    private func days(_ items: [ClubItem]) -> [(title: String, items: [ClubItem])] {
        let calendar = Calendar.current
        return Dictionary(grouping: items) { calendar.startOfDay(for: Date(timeIntervalSince1970: $0.ts)) }
            .sorted { $0.key < $1.key }
            .map { day, items in
                let title = calendar.isDateInToday(day) ? "Today" : calendar.isDateInYesterday(day) ? "Yesterday"
                    : day.formatted(.dateTime.weekday(.wide).day().month())
                return (title, items.sorted { $0.ts < $1.ts })
            }
    }
}

/// One thing that happened in the Club: a Boom, with its owner's line and the reactions on it, or someone joining.
struct ClubItem: Identifiable {
    var id: String
    var ts: Double
    var boom: String? // nil for a join
    var yours = false
    var who: String? // who joined, or who wrote the Boom's line
    var line: String?
    var reactions: [String: Int] = [:]

    /// The feed as items: each Boom gathers its line and its reactions, wherever they came in the feed.
    static func all(_ feed: [ClubEvent], mine: (ClubEvent) -> Bool) -> [ClubItem] {
        var booms: [String: ClubItem] = [:], joins: [ClubItem] = []
        for e in feed {
            switch e.type {
            case "join": joins.append(ClubItem(id: "join\(e.seq)", ts: e.ts, who: e.from))
            case "boom": if let b = e.boom { booms[b] = booms[b] ?? ClubItem(id: b, ts: e.ts, boom: b, yours: mine(e)) }
            case "why": if let b = e.boom { booms[b]?.line = e.text; booms[b]?.who = e.from }
            case "react": if let b = e.boom, let emoji = e.emoji { booms[b]?.reactions[emoji, default: 0] += 1 }
            default: break
            }
        }
        return Array(booms.values) + joins
    }
}

/// A Boom, the way a group chat shows it: when it went off, in the middle; then its owner's line as their bubble, if
/// they wrote one, with their face and name (yours on the right, in blue); then the reactions under it. On anyone
/// else's, a reaction adds yours.
private struct BoomBubble: View {
    @ObservedObject var model: GameModel
    let item: ClubItem

    var body: some View {
        VStack(spacing: 6) {
            Text("💥 \(item.yours ? "Your Boom" : "Boom") · \(clock(item.ts))").font(.caption).foregroundStyle(.secondary)
            if let line = item.line {
                VStack(alignment: item.yours ? .trailing : .leading, spacing: 3) {
                    if !item.yours { Text(item.who ?? "Someone").font(.caption).foregroundStyle(.secondary).padding(.leading, 46) }
                    HStack(alignment: .bottom, spacing: 8) {
                        if !item.yours { Face(name: item.who ?? "?", size: 26) }
                        Text(line)
                            .fixedSize(horizontal: false, vertical: true)
                            .padding(.horizontal, 12).padding(.vertical, 7)
                            .foregroundStyle(item.yours ? Color.white : .primary)
                            .background(item.yours ? Color.accentColor : Color.primary.opacity(0.08), in: bubble)
                    }
                    reactions.padding(.leading, item.yours ? 0 : 34)
                }
                .frame(maxWidth: .infinity, alignment: item.yours ? .trailing : .leading)
                .padding(item.yours ? .leading : .trailing, 48)
            } else {
                reactions
            }
        }
    }

    /// Round, with the corner by the speaker pulled in, like a chat bubble's tail.
    private var bubble: UnevenRoundedRectangle {
        UnevenRoundedRectangle(topLeadingRadius: 16, bottomLeadingRadius: item.yours ? 16 : 4,
                               bottomTrailingRadius: item.yours ? 4 : 16, topTrailingRadius: 16, style: .continuous)
    }

    /// The three to throw first, then any other emoji someone used; on yours, only the ones you got.
    private var reactions: some View {
        HStack(spacing: 4) {
            let emoji = Notifier.reacts + item.reactions.keys.filter { !Notifier.reacts.contains($0) }.sorted()
            ForEach(emoji, id: \.self) { e in
                let n = item.reactions[e] ?? 0
                if !item.yours || n > 0 {
                    Button { if let b = item.boom { model.react(b, e) } } label: {
                        Text(n > 0 ? "\(e) \(n)" : e).font(.callout).monospacedDigit()
                            .padding(.horizontal, 7).padding(.vertical, 2)
                            .background(Capsule().fill(n > 0 ? Color.accentColor.opacity(0.14) : Color.primary.opacity(0.05)))
                    }
                    .buttonStyle(.plain)
                    .disabled(item.yours)
                    .accessibilityLabel(n > 0 ? "\(e), \(n)" : "Throw \(e)")
                }
            }
        }
    }
}

/// Someone's initial in a circle, in a colour that's always the same for the same name.
private struct Face: View {
    let name: String
    var size: CGFloat = 28
    static let colors: [Color] = [.orange, .pink, .purple, .teal, .blue, .green, .indigo, .mint]

    var body: some View {
        Text(String(name.prefix(1)).uppercased()).font(.system(size: size * 0.43, weight: .semibold)).foregroundStyle(.white)
            .frame(width: size, height: size)
            .background(Self.colors[name.unicodeScalars.reduce(0) { $0 + Int($1.value) } % Self.colors.count], in: Circle())
            .help(name)
    }
}

/// Who's in the Club, as faces.
private struct People: View {
    let names: [String]

    var body: some View {
        HStack(spacing: -6) {
            ForEach(names.prefix(8), id: \.self) { name in
                Face(name: name).overlay(Circle().strokeBorder(Color(nsColor: .windowBackgroundColor), lineWidth: 2))
            }
            Text(names.count == 1 ? "1 person" : "\(names.count) people").foregroundStyle(.secondary).padding(.leading, 14)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(names.joined(separator: ", "))
    }
}
