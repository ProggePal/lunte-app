import AppKit
import FuseKit
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
    /// Everyone who's joined the Club since you did, and before, as far as its history goes. The relay has no list.
    @Published private(set) var members = defaults.stringArray(forKey: "Members") ?? []
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
    /// Each closed session's name (`Story.names`), by when it started.
    @Published private(set) var names: [Double: String] = [:]
    /// When the newest session you've opened in Today started: a newer one waits there with a dot.
    @Published private(set) var seen = defaults.double(forKey: "SeenSession")
    /// When the newest session whose pill you've watched run back started: a newer one in Today runs back at your next look.
    @Published private(set) var played = defaults.object(forKey: "PlayedSession") as? Double ?? defaults.double(forKey: "SeenSession")
    /// The fuse is burning towards a Boom that hasn't gone off yet.
    @Published private(set) var fusing = false
    /// The popover is open. Its clocks stop while it's closed, so a closed panel never wakes the app.
    @Published var popoverOpen = false
    /// The earlier session dived into, by start, which has the popover to itself; the menu bar's icon comes back out.
    @Published var diving: Double?
    /// A test Boom has blown, so the menu bar says BOOM.
    @Published private(set) var testBlown = false
    /// The vibe line, off by default while vibes are still taking shape. Off means no vibe is picked and no topic is
    /// asked; nothing about vibes runs at all.
    @Published var vibesOn = defaults.bool(forKey: "VibesOn") {
        didSet {
            defaults.set(vibesOn, forKey: "VibesOn")
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
    enum Detector: Equatable {
        case notInstalled, downloading(Double), settingUp, loading, ready, failed(String) // loading: an installed one, at launch
        /// How far the download is, while it's downloading.
        var share: Double? { if case .downloading(let share) = self { share } else { nil } }
    }
    @Published private(set) var detector: Detector = .notInstalled
    /// You chose "Not now" for the Heat Detector in onboarding, so its row offers the download instead.
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
    /// What Lunte plays, only the Boom until you ask for more.
    // Why: the Boom is the only sound unless you ask (docs/why.md#fuse-sounds-opt-in)
    @Published var sounds = Sounds(rawValue: defaults.string(forKey: "Sounds") ?? "") ?? .boom {
        didSet { defaults.set(sounds.rawValue, forKey: "Sounds") }
    }
    /// How loud, 0 (silent) to 1, a share of `Bang.cap`. It was a switch, "SoundOn".
    @Published var volume = defaults.object(forKey: "Volume") as? Double ?? (defaults.object(forKey: "SoundOn") as? Bool ?? true ? 1 : 0) {
        didSet { defaults.set(volume, forKey: "Volume") }
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
    /// The newest Club event you've seen in the Club's window.
    @Published private var clubSeenSeq = defaults.integer(forKey: "ClubSeen")

    private let log = EventLog.defaultURL
    private var dirSource: DispatchSourceFileSystemObject?
    private var fileSource: DispatchSourceFileSystemObject?
    private var watchedInode: Int?
    private var debounce: Task<Void, Never>?
    /// The prompt the hook just handed to the model, by its time, until the log has it: the breeze starts on it at once,
    /// about 15 ms after Enter, not when the log comes round a second later.
    // Why: your own feedback is instant (docs/why.md#two-clocks)
    @Published private var heard: Double?
    private var polling = false

    init() {
        Notifier.setUp()
        let demo = ["FuseDemo", "Lab"].contains { UserDefaults.standard.bool(forKey: $0) } || UserDefaults.standard.string(forKey: "HeroDemo") != nil
        if !demo { linkHook() } // a demo build never takes your Claude Code hook from your own Lunte
        let dir = log.deletingLastPathComponent()
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        dirSource = watch(dir.path, [.write]) { [weak self] in self?.changed() } // events.jsonl created, replaced or removed
        // The fuse folder, where your AI saves labels.json and vibes.json (`lunte-hook setup` tells it how).
        try? FileManager.default.createDirectory(at: Fuse.dir, withIntermediateDirectories: true)
        scorer = Scorer(log: log) { [weak self] status in
            self?.fuse = status
            if status.isTuned { self?.retuning = false } // tuned again, cool and all
        }
        scorer?.heard = { [weak self] in self?.heard = $0 }
        if HeatDetector.isInstalled() { setUpDetector(first: false) }
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

    #if DEBUG
    /// For previews: the game these events make, now, with their prompts' text. Nothing is watched, polled, sent or saved.
    init(preview events: [Event], texts: [Double: String], club: String? = "Antler", feed: [ClubEvent] = [],
         line: String? = nil, reactions: [String] = [], members: [String] = [], mine: Set<String> = []) {
        connected = true
        onboarded = true
        detector = .ready
        state = Game.replay(events, now: Date().timeIntervalSince1970)
        messages = events
        session = state.sittingStart.map { start in events.filter { $0.ts >= start } } ?? []
        past = state.sittings.filter { !$0.isOpen }
        names = named(past, now: Date().timeIntervalSince1970, personal: [])
        promptCache = texts
        self.club = club.map { _ in "PREVIEW" }
        clubName = club
        clubFeed = feed
        self.members = members
        self.mine = mine
        clubSeenSeq = 0
        if let boom = state.booms.last {
            justifications = line.map { [boom.id: $0] } ?? [:]
            self.reactions = [boom.id: reactions]
        }
    }

    /// A Mac partway through onboarding: which step it's on, as the previews show it.
    convenience init(onboarding detector: Detector, plugin: Bool = false, fuse: Scorer.Status = .untuned, connected: Bool = false,
                     owned: String? = nil) {
        self.init(preview: [], texts: [:], club: nil)
        self.detector = detector
        detectorLater = false
        pluginInstalled = plugin
        self.fuse = fuse
        self.connected = connected
        onboarded = false
        ownedTest = owned.map { ($0, Date().addingTimeInterval(10)) }
    }
    #endif

    // MARK: The menu

    /// How long "Held it together" shows after the fuse climbs out of its last third.
    static let heldFor: Double = 600

    /// A close call in the last 10 minutes: the fuse got into its last third and climbed back out without a Boom.
    /// The 60-second reload takes it away on time.
    var heldTogether: Bool {
        guard !state.boomed, let last = state.closeCalls.last else { return false }
        return Date().timeIntervalSince1970 - last.cooled < Self.heldFor
    }

    /// How long the menu bar keeps the tier's name, or "Still burning", after the Boom or its last escalation, before it
    /// says "Cooled off".
    // Why: calm technology; a Boom shouts once, then steps back (docs/why.md#quiet-boom)
    static let loudFor: Double = 600

    /// Blown for a while: the menu bar says "Cooled off", while the popover still says you're blown. The 60-second
    /// reload quiets it on time.
    var boomQuiet: Bool {
        guard state.boomed, let boom = state.booms.last else { return false }
        return Date().timeIntervalSince1970 - (boom.escalations.last ?? boom.ts) >= Self.loudFor
    }

    /// What the menu bar fuse shows. After a Boom, its heat is how far the burn has got toward the next tier.
    var fuseLook: FuseLook {
        assert(FuseScene.full == Game.full) // the menu bar draws the game's full
        guard connected else { return FuseLook(phase: .offline) }
        if fusing { return FuseLook(phase: .fusing, left: 0) }
        if testBlown { return FuseLook(phase: .blown, name: tier(1).name) } // the test Boom has no tier
        guard state.boomed, let boom = state.booms.last else {
            let last = session.last, now = Date().timeIntervalSince1970
            // Heard from the hook and not in the log yet: the same look the log will bring, a breeze while it's rated.
            if let heard, heard > last?.ts ?? 0, now - heard < Game.ratingWait { return FuseLook(left: state.left, prompt: heard, rating: true) }
            let bite = last.map { (Game.burn($0, at: now) + Game.mend($0)) / state.fuse } ?? 0 // its heat alone
            return FuseLook(left: state.left, prompt: last?.ts, rating: last?.awaitingRating(at: now) ?? false, bite: bite)
        }
        let stick = max(Game.minFuse, state.fuse - Game.boomGrowth) // ponytail: the stick that blew, unless a day ended since
        let toward = state.burned / (Game.escalationStep * stick) - Double(boom.tier - 1)
        return FuseLook(phase: .blown, name: tier(boom.tier).name, tier: boom.tier,
                        heat: min(1, max(0, toward)), quiet: boomQuiet)
    }

    /// For VoiceOver: the vibe, and how much stick is left, or the Boom's tier.
    var sentence: String {
        let vibe = self.vibe.map { $0.label + ". " } ?? ""
        guard state.boomed, let boom = state.booms.last else { return vibe + "\(Int((state.left * 100).rounded()))% of the fuse left." }
        return tier(boom.tier).name + ". " + vibe
    }

    // MARK: Sessions

    /// You opened a session in Today: the newest one you've opened stops waiting with a dot.
    // Why: a finished session waits in Today for your next look (docs/why.md#summary-next-open)
    func opened(_ s: Sitting) {
        guard s.start > seen else { return }
        seen = s.start
        defaults.set(seen, forKey: "SeenSession")
    }

    /// You watched a session's pill run back to its end.
    func played(_ s: Sitting) {
        guard s.start > played else { return }
        played = s.start
        defaults.set(played, forKey: "PlayedSession")
    }

    /// The closed sessions' names, from their facts and the session names your AI wrote at setup (vibes.json v 2).
    // ponytail: named from the first session on every reload; keep the names if history gets long enough to notice
    private func named(_ past: [Sitting], now: Double, personal: [Vibe]? = nil) -> [Double: String] {
        let file = personal == nil ? (try? Data(contentsOf: Fuse.vibesURL)).flatMap { try? JSONDecoder().decode(FuseVibes.self, from: $0) } : nil
        let yours = personal ?? (file?.v == 2 ? file!.vibes.map { var v = $0; if v.topic == "any" { v.topic = nil }; return v } : [])
        let told = past.map { s in let m = messages(in: s); return (sitting: s, events: m, line: Game.fuseLine(s, m, now: now)) }
        return Dictionary(zip(past.map(\.start), Story.names(told, personal: yours)), uniquingKeysWith: { a, _ in a })
    }

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

    /// The Club's reactions to a Boom, an emoji each: how many threw it and who, the most first; nil when nobody has yet.
    func reacted(_ boom: String) -> [(emoji: String, n: Int, names: [String])]? {
        guard let list = reactions[boom], !list.isEmpty else { return nil }
        let pairs = list.map { (emoji: String($0.prefix { $0 != " " }), name: String($0.drop { $0 != " " }.dropFirst())) }
        return Dictionary(grouping: pairs, by: \.emoji)
            .map { (emoji: $0.key, n: $0.value.count, names: Set($0.value.map(\.name)).sorted()) }
            .sorted { ($0.n, $1.emoji) > ($1.n, $0.emoji) }
    }


    func isMine(_ e: ClubEvent) -> Bool { e.boom.map(mine.contains) ?? false }

    /// Something happened in the Club since you last opened its window: someone else's Boom, line or join, or a
    /// reaction to yours.
    var clubNews: Bool { clubFeed.contains { $0.seq > clubSeenSeq && ($0.type == "react") == isMine($0) } }

    func clubSeen() {
        clubSeenSeq = clubFeed.last?.seq ?? clubSeenSeq
        defaults.set(clubSeenSeq, forKey: "ClubSeen")
    }

    /// 🧯, 😂, 🫂 or any emoji on someone else's Boom, from the Club's window.
    func react(_ boom: String, _ emoji: String) {
        Task {
            try? await Relay.post(["type": "react", "boom": boom, "emoji": emoji]) // ponytail: a failed react is dropped
            await poll(notify: false)
        }
    }

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

    /// Reads the prompts behind `events` in one pass per Claude Code session, so pointing along a session shows each
    /// at once. Kept in memory only.
    func prefetch(_ events: [Event]) async {
        let missing = events.filter { promptCache[$0.ts] == nil }.map { (sid: $0.sid, ts: $0.ts) }
        guard !missing.isEmpty else { return }
        let found = await Task.detached { Transcript.prompts(missing) }.value
        promptCache.merge(found) { mine, _ in mine }
    }

    /// The prompt behind an event, if it's been read already.
    func cachedPrompt(_ e: Event) -> String? { promptCache[e.ts] }

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

    /// Loads the Heat Detector: just installed, it's setting up, which shows; at launch it's only loading, about a
    /// second, which doesn't.
    private func setUpDetector(first: Bool = true) {
        detector = first ? .settingUp : .loading
        Task {
            let loaded = await scorer?.loadModel() == true
            detector = loaded ? .ready : .failed("The Heat Detector wouldn't start. Try downloading it again.")
        }
    }

    /// The one prompt that has your AI set up your fuse (contract §8).
    func copySetupPrompt() { copyToClipboard(Fuse.setupPrompt) }

    /// You've tuned heat but Lunte has no cool model, as when you tuned before cool came, or too few of the rated
    /// messages were cool to learn it: then every prompt reads as 0 cool, and nothing grows your fuse back.
    var coolUntuned: Bool {
        FileManager.default.fileExists(atPath: Fuse.profileURL.path) && !FileManager.default.fileExists(atPath: Fuse.coolURL.path)
    }

    /// "Tuning your fuse… 40 of 212", or why it failed; nil when untuned or tuned.
    var fuseLine: String? {
        switch fuse {
        case .untuned, .tuned: return nil
        case .tuning(let done, let of): return "Tuning your fuse… \(done) of \(of)"
        case .failed(let why): return "Couldn’t tune your fuse: " + why
        }
    }

    /// The silence between the fuse burning through and the bang, at random, so the room has to guess who it was.
    // Why: your own feedback is instant, the room's Boom is delayed (docs/why.md#two-clocks)
    static let silence = 1.0...3.0

    /// The fuse burns for `seconds` (sparks dripping from the menu bar icon), then it blows from the icon: the bang, at
    /// `volume`. `boom` goes to the Club at the bang, sound or not, never before, so no Mac pings ahead of the room.
    /// If the Mac slept through the wait, there's no bang and it never goes.
    /// A test isn't a Boom in the game, so the menu bar says BOOM on its own: until onboarding's fresh stick, or for 10 s.
    private func light(_ seconds: Double, volume: Double, test: Bool = false, posting boom: Boom? = nil) {
        fusing = true
        for (sitting, id) in burning { announce(id, sitting: sitting) } // a new Blast replaces a running one: no bang for it
        let key = boom.map(sittingKey)
        if let boom, let key { burning[key] = boom.id }
        // Each Boom blows its own way, from its id, so it looks the same if it lights again after a restart.
        let scene = BlastScene(seed: boom.flatMap { UInt64($0.id) } ?? .random(in: 0 ... .max))
        Blast.run(fuse: seconds, volume: volume, scene: scene) { [weak self] blew in
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
        if let heard, events.contains(where: { $0.ts >= heard }) { self.heard = nil } // the log has it now, whatever it was
        state = Game.replay(events, now: now)
        messages = events.filter { $0.burn != .test && $0.burn != .rest }
        session = state.sittingStart.map { start in messages.filter { $0.ts >= start } } ?? []
        let tests = events.filter { $0.burn == .test }.map(\.ts)
        past = state.sittings.filter { s in !s.isOpen && s.prompts > tests.filter { $0 >= s.start && $0 <= s.end }.count }
        names = named(past, now: now)
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
            light(FuseScene.raceFor + .random(in: Self.silence), volume: volume, posting: boom)
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

    /// The first Boom is the onboarding: "3 2 1 boom" proves the hook reaches the app. Never posted to the Club.
    private func onboard(_ tests: [Event], now: Double) {
        let fresh = tests.filter { !announced.contains(String(Int($0.ts * 1000))) }
        guard !fresh.isEmpty else { return }
        fresh.forEach { announced.insert(String(Int($0.ts * 1000))) }
        connected = true
        defaults.set(true, forKey: "Connected")
        defaults.set(Array(announced), forKey: "Announced")
        guard fresh.contains(where: { now - $0.ts < 600 }) else { return }
        light(FuseScene.raceFor + 2, volume: volume, test: true) // the whole show: the burn, the silence, the bang
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

    /// Setup again to tune cool, from the cool nudge: its tune step stays open, though you've tuned heat before, until
    /// a new tune is done.
    @Published private(set) var retuning = false

    func retune() {
        retuning = true
        replayOnboarding()
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
        members = []
        lastSeq = 0
        clubSeenSeq = 0
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
        members = []
        lastSeq = 0
        clubSeenSeq = 0
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
                for e in page where e.type == "join" { if let who = e.from, !members.contains(who) { members.append(who) } }
                clubFeed = Array((clubFeed + page).suffix(100)) // ponytail: the window's history; page it if a Club outgrows it
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
        defaults.set(members, forKey: "Members")
    }

}

func copyToClipboard(_ s: String) {
    NSPasteboard.general.clearContents()
    NSPasteboard.general.setString(s, forType: .string)
}
