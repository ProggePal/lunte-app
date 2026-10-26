import Foundation
import LayaKit
import LunteCore

/// Rates your prompts with Laya on the Neural Engine (contract §6, §8). The hook hands each prompt over a local socket,
/// and every rating lands in the log as a heat line.
/// - Untuned: heat is Laya's P(frustrated) for the mood probe.
/// - Tuned: every probe is asked (~90 ms), and your personal fuse (fuse/profile.json) turns the answers into heat.
///   Your cool model (fuse/cool.json), trained the same way on the cool ratings, turns the same answers into cool.
///   Without it, cool stays nil.
/// The model is the Heat Detector (`HeatDetector`, 483 MB), installed only when you press Download. Until it's loaded
/// nothing listens on the socket, so the hook doesn't wait and the word list decides.
@MainActor
final class Scorer {
    enum Status: Equatable {
        case untuned, tuning(done: Int, of: Int), tuned(PersonalFuse), failed(String)
        var isTuned: Bool { if case .tuned = self { true } else { false } }
        var isFailed: Bool { if case .failed = self { true } else { false } }
    }

    /// The probe questions. The first is the mood (its answer also feeds the vibe line). Short descriptions keep
    /// each one well inside the bucket's 128 tokens. Renaming or reordering them invalidates trained profiles.
    nonisolated static let probes: [(name: String, question: LayaQuestion, chars: Int)] = [
        ("mood", .choice("The writer's mood toward their AI assistant?", options: [
            .init("frustrated", description: "angry or annoyed"), .init("confused", description: "unsure, asking"),
            .init("hyped", description: "excited, happy"), .init("grateful", description: "thankful"),
            .init("tired", description: "worn out"), .init("neutral", description: "plain request")]), 1000),
        ("tone", .choice("What is the writer's tone toward their AI assistant?", options: [
            .init("A", description: "friendly"), .init("B", description: "neutral"), .init("C", description: "impatient"), .init("D", description: "angry")]), 1000),
        ("tone-opening", .choice("What is the writer's tone toward their AI assistant?", options: [
            .init("A", description: "friendly"), .init("B", description: "neutral"), .init("C", description: "impatient"), .init("D", description: "angry")]), 200),
        ("annoyed", .choice("Is the writer annoyed or angry at their AI assistant?", options: [
            .init("A", description: "no, calm: a request, a question, a bug report or a happy message"),
            .init("B", description: "yes: annoyed, impatient, scolding, swearing or shouting at the assistant")]), 1000),
        ("calm-or-annoyed", .choice("Is the writer annoyed or angry at their AI assistant?", options: [
            .init("calm", description: "a request, a question, a bug report or a happy message"),
            .init("annoyed", description: "impatient, scolding, swearing or shouting at the assistant")]), 1000),
        ("blame", .choice("Does the writer blame the assistant for a mistake it made?", options: [.init("A", description: "no"), .init("B", description: "yes")]), 1000),
        ("repeat", .choice("Is the writer repeating an instruction they already gave, or correcting the assistant?", options: [
            .init("A", description: "no"), .init("B", description: "yes")]), 1000),
        ("swear", .choice("Does the writer swear, shout in capitals or use harsh words?", options: [
            .init("A", description: "no"), .init("B", description: "yes, but happily"), .init("C", description: "yes, in anger")]), 1000),
        ("praise", .choice("Is the writer praising or thanking the assistant?", options: [.init("A", description: "no"), .init("B", description: "yes")]), 1000),
        ("kind", .choice("What kind of message is this?", options: [
            .init("A", description: "a task or instruction"), .init("B", description: "a question"),
            .init("C", description: "feedback on the result"), .init("D", description: "a complaint")]), 1000),
        ("patience", .choice("How much patience does the writer have left with their AI assistant?", options: [
            .init("A", description: "plenty"), .init("B", description: "some"), .init("C", description: "very little"), .init("D", description: "none")]), 1000),
    ]

    /// What a message is about, for session names (`Story.activity`) and the vibe line. Asked on its own, so it never
    /// changes a trained fuse's features.
    nonisolated static let topicQuestion = LayaQuestion.choice("What is this message to an AI assistant about?",
                                                             options: Vibe.topics.map { .init($0.name, description: $0.about) })

