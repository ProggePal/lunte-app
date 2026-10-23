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
    @Published private(set) var clubFeed: [ClubEvent] = defaults.data(forKey: "Recent").flatMap { try? JSONDecoder().decode([ClubEvent].self, from: $0) } ?? []
    /// Boom ids this Mac posted to the Club.
    @Published private(set) var mine = Set(defaults.stringArray(forKey: "Mine") ?? [])
    /// True once the onboarding phrase has reached the log: the hook is wired up.
    @Published private(set) var connected = defaults.bool(forKey: "Connected")
    /// True once you've owned your first (test) Boom and got a fresh stick. Already-connected Macs count as done.
    @Published private(set) var onboarded = defaults.object(forKey: "Onboarded") as? Bool ?? defaults.bool(forKey: "Connected")
    /// Onboarding: what you owned your test Boom with, and when the 10-second fresh stick lands.
    @Published private(set) var ownedTest: (line: String, freshAt: Date)?
    /// Your messages from the last 30 minutes (no onboarding test), for the timeline.
    @Published private(set) var recent: [Event] = []
    /// The fuse is burning towards a Boom that hasn't gone off yet.
    @Published private(set) var fusing = false
    /// A test Boom has blown, so the menu bar says BOOM.
    @Published private(set) var testBlown = false
    /// The vibe line, off by default while vibes are still taking shape. Off means no vibe is picked and no topic is
    /// asked; nothing about vibes runs at all.
    @Published var vibesOn = defaults.bool(forKey: "VibesOn") {
        didSet {
            defaults.set(vibesOn, forKey: "VibesOn")
            scorer?.topicsOn = vibesOn
            vibe = nil
            vibePicked = nil
            vibesFile = []
            if vibesOn { loadPersonalVibes(); reload() }
        }
    }
    /// Debug: show the model's numbers when hovering a message.
    @Published var showRatings = defaults.bool(forKey: "ShowRatings") {
        didSet { defaults.set(showRatings, forKey: "ShowRatings") }
    }
    private var scorer: Scorer?
    /// Your personal fuse: untuned, tuning, tuned (with its fit), or why it failed.
    @Published private(set) var fuse: Scorer.Status = .untuned
    private var fuseSource: DispatchSourceFileSystemObject?
    private var fuseDebounce: Task<Void, Never>?
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
    /// Your justification per Boom id, kept on this Mac. Your own words about a Boom, never a prompt.
    @Published private(set) var justifications = defaults.dictionary(forKey: "Justifications") as? [String: String] ?? [:]
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
        dirSource = watch(dir.path, [.write]) { [weak self] in self?.changed() } // events.jsonl created, replaced or removed
        // The fuse folder, where your AI saves labels.json and vibes.json (`lunte-hook setup` tells it how).
        try? FileManager.default.createDirectory(at: Fuse.dir, withIntermediateDirectories: true)
        scorer = Scorer(log: log) { [weak self] in self?.fuse = $0 }
        scorer?.topicsOn = vibesOn
        loadPersonalVibes()
        fuseSource = watch(Fuse.dir.path, [.write]) { [weak self] in
            guard let self else { return }
            fuseDebounce?.cancel()
            fuseDebounce = Task {
                try? await Task.sleep(for: .seconds(1))
                guard !Task.isCancelled else { return }
                self.scorer?.labelsChanged()
                self.loadPersonalVibes()
            }
        }
        reload()
        Task { while true { try? await Task.sleep(for: .seconds(60)); reload() } } // closes a Sitting on time with no new events
        Task { while true { await poll(notify: true); try? await Task.sleep(for: .seconds(30)) } }
    }

    // MARK: The menu

    /// For VoiceOver: the vibe, and how much stick is left.
    var sentence: String {
        let vibe = self.vibe.map { $0.label + ". " } ?? ""
        return state.boomed ? "Boom. " + vibe : vibe + "\(Int((state.left * 100).rounded()))% of the fuse left."
    }

    // MARK: The vibe

    /// This session's vibe, once you've sent 5 or more messages in 30 minutes; nil until then ("Reading the room…").
    @Published private(set) var vibe: Vibe?
    /// The first time this vibe has ever shown up. No counter, no list: vibes are found by playing.
    @Published private(set) var vibeIsNew = false
    private var personalVibes: [Vibe] = []
    private var seenVibes = Set(defaults.stringArray(forKey: "SeenVibes") ?? [])
    /// The band and newest message when the vibe was last picked.
    private var vibePicked: (band: Vibe.Band, newest: Double)?

    /// Your AI's vibes from fuse setup, if any, read again whenever the fuse folder changes. Each is then tagged with
    /// its topic by Laya, once per change, so a vibe about design only shows when you're working on design.
    private var vibesFile: [Vibe] = []
    private func loadPersonalVibes() {
        guard vibesOn else { return }
        let file = (try? Data(contentsOf: Fuse.vibesURL)).flatMap { try? JSONDecoder().decode(FuseVibes.self, from: $0) }
        let vibes = file?.vibes.filter { !$0.label.isEmpty && !$0.emoji.isEmpty } ?? []
        guard vibes != vibesFile else { return }
        vibesFile = vibes
        let given = vibes.map { var v = $0; if v.topic == "any" { v.topic = "" }; return v } // "" = any topic, set by your AI
        guard given.contains(where: { $0.topic == nil }) else { return useVibes(given) }
        personalVibes = given.filter { $0.topic != nil } // the rest wait for Laya to tag them
        Task {
            guard let tagged = await scorer?.tagTopics(given), vibesFile == vibes else { return }
            useVibes(tagged)
        }
    }

    private func useVibes(_ vibes: [Vibe]) {
        personalVibes = vibes.map { var v = $0; if v.topic == "" { v.topic = nil }; return v }
        vibePicked = nil
    }

    /// Picks again when your band changes or after 3 new messages, so the vibe moves with the session without flickering.
    /// Laya chooses from a shortlist (yours first, then stock) by a text-free summary; without the model, the rules do.
    private func updateVibe(_ now: Double) {
        guard vibesOn, recent.count >= Vibe.minimumMessages, let newest = recent.last?.ts else { vibe = nil; vibePicked = nil; return }
        let band = Vibe.band(state, recent: recent, now: now)
        if let p = vibePicked, p.band == band, recent.filter({ $0.ts > p.newest }).count < 3 { return }
        vibePicked = (band, newest)
        let shortlist = Vibe.candidates(band, personal: personalVibes, seed: Int(now / 1800), topic: Vibe.topic(recent)) // fresh each half hour
        let summary = Vibe.summary(state, recent: recent, now: now)
        let rules = Vibe.of(state, recent: recent, boomedWithinHour: state.booms.last.map { now - $0.ts < 3600 } ?? false, now: now)
        Task {
            let picked = await scorer?.pickVibe(shortlist, summary: summary) ?? rules
            guard picked != vibe else { return }
            vibeIsNew = !seenVibes.contains(picked.label)
            seenVibes.insert(picked.label)
            defaults.set(Array(seenVibes), forKey: "SeenVibes")
            vibe = picked
        }
    }

    static let justifyLimit = 40 // short and honest

    func canJustify(_ boom: String) -> Bool { justifications[boom] == nil } // solo too; the Club is a bonus

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

    /// After a Boom: seconds until a fresh stick, whichever comes first of 10 quiet minutes or 30 minutes without heat.
    func freshLeft(at now: Date) -> Double? {
        state.freshAt.map { max(0, $0 - shaved - now.timeIntervalSince1970) }
    }

    /// Easter egg: once you've justified, each tap on the 💥 shaves 2 s off the wait, at most a minute. No UI.
    func hurry() {
        guard state.freshAt != nil, let last = lastActivity, shaved < 60 else { return }
        shaveKey = last
        shaved += 2
        scheduleBreakEnd()
    }

    /// Ends the wait on time: a plain reload brings the fresh stick, and a hurried one needs a rest event.
    private func scheduleBreakEnd() {
        breakEnd?.cancel()
        guard let left = freshLeft(at: .now) else { return }
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

    /// Your idea as a prefilled issue on the public repo, where you post it. Nothing leaves until you press Submit on GitHub.
    func submitPrompt() {
        guard let (name, prompt) = Alerts.submitPrompt() else { return }
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "dev"
        let body = "**Prompt**\n\n\(prompt.prefix(4000))\n\n**Name for the changelog:** \(name.isEmpty ? "anonymous" : name)\n\n_Sent from Lunte \(version)_"
        var url = URLComponents(string: "https://github.com/ProggePal/lunte-app/issues/new")!
        url.queryItems = [URLQueryItem(name: "title", value: "Prompt request: " + prompt.prefix(60).replacingOccurrences(of: "\n", with: " ")),
                          URLQueryItem(name: "body", value: body)]
        url.percentEncodedQuery = url.percentEncodedQuery?.replacingOccurrences(of: "+", with: "%2B") // a "+" would arrive as a space
        if let link = url.url { NSWorkspace.shared.open(link) }
    }

    /// The one prompt that has your AI set up your fuse (contract §8).
    func copySetupPrompt() { copyToClipboard(Fuse.setupPrompt) }

    /// "Tuning your fuse… 40 of 212", or why it failed; nil when untuned or tuned.
    var fuseLine: String? {
        switch fuse {
        case .untuned, .tuned: return nil
        case .tuning(let done, let of): return "Tuning your fuse… \(done) of \(of)"
        case .failed(let why): return "Couldn’t tune your fuse: " + why
        }
    }

    /// A random wait between your outburst and the bang, so the room has to guess who it was (GAME.md).
    static let boomDelay = 5.0...60.0

    /// The fuse burns for `seconds` (sparks dripping from the menu bar icon), then it blows from the icon, with the sound.
    /// A test isn't a Boom in the game, so the menu bar says BOOM on its own: until onboarding's fresh stick, or for 10 s.
    private func light(_ seconds: Double, sound: Bool, test: Bool = false) {
        fusing = true
        Blast.run(fuse: seconds) { [weak self] in
            guard let self else { return }
            fusing = false
            if sound { playBoom() }
            guard test else { return }
            testBlown = true
            if onboarded { Task { try? await Task.sleep(for: .seconds(10)); self.testBlown = false } }
        }
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

    private func watch(_ path: String, _ mask: DispatchSource.FileSystemEvent, _ action: @escaping @MainActor () -> Void) -> DispatchSourceFileSystemObject? {
        let fd = open(path, O_EVTONLY)
        guard fd >= 0 else { return nil }
        let source = DispatchSource.makeFileSystemObjectSource(fileDescriptor: fd, eventMask: mask, queue: .main)
        source.setEventHandler { MainActor.assumeIsolated { action() } }
        source.setCancelHandler { close(fd) }
        source.resume()
        return source
    }

    /// (Re)opens events.jsonl when it appears or is replaced by a new file.
    private func rewatchLog() {
        let inode = (try? FileManager.default.attributesOfItem(atPath: log.path))?[.systemFileNumber] as? Int
        guard inode != watchedInode else { return }
        fileSource?.cancel()
        fileSource = inode == nil ? nil : watch(log.path, [.write, .extend, .delete, .rename]) { [weak self] in self?.changed() }
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
        recent = Array(events.filter { $0.burn != .test && $0.burn != .rest && now - $0.ts < Game.cooling }.suffix(200)) // ponytail: capped for a very busy half hour
        updateVibe(now)
        lastActivity = events.last { $0.burn != .rest }?.ts
        if shaveKey != lastActivity { shaveKey = nil; shaved = 0 } // a new prompt restarts the break
        onboard(events.filter { $0.burn == .test }, now: now)
        scheduleBreakEnd()
        let fresh = state.booms.filter { !announced.contains($0.id) }
        guard !fresh.isEmpty else { return }
        for boom in fresh {
            announced.insert(boom.id)
            guard now - boom.ts < 600 else { continue } // older than 10 minutes: announced silently
            light(.random(in: Self.boomDelay), sound: soundOn)
            if club != nil { post(boom) } // anonymous, and the Club polls every 30 s, so posting now gives nothing away
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
        light(3, sound: true, test: true)
    }

    /// Onboarding: you own the test Boom, and 10 seconds later you get your first fresh stick. Kept on this Mac only.
    func ownTest(_ line: String) {
        ownedTest = (line, Date().addingTimeInterval(10))
        Task {
            try? await Task.sleep(for: .seconds(10))
            ownedTest = nil
            testBlown = false
            onboarded = true
            defaults.set(true, forKey: "Onboarded")
        }
    }

    /// Tucked away in the gear while onboarding shows: straight to the game, as if you'd finished it.
    func skipOnboarding() {
        ownedTest = nil
        testBlown = false
        connected = true
        onboarded = true
        defaults.set(true, forKey: "Connected")
        defaults.set(true, forKey: "Onboarded")
    }

    /// Start the onboarding over, from the checklist.
    func replayOnboarding() {
        connected = false
        onboarded = false
        defaults.set(false, forKey: "Connected")
        defaults.set(false, forKey: "Onboarded")
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
        for key in ["Mine", "Secrets", "Reactions"] { defaults.removeObject(forKey: key) } // your justifications stay
        clubFeed = []
        lastSeq = 0
        saveClub()
    }

    /// Justify a Boom: saved on this Mac, and sent to your Club (the relay's "why") when the Boom reached it.
    /// Returns a message when the Club couldn't get it, or nil.
    func justify(_ boom: String, _ text: String) async -> String? {
        let line = String(text.trimmingCharacters(in: .whitespacesAndNewlines).prefix(Self.justifyLimit))
        guard !line.isEmpty else { return nil }
        justifications[boom] = line
        defaults.set(justifications, forKey: "Justifications")
        guard club != nil, let secret = secrets[boom] else { return nil } // solo, or this Boom never reached the Club
        do {
            try await Relay.post(["type": "why", "boom": boom, "text": line, "secret": secret])
            await poll(notify: true)
            return nil
        } catch {
            return "Saved, but your Club didn't get it. " + error.localizedDescription
        }
    }

    private func join(_ code: String, _ name: String) async throws {
        try await Relay.join(code, name: name)
        club = code
        clubName = Relay.clubName
        clubFeed = []
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
                clubFeed = Array((clubFeed + page).suffix(5))
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
        defaults.set(try? JSONEncoder().encode(clubFeed), forKey: "Recent")
    }

}

func copyToClipboard(_ s: String) {
    NSPasteboard.general.clearContents()
    NSPasteboard.general.setString(s, forType: .string)
}
