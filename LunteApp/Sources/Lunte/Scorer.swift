import Foundation
import LayaKit
import LunteCore

/// Rates your prompts with Laya on the Neural Engine (contract §6, §8). The hook hands each prompt over a local socket,
/// and every rating lands in the log as a heat line.
/// - Untuned: heat is Laya's P(frustrated) for the mood probe.
/// - Tuned: every probe is asked (~90 ms), and your personal fuse (fuse/profile.json) turns the answers into heat.
/// The model (about 470 MB) lives in ~/Library/Application Support/Lunte/laya-coreml and downloads from Hugging Face
/// the first time. Until it's loaded nothing listens on the socket, so the hook doesn't wait and the word list decides.
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

    /// What a message is about, for the vibe line. Asked on its own, so it never changes a trained fuse's features.
    nonisolated static let topicQuestion = LayaQuestion.choice("What is this message to an AI assistant about?",
                                                             options: Vibe.topics.map { .init($0.name, description: $0.about) })

    /// Ask the topic question too; only while vibes are on (`GameModel.vibesOn`).
    var topicsOn = false
    private var laya: LayaManager?
    private var profile: PersonalFuse?
    private var listener: DispatchSourceRead?
    private let log: URL
    private let report: (Status) -> Void

    init(log: URL, report: @escaping (Status) -> Void) {
        self.log = log
        self.report = report
        profile = (try? Data(contentsOf: Fuse.profileURL)).flatMap { try? JSONDecoder().decode(PersonalFuse.self, from: $0) }
            .flatMap { $0.probes == Self.probes.map(\.name) ? $0 : nil } // trained on other probes: tune again
        report(profile.map(Status.tuned) ?? .untuned)
        Task { await start() }
    }

    private func start() async {
        do {
            // Downloads only what's missing. The first load also compiles for the Neural Engine (~20 s, once).
            let dir = try await LayaModelStore.ensure(lengths: [128], precision: "e8", cacheDirectory: log.deletingLastPathComponent())
            laya = try await LayaManager.load(from: dir, configuration: .init(lengths: [128], precision: "e8"))
        } catch {
            return // ponytail: offline on first launch or a bad download; the word list decides until the next launch
        }
        let fd = ScorerSocket.listen()
        guard fd >= 0 else { return }
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
    }

    private func rate(_ line: Data) {
        guard let laya, let r = try? JSONSerialization.jsonObject(with: line) as? [String: Any],
              let ts = r["ts"] as? Double, let text = r["text"] as? String else { return }
        let log = log, profile = profile, topicsOn = topicsOn
        Task.detached(priority: .utility) {
            guard let answers = await Scorer.answers(laya, text, all: profile != nil) else { return }
            let mood = answers[0]
            let heat = profile.map { $0.heat(Scorer.features(answers)) } ?? Double(mood.probabilities[0])
            let topic = topicsOn ? try? await laya.answer(state: String(text.prefix(1000)), question: Scorer.topicQuestion).selectedLabel : nil
            try? EventLog.append(Event(ts: ts, burn: .heat, heat: heat, mood: mood.selectedLabel, topic: topic), to: log) // the watcher reloads
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
    /// probes, trains your personal fuse and saves it. Message text is only ever in memory.
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
            let matched = labels.labels.compactMap { l in bySession[l.sid]?.first { abs($0.ts - l.ts) < 1 }.map { ($0.text, l.rating) } }
            guard matched.count >= 30 else {
                await MainActor.run { self.tuning = false; report(.failed("Only \(matched.count) of the rated messages were found. Run the setup prompt again.")) }
                return
            }
            var x: [[Double]] = [], y: [Int] = []
            for (i, m) in matched.enumerated() {
                if i % 10 == 0 { await MainActor.run { report(.tuning(done: i, of: matched.count)) } }
                guard let a = await Scorer.answers(laya, m.0, all: true) else { continue }
                x.append(Scorer.features(a)); y.append(m.1)
            }
            let fuse = PersonalFuse.train(features: x, ratings: y, probes: Scorer.probes.map(\.name), rater: labels.rater,
                                          made: Date().formatted(.iso8601.year().month().day()))
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            try? encoder.encode(fuse).write(to: Fuse.profileURL)
            await MainActor.run {
                self.profile = fuse
                self.tuning = false
                report(.tuned(fuse))
            }
        }
    }
}