    private var laya: LayaManager?
    private var profile: PersonalFuse?
    private var coolProfile: PersonalFuse?
    private var listener: DispatchSourceRead?
    private let log: URL
    private let report: (Status) -> Void

    init(log: URL, report: @escaping (Status) -> Void) {
        self.log = log
        self.report = report
        let load = { (url: URL) in
            (try? Data(contentsOf: url)).flatMap { try? JSONDecoder().decode(PersonalFuse.self, from: $0) }
                .flatMap { $0.probes == Scorer.probes.map(\.name) ? $0 : nil } // trained on other probes: tune again
        }
        profile = load(Fuse.profileURL)
        coolProfile = load(Fuse.coolURL)
        report(profile.map(Status.tuned) ?? .untuned)
    }

    /// Loads the installed Heat Detector and starts listening. The first load compiles it for the Neural Engine
    /// (~20 s, once). Never downloads. False when it isn't installed or won't load.
    func loadModel() async -> Bool {
        if laya != nil { return true }
        guard HeatDetector.isInstalled() else { return false }
        do {
            laya = try await LayaManager.load(from: HeatDetector.dir, configuration: .init(lengths: [128], precision: "e8"))
        } catch {
            return false
        }
        let fd = ScorerSocket.listen()
        guard fd >= 0 else { return true }
        let source = DispatchSource.makeReadSource(fileDescriptor: fd, queue: .main)
        source.setEventHandler { [weak self] in
            let conn = accept(fd, nil, nil)
            guard conn >= 0 else { return }
            var wait = timeval(tv_sec: 1, tv_usec: 0) // a client that never closes can't hang the menu
            setsockopt(conn, SOL_SOCKET, SO_RCVTIMEO, &wait, socklen_t(MemoryLayout<timeval>.size))
            let data = FileHandle(fileDescriptor: conn, closeOnDealloc: true).readDataToEndOfFile() // the hook writes one line and closes
            MainActor.assumeIsolated { self?.rate(data) }
        }
        source.setCancelHandler { close(fd); unlink(ScorerSocket.url.path) }
        source.resume()
        listener = source
        if labelsAreNewer() { tune() }
        return true
    }

    private func rate(_ line: Data) {
        guard let laya, let r = try? JSONSerialization.jsonObject(with: line) as? [String: Any],
              let ts = r["ts"] as? Double, let text = r["text"] as? String else { return }
        let log = log, profile = profile, coolProfile = coolProfile
        Task.detached(priority: .utility) {
            guard let answers = await Scorer.answers(laya, text, all: profile != nil || coolProfile != nil) else { return }
            let mood = answers[0], features = Scorer.features(answers)
            let heat = profile.map { $0.heat(features) } ?? Double(mood.probabilities[0])
            let cool = coolProfile.map { $0.heat(features) } // the cool model's heat is cool
            // What it's about, one word, so a finished session can be named for its work (`Story.activity`).
            let topic = try? await laya.answer(state: String(text.prefix(1000)), question: Scorer.topicQuestion).selectedLabel
            try? EventLog.append(Event(ts: ts, burn: .heat, heat: heat, cool: cool, mood: mood.selectedLabel, topic: topic), to: log) // the watcher reloads
        }
    }

    /// Laya's answers to the probes, in order: all of them, or only the mood.
    nonisolated static func answers(_ laya: LayaManager, _ text: String, all: Bool) async -> [LayaAnswer]? {
        let clean = text.replacingOccurrences(of: "(?s)```.*?(```|$)", with: " ", options: .regularExpression)
        var out: [LayaAnswer] = []
        for probe in all ? probes : Array(probes.prefix(1)) {
            let state = String(clean.prefix(probe.chars))
            guard let a = try? await laya.answer(state: state.isEmpty ? "." : state, question: probe.question) else { return nil }
            out.append(a)
        }
        return out
    }

    /// The numbers the personal fuse reads: the log probability of every option of every probe.
    nonisolated static func features(_ answers: [LayaAnswer]) -> [Double] {
        answers.flatMap { $0.probabilities.map { Foundation.log(Double($0) + 1e-4) } }
    }

