import AppKit
import CryptoKit
import LunteCore

private let defaults = UserDefaults.standard

/// The stick, the log watcher, Boom announcing and the Club. Everything runs on the main actor.
@MainActor
final class GameModel: ObservableObject {
    @Published private(set) var state = Game.replay([], now: 0)
    @Published private(set) var club = Relay.club
    @Published private(set) var clubName = Relay.clubName
    @Published private(set) var recent: [ClubEvent] = defaults.data(forKey: "Recent").flatMap { try? JSONDecoder().decode([ClubEvent].self, from: $0) } ?? []
    /// Boom ids this Mac posted to the Club.
    @Published private(set) var mine = Set(defaults.stringArray(forKey: "Mine") ?? [])
    /// True once the onboarding phrase has reached the log: the hook is wired up.
    @Published private(set) var connected = defaults.bool(forKey: "Connected")
    /// Your prompts from the last hour (no onboarding test), for the vibe strip.
    @Published private(set) var lastHour: [Event] = []
    /// When you last sent a prompt: a break counts from here.
    @Published private(set) var lastActivity: Double?
    private var promptCache: [Double: String] = [:]
    /// Seconds shaved off the current break by tapping the countdown, and which break (last prompt) they belong to.
    @Published private(set) var shaved: Double = 0
    private var shaveKey: Double?
    private var breakEnd: Task<Void, Never>?
    @Published private(set) var pluginInstalled = defaults.bool(forKey: "PluginInstalled")
    @Published private(set) var connecting = false
    @Published private(set) var connectError: String?
    /// Boom id → reactions on it, like "🧯 Ola".
    @Published private(set) var reactions = defaults.dictionary(forKey: "Reactions") as? [String: [String]] ?? [:]
    @Published private(set) var whySent = Set(defaults.stringArray(forKey: "WhySent") ?? [])
    @Published var soundOn = defaults.object(forKey: "SoundOn") as? Bool ?? true {
        didSet { defaults.set(soundOn, forKey: "SoundOn") }
    }
    private var announced = Set(defaults.stringArray(forKey: "Announced") ?? [])
    private var secrets = defaults.dictionary(forKey: "Secrets") as? [String: String] ?? [:] // ponytail: UserDefaults, not the Keychain
    private var lastSeq = defaults.integer(forKey: "LastSeq")

    private let log = EventLog.defaultURL
    private var dirSource: DispatchSourceFileSystemObject?
    private var fileSource: DispatchSourceFileSystemObject?
    private var watchedInode: Int?
    private var debounce: Task<Void, Never>?
    private var polling = false
    private var sound: NSSound?

    init() {
        Notifier.setUp()
        linkHook()
        let dir = log.deletingLastPathComponent()
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        dirSource = watch(dir.path, [.write]) // fires when events.jsonl is created, replaced or removed
        reload()
        Task { while true { try? await Task.sleep(for: .seconds(60)); reload() } } // closes a Sitting on time with no new events
        Task { while true { await poll(notify: true); try? await Task.sleep(for: .seconds(30)) } }
    }

    // MARK: The menu

    /// One plain sentence about the stick. No numbers to decode.
    var sentence: String {
        if state.pieces <= 2 { return "One outburst and it blows." }
        if state.pieces == state.fuse { return "Fresh stick. Telling it off burns one piece, losing it burns two." }
        return "\(state.pieces) pieces left. Losing it burns two."
    }

    static let justifyLimit = 40 // short and honest

    func canJustify(_ boom: String) -> Bool { club != nil && mine.contains(boom) && !whySent.contains(boom) }

    /// "🧯 2 · 😂 1 from Ola", or nil when nobody reacted yet.
    func reactionSummary(_ boom: String) -> String? {
        guard let list = reactions[boom], !list.isEmpty else { return nil }
        let emoji = list.map { String($0.prefix { $0 != " " }) }, names = Set(list.map { String($0.drop { $0 != " " }.dropFirst()) })
        let counts = Dictionary(emoji.map { ($0, 1) }, uniquingKeysWith: +).sorted { $0.value > $1.value }
        return counts.map { "\($0.key) \($0.value)" }.joined(separator: " · ") + " from " + names.sorted().joined(separator: ", ")
    }


    private func isMine(_ e: ClubEvent) -> Bool { e.boom.map(mine.contains) ?? false }

    func describe(_ e: ClubEvent) -> String {
        let who = e.from ?? "Someone"
        switch e.type {
        case "boom": return "💥 Boom at \(clock(e.ts))" + (isMine(e) ? " (yours)" : "")
        case "join": return "👋 \(who) joined"
        case "react": return "\(e.emoji ?? "") from \(who)"
        case "why": return "\(who): \(e.text ?? "")"
        default: return e.type
        }
    }

    /// Seconds until a fresh stick if you step away now (a 10-minute break), or nil with no activity yet.
    func breakLeft(at now: Date) -> Double? {
        guard state.sittingOpen, let last = lastActivity else { return nil }
        return max(0, last + Game.sittingGap - shaved - now.timeIntervalSince1970)
    }

