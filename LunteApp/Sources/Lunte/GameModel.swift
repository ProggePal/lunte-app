import AppKit
import CryptoKit
import LunteCore

private let defaults = UserDefaults.standard

/// The stick, the log watcher, Boom announcing and the Club. Everything runs on the main actor.
@MainActor
final class GameModel: ObservableObject {
    @Published private(set) var state = Game.replay([], now: 0)
    @Published private(set) var club = Relay.club
    @Published private(set) var recent: [ClubEvent] = defaults.data(forKey: "Recent").flatMap { try? JSONDecoder().decode([ClubEvent].self, from: $0) } ?? []
    /// Boom ids this Mac posted to the Club.
    @Published private(set) var mine = Set(defaults.stringArray(forKey: "Mine") ?? [])
    /// True once the onboarding phrase has reached the log: the hook is wired up.
    @Published private(set) var connected = defaults.bool(forKey: "Connected")
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

    var statusLine: String {
        if !connected { return "Not connected yet: open a new Claude Code chat and type: this is a test 3 2 1 pow" }
        if state.boomed, let boom = state.booms.last { return "💥 lit by " + Game.litByText(boom) }
        return "Fuse \(state.fuse) · \(state.pieces) left"
    }

    /// Your latest Boom that went to the Club, for "Say why…".
    var whyBoom: Boom? { club == nil ? nil : state.booms.last { mine.contains($0.id) } }

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
        onboard(events.filter { $0.burn == .test }, now: now)
        let fresh = state.booms.filter { !announced.contains($0.id) }
        guard !fresh.isEmpty else { return }
        for boom in fresh {
            announced.insert(boom.id)
            guard now - boom.ts < 600 else { continue } // older than 10 minutes: announced silently
            if soundOn { playBoom() }
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
        Alerts.tell("💥 We're connected!", "Lunte hears you. Ready.")
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
        guard let name = Alerts.ask("Create a Club", "Your name, as your Club will see it.", fields: ["Your name"])?.first,
              !name.isEmpty else { return }
        Task {
            do {
                let code = try await Relay.createClub()
                try await join(code, name)
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
        mine = []
        secrets = [:]
        defaults.removeObject(forKey: "Mine")
        defaults.removeObject(forKey: "Secrets")
        recent = []
        lastSeq = 0
        saveClub()
    }

    func sayWhy() {
        guard let boom = whyBoom, let secret = secrets[boom.id],
              let text = Alerts.ask("Say why", "What lit your Boom at \(clock(boom.ts))? Your Club sees it with your name. Up to 140 characters.",
                                    fields: ["Why"])?.first, !text.isEmpty else { return }
        Task {
            do {
                try await Relay.post(["type": "why", "boom": boom.id, "text": String(text.prefix(140)), "secret": secret])
                await poll(notify: true)
            } catch {
                Alerts.tell("Couldn't send that", error.localizedDescription)
            }
        }
    }

    private func join(_ code: String, _ name: String) async throws {
        try await Relay.join(code, name: name)
        club = code
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
        case "why" where !isMine(e): // only a Boom's owner can say why, so a why on your own Boom is yours
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

    private func clock(_ ts: Double) -> String {
        Date(timeIntervalSince1970: ts).formatted(date: .omitted, time: .shortened)
    }
}

func copyToClipboard(_ s: String) {
    NSPasteboard.general.clearContents()
    NSPasteboard.general.setString(s, forType: .string)
}