    /// Tags vibes that have no topic with the one Laya reads in their label and "when", if it's sure (over half
    /// its probability on one topic, and not "other"). Waits up to a minute for the model; nil if it never loads.
    func tagTopics(_ vibes: [Vibe]) async -> [Vibe]? {
        for _ in 0..<120 where laya == nil { try? await Task.sleep(for: .milliseconds(500)) }
        guard let laya else { return nil }
        var out = vibes
        for i in out.indices where out[i].topic == nil {
            let about = out[i].label + ": " + out[i].when // adding the story made the tags worse in a test on 20 vibes
            guard let a = try? await laya.answer(state: about, question: Scorer.topicQuestion) else { continue }
            out[i].topic = a.probabilities[a.selectedIndex] > 0.5 && a.selectedLabel != "other" ? a.selectedLabel : nil
        }
        return out
    }

    /// Laya picks the vibe that fits the summary of your last 30 minutes, from the shortlist. Nil without the model.
    /// ponytail: labels only; six labels take 38 of the 128 tokens and leave the summary whole, while adding each
    /// vibe's `when` (even cut to 4 words) pushes the summary out. A 256-token bucket would fit both.
    func pickVibe(_ candidates: [Vibe], summary: String) async -> Vibe? {
        guard let laya else { return nil }
        guard candidates.count > 1 else { return candidates.first }
        let question = LayaQuestion.choice("Which vibe fits this coding session best?", options: candidates.map(\.label))
        guard let a = try? await laya.answer(state: summary, question: question) else { return nil }
        return candidates[a.selectedIndex]
    }

    // MARK: Tuning

    private func labelsAreNewer() -> Bool {
        let date = { (url: URL) in (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate }
        guard let labels = date(Fuse.labelsURL) else { return false }
        return profile == nil || labels > (date(Fuse.profileURL) ?? .distantPast)
    }

    private var tuning = false

    /// Called when fuse/labels.json changes. Reads the rated messages from Claude Code's transcripts, asks Laya the
    /// probes, trains your personal fuse and your cool model on the same answers, and saves them. Message text is only
    /// ever in memory.
    func labelsChanged() { if laya != nil, labelsAreNewer() { tune() } }

    private func tune() {
        guard let laya, !tuning,
              let data = try? Data(contentsOf: Fuse.labelsURL) else { return }
        guard let labels = try? JSONDecoder().decode(FuseLabels.self, from: data) else { return report(.failed("labels.json isn't in the expected shape.")) }
        if let problem = labels.problems.first { return report(.failed(problem)) }
        tuning = true
        let report = report
        Task.detached(priority: .utility) {
            let known = Transcript.all(since: (labels.labels.map(\.ts).min() ?? 0) - 60)
            let bySession = Dictionary(grouping: known, by: \.sid)
            let matched = labels.labels.compactMap { l in bySession[l.sid]?.first { abs($0.ts - l.ts) < 1 }.map { (text: $0.text, heat: l.rating, cool: l.cool) } }
            guard matched.count >= 30 else {
                await MainActor.run { self.tuning = false; report(.failed("Only \(matched.count) of the rated messages were found. Run the setup prompt again.")) }
                return
            }
            var x: [[Double]] = [], y: [Int] = [], coolX: [[Double]] = [], coolY: [Int] = []
            for (i, m) in matched.enumerated() {
                if i % 10 == 0 { await MainActor.run { report(.tuning(done: i, of: matched.count)) } }
                guard let a = await Scorer.answers(laya, m.text, all: true) else { continue }
                let f = Scorer.features(a)
                x.append(f); y.append(m.heat)
                if let c = m.cool { coolX.append(f); coolY.append(c) }
            }
            let probes = Scorer.probes.map(\.name), made = Date().formatted(.iso8601.year().month().day())
            let fuse = PersonalFuse.train(features: x, ratings: y, probes: probes, rater: labels.rater, made: made)
            let cool = coolY.count >= 30 ? PersonalFuse.train(features: coolX, ratings: coolY, probes: probes, rater: labels.rater, made: made) : nil
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            if let cool { try? encoder.encode(cool).write(to: Fuse.coolURL) } else { try? FileManager.default.removeItem(at: Fuse.coolURL) }
            try? encoder.encode(fuse).write(to: Fuse.profileURL)
            await MainActor.run {
                self.profile = fuse
                self.coolProfile = cool
                self.tuning = false
                report(.tuned(fuse))
            }
        }
    }
}