    /// Easter egg: once you've justified, each tap on the 💥 shaves 2 s off the break, at most a minute. No UI.
    func hurry() {
        guard state.sittingOpen, let last = lastActivity, shaved < 60 else { return }
        shaveKey = last
        shaved += 2
        scheduleBreakEnd()
    }

    /// Ends the break on time: a plain reload closes a full 10-minute break, and a hurried one needs a rest event.
    private func scheduleBreakEnd() {
        breakEnd?.cancel()
        guard let left = breakLeft(at: .now) else { return }
        let key = lastActivity
        breakEnd = Task {
            try? await Task.sleep(for: .seconds(left + 0.5))
            guard !Task.isCancelled, lastActivity == key else { return }
            if shaved > 0 {
                try? EventLog.append(Event(ts: Date().timeIntervalSince1970, burn: .rest), to: log) // the watcher reloads
            } else {
                reload()
            }
        }
    }

    /// The prompt behind an event, read from Claude Code's transcript on demand and kept in memory only.
    func promptText(_ e: Event) async -> String? {
        if let cached = promptCache[e.ts] { return cached }
        let text = await Task.detached { Transcript.prompt(sid: e.sid, ts: e.ts) }.value
        if let text { promptCache[e.ts] = text }
        return text
    }

    func testBoom() {
        playBoom()
        BoomFlash.show()
    }

    func connect() {
        guard !translocated(), !connecting else { return }
        connecting = true
        connectError = nil
        Task {
            let result = await installPlugin()
            connecting = false
            if result.ok {
                pluginInstalled = true
                defaults.set(true, forKey: "PluginInstalled")
            } else {
                connectError = String(result.output.suffix(300))
            }
            if connected { Alerts.tell(result.ok ? "Connected to Claude Code" : "Couldn't connect to Claude Code", connectError ?? "") }
        }
    }

    func playBoom() {
        guard let url = Bundle.main.url(forResource: "boom", withExtension: "wav") else { return }
        sound = NSSound(contentsOf: url, byReference: true) // kept so it isn't freed mid-boom
        sound?.play()
    }

    // MARK: Watching the log

    private func watch(_ path: String, _ mask: DispatchSource.FileSystemEvent) -> DispatchSourceFileSystemObject? {
        let fd = open(path, O_EVTONLY)
        guard fd >= 0 else { return nil }
        let source = DispatchSource.makeFileSystemObjectSource(fileDescriptor: fd, eventMask: mask, queue: .main)
        source.setEventHandler { [weak self] in MainActor.assumeIsolated { self?.changed() } }
        source.setCancelHandler { close(fd) }
        source.resume()
        return source
    }

    /// (Re)opens events.jsonl when it appears or is replaced by a new file.
    private func rewatchLog() {
        let inode = (try? FileManager.default.attributesOfItem(atPath: log.path))?[.systemFileNumber] as? Int
        guard inode != watchedInode else { return }
        fileSource?.cancel()
        fileSource = inode == nil ? nil : watch(log.path, [.write, .extend, .delete, .rename])
        watchedInode = fileSource == nil ? nil : inode
    }

    private func changed() {
        debounce?.cancel()
        debounce = Task {
            try? await Task.sleep(for: .seconds(1))
            if !Task.isCancelled { reload() }
        }
    }

    func reload() {
        rewatchLog()
        let now = Date().timeIntervalSince1970
        let events = EventLog.read(log)
        state = Game.replay(events, now: now)
        lastHour = Array(events.filter { ($0.burn != .test && $0.burn != .rest) && now - $0.ts < 3600 }.suffix(240)) // ponytail: capped for a very busy hour
        lastActivity = events.last { $0.burn != .rest }?.ts
        if shaveKey != lastActivity { shaveKey = nil; shaved = 0 } // a new prompt restarts the break
        onboard(events.filter { $0.burn == .test }, now: now)
        scheduleBreakEnd()
        let fresh = state.booms.filter { !announced.contains($0.id) }
        guard !fresh.isEmpty else { return }
        for boom in fresh {
            announced.insert(boom.id)
            guard now - boom.ts < 600 else { continue } // older than 10 minutes: announced silently
            if soundOn { playBoom() }
            BoomFlash.show()
            if club != nil { post(boom) }
        }
        defaults.set(Array(announced), forKey: "Announced")
    }

    /// The first Boom is the onboarding: "this is a test 3 2 1 pow" proves the hook reaches the app. Never posted to the Club.
    private func onboard(_ tests: [Event], now: Double) {
        let fresh = tests.filter { !announced.contains(String(Int($0.ts * 1000))) }
        guard !fresh.isEmpty else { return }
        fresh.forEach { announced.insert(String(Int($0.ts * 1000))) }
        connected = true
        defaults.set(true, forKey: "Connected")
        defaults.set(Array(announced), forKey: "Announced")
        guard fresh.contains(where: { now - $0.ts < 600 }) else { return }
        playBoom()
        BoomFlash.show("CONNECTED")
    }

