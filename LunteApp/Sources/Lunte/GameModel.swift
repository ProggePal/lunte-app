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
    /// Your messages from the last 30 minutes (no onboarding test), for the vibe.
    @Published private(set) var recent: [Event] = []
    /// Every message in the log (no onboarding test, no rest), oldest first, for heat lines.
    @Published private(set) var messages: [Event] = []
    /// The open session's messages, oldest first: the dots.
    @Published private(set) var session: [Event] = []
    /// Closed sessions with a message of yours in them (not just the onboarding test), oldest first. On this Mac only.
    @Published private(set) var past: [Sitting] = []
    /// The last session's summary, each time the popover opens after it closed, until its card has shown once.
    @Published private(set) var summary: Sitting?
    /// The start of the last session summarised, so each summary shows once.
    private var summarised = defaults.double(forKey: "Summarised")
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
    /// The Heat Detector model on this Mac (contract §6). Nothing downloads until you press Download.
    enum Detector: Equatable { case notInstalled, downloading(Double), settingUp, ready, failed(String) }
    @Published private(set) var detector: Detector = .notInstalled
    /// You chose "Not now" on the first screen, so the footer offers the download instead.
    @Published private(set) var detectorLater = defaults.bool(forKey: "DetectorLater")

    /// Your personal fuse: untuned, tuning, tuned (with its fit), or why it failed.
    @Published private(set) var fuse: Scorer.Status = .untuned
    private var fuseSource: DispatchSourceFileSystemObject?
    private var fuseDebounce: Task<Void, Never>?
    /// When you last sent a prompt: the 30 quiet minutes count from here.
    @Published private(set) var lastActivity: Double?
    private var promptCache: [Double: String] = [:]
    /// Seconds shaved off the wait for a fresh stick by tapping the emoji, and which wait (last prompt) they belong to.
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
    /// Booms done with for good (`announce`), and the onboarding tests.
    private var announced = Set(defaults.stringArray(forKey: "Announced") ?? [])
    /// Sittings whose fuse was lit (`sittingKey`) → the Boom id it banged under. A Sitting bangs once, even when a late
    /// rating moves its Boom to an earlier prompt, which gives it a new id.
    private var lit = defaults.dictionary(forKey: "Lit") as? [String: String] ?? [:]
    /// The same for the fuse that's burning, in memory only: it's announced at its bang, so a Boom whose fuse is still
    /// burning when Lunte quits, crashes or updates lights again when it opens, if it's under 10 minutes old.
    private var burning: [String: String] = [:]
    private var secrets = defaults.dictionary(forKey: "Secrets") as? [String: String] ?? [:] // ponytail: UserDefaults, not the Keychain
    private var lastSeq = defaults.integer(forKey: "LastSeq")

    private let log = EventLog.defaultURL
    private var dirSource: DispatchSourceFileSystemObject?
    private var fileSource: DispatchSourceFileSystemObject?
    private var watchedInode: Int?
    private var debounce: Task<Void, Never>?
    private var polling = false

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
        if HeatDetector.isInstalled() { setUpDetector() }
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

    /// How long "Held it together" shows after the fuse climbs out of its last third.
    static let heldFor: Double = 600

    /// A close call in the last 10 minutes: the fuse got into its last third and climbed back out without a Boom.
    /// The 60-second reload takes it away on time.
    var heldTogether: Bool {
        guard !state.boomed, let last = state.closeCalls.last else { return false }
        return Date().timeIntervalSince1970 - last.cooled < Self.heldFor
    }

    /// How long the menu bar says BOOM after the Boom or its last escalation, before it quiets down.
    // Why: calm technology; a Boom shouts once, then steps back (docs/why.md#quiet-boom)
    static let loudFor: Double = 600

    /// Blown for a while: the menu bar's 💥 has quieted down, while the popover still says you're blown. The 60-second
    /// reload quiets it on time.
    var boomQuiet: Bool {
        guard state.boomed, let boom = state.booms.last else { return false }
        return Date().timeIntervalSince1970 - (boom.escalations.last ?? boom.ts) >= Self.loudFor
    }

    /// Your Club's name, or nil without one.
    var clubLabel: String? { club.map { clubName ?? $0 } }

    /// For VoiceOver: the vibe, and how much stick is left, or the Boom's tier.
    var sentence: String {
        let vibe = self.vibe.map { $0.label + ". " } ?? ""
        guard state.boomed, let boom = state.booms.last else { return vibe + "\(Int((state.left * 100).rounded()))% of the fuse left." }
        return tier(boom.tier).name + ". " + vibe
    }

    // MARK: Sessions

    /// The popover opened: after a session closed, and before the next one starts, its summary shows.
    // Why: the peak-end rule; the summary waits for your next look (docs/why.md#summary-next-open)
    func popoverOpened() {
        guard onboarded, state.sitting == nil, let last = past.last, last.start > summarised else { return }
        summary = last
    }

    /// The summary card is on screen, so it's used up. Not before: another screen, like the Heat Detector's, can fill
    /// the popover instead.
    func summaryShown() {
        guard let summary else { return }
        summarised = summary.start
        defaults.set(summarised, forKey: "Summarised")
    }

    /// The popover closed: the summary goes away. History keeps it.
    func popoverClosed() { summary = nil }

    /// A session's messages, oldest first, for its heat line.
    func messages(in s: Sitting) -> [Event] { messages.filter { $0.ts >= s.start && $0.ts <= s.end } }

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

    /// After a Boom: seconds until a fresh stick, which comes when the session closes after 30 quiet minutes
    /// (`freshAt`), less what the hurry easter egg shaved off.
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

    /// Your idea, straight to the Lunte team's inbox on the relay.
    func submitPrompt() {
        guard let (name, prompt) = Alerts.submitPrompt() else { return }
        Task {
            do {
                try await Relay.submitPrompt(name: name, prompt: prompt)
                Alerts.tell("Thanks, it's in", "If we build it, you're credited in the changelog.")
            } catch let error as RelayError where error.status == 429 {
                Alerts.tell("That's a lot of ideas", "You've sent the most we take in an hour. Try again a bit later.")
            } catch {
                Alerts.tell("Couldn't send your prompt", "Check your connection and try again. " + error.localizedDescription)
            }
        }
    }

    // MARK: The Heat Detector

    /// Downloads the Heat Detector (483 MB, checked file by file), then loads it. Progress shows in the footer.
    func installDetector() {
        switch detector {
        case .notInstalled, .failed: break
        default: return
        }
        detector = .downloading(0)
        Task {
            do {
                try await HeatDetector.install { share in
                    Task { @MainActor in // every half percent is plenty for a progress bar
                        guard case .downloading(let shown) = self.detector, share - shown >= 0.005 || share == 1 else { return }
                        self.detector = .downloading(share)
                    }
                }
                setUpDetector()
            } catch {
                detector = .failed(error.localizedDescription)
            }
        }
    }

    func detectorNotNow() {
        detectorLater = true
        defaults.set(true, forKey: "DetectorLater")
    }

    private func setUpDetector() {
        detector = .settingUp
        Task {
            let loaded = await scorer?.loadModel() == true
            detector = loaded ? .ready : .failed("The Heat Detector wouldn't start. Try downloading it again.")
        }
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

    /// A random wait between your outburst and the bang, so the room has to guess who it was.
    // Why: your own feedback is instant, the room's Boom is delayed (docs/why.md#two-clocks)
    static let boomDelay = 5.0...60.0

    /// The fuse burns for `seconds` (sparks dripping from the menu bar icon), then it blows from the icon: a fizz and the
    /// bang, with `sound`. `boom` goes to the Club at the bang, sound or not, never before, so no Mac pings ahead of the room.
    /// If the Mac slept through the wait, there's no bang and it never goes.
    /// A test isn't a Boom in the game, so the menu bar says BOOM on its own: until onboarding's fresh stick, or for 10 s.
    private func light(_ seconds: Double, sound: Bool, test: Bool = false, posting boom: Boom? = nil) {
        fusing = true
        for (sitting, id) in burning { announce(id, sitting: sitting) } // a new Blast replaces a running one: no bang for it
        let key = boom.map(sittingKey)
        if let boom, let key { burning[key] = boom.id }
        Blast.run(fuse: seconds, sound: sound) { [weak self] blew in
            guard let self else { return }
            fusing = false
            if let boom { announce(boom.id, sitting: key) }
            if blew, let boom, club != nil { post(boom) }
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
        messages = events.filter { $0.burn != .test && $0.burn != .rest }
        session = state.sittingStart.map { start in messages.filter { $0.ts >= start } } ?? []
        let tests = events.filter { $0.burn == .test }.map(\.ts)
        past = state.sittings.filter { s in !s.isOpen && s.prompts > tests.filter { $0 >= s.start && $0 <= s.end }.count }
        recent = Array(messages.filter { now - $0.ts < Game.cooling }.suffix(200)) // ponytail: capped for a very busy half hour
        updateVibe(now)
        lastActivity = events.last { $0.burn != .rest }?.ts
        if shaveKey != lastActivity { shaveKey = nil; shaved = 0 } // a new prompt restarts the wait
        onboard(events.filter { $0.burn == .test }, now: now)
        scheduleBreakEnd()
        for boom in state.booms where !announced.contains(boom.id) {
            let key = sittingKey(boom)
            guard burning[key] == nil else { continue } // its Sitting's fuse is burning, and that bang announces it
            // Older than 10 minutes, or its Sitting was lit already and a late rating moved the Boom: announced silently.
            guard now - boom.ts < 600, lit[key] == nil else { announce(boom.id); continue }
            light(.random(in: Self.boomDelay), sound: soundOn, posting: boom)
        }
    }

    /// Done with a Boom for good: it banged, the Mac slept through it, a new fuse replaced its own, or it's too old.
    /// With its Sitting, that Sitting has been lit, under this id.
    private func announce(_ id: String, sitting: String? = nil) {
        announced.insert(id)
        defaults.set(Array(announced), forKey: "Announced")
        guard let sitting else { return }
        burning[sitting] = nil
        lit[sitting] = id
        defaults.set(lit, forKey: "Lit")
    }

    /// A Boom's Sitting, by its start written the way a Boom id is: what gets lit once.
    private func sittingKey(_ boom: Boom) -> String {
        String(Int((state.sittings.first { $0.boom?.id == boom.id }?.start ?? boom.ts) * 1000))
    }

    /// The id a Boom's fuse was lit for, which its comment, its reactions and the Club keep, even if a late rating has
    /// moved the Boom to an earlier prompt since. Its own id until its fuse is lit.
    func litID(_ boom: Boom) -> String {
        let key = sittingKey(boom)
        return lit[key] ?? burning[key] ?? boom.id
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
        light(3, sound: soundOn, test: true)
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

    /// Sent at the bang (`light`).
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
            // A comment typed while the fuse burned waited for the Boom. From here on, `justify` sends it, so it goes once.
            guard let line = justifications[boom.id] else { return }
            try? await Relay.post(["type": "why", "boom": boom.id, "text": line, "secret": secret]) // ponytail: no retry either
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

    /// Justify a Boom: saved on this Mac, and sent to your Club (the relay's "why") once the Boom has reached it. While
    /// its fuse still burns, `post` sends it right after the Boom. Returns a message when the Club couldn't get it, or nil.
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

    /// Reactions never notify: those on your own Boom pile up on its card, so nothing pops up to say it was yours.
    private func notify(about e: ClubEvent) {
        let who = e.from ?? "Someone"
        switch e.type {
        case "boom" where !isMine(e):
            Notifier.post("💥 Boom in your Club", "Someone lost it. Throw them something.", boom: e.boom)
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