    private func post(_ boom: Boom) {
        let secret = (0..<32).map { _ in String(format: "%02x", UInt8.random(in: 0...255)) }.joined()
        let proof = SHA256.hash(data: Data(secret.utf8)).map { String(format: "%02x", $0) }.joined()
        Task {
            // ponytail: no retry; a Boom the relay never got just can't take a why
            guard (try? await Relay.post(["type": "boom", "boom": boom.id, "ts": boom.ts, "proof": proof])) != nil else { return }
            secrets[boom.id] = secret
            mine.insert(boom.id)
            defaults.set(secrets, forKey: "Secrets")
            defaults.set(Array(mine), forKey: "Mine")
        }
    }

    // MARK: The Club

    func createClub() {
        guard let f = Alerts.ask("Create a Club", "Name your Club, and say who you are in it.", fields: ["Club name", "Your name"]),
              !f[0].isEmpty, !f[1].isEmpty else { return }
        Task {
            do {
                let code = try await Relay.createClub(named: f[0])
                try await join(code, f[1])
                copyToClipboard(code)
                Alerts.tell("Your Club is \(code)", "The code is on your clipboard. Send it to the people you want in.")
            } catch {
                Alerts.tell("Couldn't create a Club", error.localizedDescription)
            }
        }
    }

    func joinClub() {
        guard let f = Alerts.ask("Join a Club", "Ask a member for the six-letter code.", fields: ["Club code", "Your name"]),
              !f[0].isEmpty, !f[1].isEmpty else { return }
        Task {
            do {
                let code = f[0].uppercased()
                try await join(code, f[1])
                copyToClipboard(code)
                Alerts.tell("You're in Club \(code)", "When someone in it blows up, you'll hear about it.")
            } catch {
                Alerts.tell("Couldn't join", error.localizedDescription)
            }
        }
    }

    func leaveClub() {
        Relay.leave()
        club = nil
        clubName = nil
        mine = []
        secrets = [:]
        reactions = [:]
        whySent = []
        for key in ["Mine", "Secrets", "Reactions", "WhySent"] { defaults.removeObject(forKey: key) }
        recent = []
        lastSeq = 0
        saveClub()
    }

    /// Justify a Boom (the relay's "why"). Returns an error message to show, or nil when the Club got it.
    func justify(_ boom: String, _ text: String) async -> String? {
        guard let secret = secrets[boom], !text.isEmpty else { return "Nothing to send." }
        do {
            try await Relay.post(["type": "why", "boom": boom, "text": String(text.prefix(Self.justifyLimit)), "secret": secret])
            whySent.insert(boom)
            defaults.set(Array(whySent), forKey: "WhySent")
            await poll(notify: true)
            return nil
        } catch {
            return error.localizedDescription
        }
    }

    private func join(_ code: String, _ name: String) async throws {
        try await Relay.join(code, name: name)
        club = code
        clubName = Relay.clubName
        recent = []
        lastSeq = 0
        await poll(notify: false) // catch up on the Club's history without a burst of notifications
    }

    private func poll(notify: Bool) async {
        guard club != nil, !polling else { return }
        polling = true
        defer { polling = false }
        do {
            while true {
                let page = try await Relay.events(after: lastSeq)
                for e in page where e.seq > lastSeq {
                    if e.type == "react", isMine(e), let boom = e.boom {
                        reactions[boom, default: []].append("\(e.emoji ?? "") \(e.from ?? "Someone")")
                        defaults.set(reactions, forKey: "Reactions")
                    }
                    if notify && Date().timeIntervalSince1970 - e.ts < 600 { self.notify(about: e) } // catch-up goes to the feed quietly
                    lastSeq = e.seq
                }
                recent = Array((recent + page).suffix(5))
                if page.count < 100 { break }
            }
        } catch {} // ponytail: offline or relay down; the next poll tries again
        saveClub()
    }

    private func notify(about e: ClubEvent) {
        let who = e.from ?? "Someone"
        switch e.type {
        case "boom" where !isMine(e):
            Notifier.post("💥 Boom in your Club", "Someone lost it. Throw them something.", boom: e.boom)
        case "react" where isMine(e):
            Notifier.post("\(e.emoji ?? "") from \(who)", "On your Boom")
        case "why" where !isMine(e): // only a Boom's owner can justify it, so a why on your own Boom is yours
            Notifier.post("\(who): \(e.text ?? "")")
        case "join":
            Notifier.post("👋 \(who) joined your Club")
        default:
            break
        }
    }

    private func saveClub() {
        defaults.set(lastSeq, forKey: "LastSeq")
        defaults.set(try? JSONEncoder().encode(recent), forKey: "Recent")
    }

}

func copyToClipboard(_ s: String) {
    NSPasteboard.general.clearContents()
    NSPasteboard.general.setString(s, forType: .string)
}
