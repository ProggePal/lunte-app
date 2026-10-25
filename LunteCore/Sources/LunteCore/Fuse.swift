// Your own fuse (contract §8): your AI rates your past messages once, for heat and for cool, and Lunte learns how
// Laya's answers add up to each for you. The files live in ~/Library/Application Support/Lunte/fuse, next to the log.
import Foundation

public enum Fuse {
    public static var dir: URL { EventLog.defaultURL.deletingLastPathComponent().appendingPathComponent("fuse") }
    public static var labelsURL: URL { dir.appendingPathComponent("labels.json") }
    public static var profileURL: URL { dir.appendingPathComponent("profile.json") }
    /// The cool model: a `PersonalFuse` trained on the cool ratings, absent when labels.json has none.
    public static var coolURL: URL { dir.appendingPathComponent("cool.json") }
    public static var vibesURL: URL { dir.appendingPathComponent("vibes.json") }

    /// The one prompt you paste into Claude Code. `lunte-hook setup` prints the rest (`setupText`). It never contains
    /// the test phrase, so pasting it can't Boom; your AI's last line tells you to type it.
    public static let setupPrompt = #"Let's set up Lunte. Look at my messages and tune the sensitivity and the vibes. Lunte's setup tool is at "$HOME/Library/Application Support/Lunte/lunte-hook": run it with setup for the steps. Let me know when you're done :)"#

    /// Messages for your AI to rate, oldest first: the latest the word list flags and the latest that look like banter
    /// (up to a third of `count` each), then an even spread of the rest, so there's temper, banter and calm to learn from.
    // Why: an even spread of a mostly plain history held 29 cool messages in 300, too few to learn cool from
    // (docs/why.md#cool-grows)
    public static func candidates(_ all: [Transcript.Message], count: Int = 300) -> [Transcript.Message] {
        let same = { (a: Transcript.Message, b: Transcript.Message) in a.ts == b.ts && a.sid == b.sid }
        let hot = Array(all.filter { [.tell, .lose].contains(Classifier.classify($0.text)) }.suffix(count / 3))
        let cool = Array(all.filter { m in Classifier.looksCool(m.text) && !hot.contains { same($0, m) } }.suffix(count / 3))
        let calm = all.filter { m in !(hot + cool).contains { same($0, m) } }
        let want = min(calm.count, count - hot.count - cool.count)
        let step = want > 0 ? Double(calm.count) / Double(want) : 1 // ponytail: an even spread, not random, so reruns agree
        let spread = (0..<want).map { calm[Int(Double($0) * step)] }
        return (hot + cool + spread).sorted { $0.ts < $1.ts }
    }

    public static let setupText = """
    # Set up a Lunte fuse

    Lunte is a menu bar game: a fuse burns when its owner loses their temper with their AI assistant, it grows back
    when they talk to it like a best bud, and it blows at the end. You are that assistant. Rate the owner's own
    messages to you twice, for heat and for cool, so Lunte can tune the fuse to them. Everything stays on this Mac;
    Lunte keeps only the ratings.

    1. List the messages to rate:

           "$HOME/Library/Application Support/Lunte/lunte-hook" messages

       One JSON object per line: {"sid", "ts", "text"}. About 300 messages from the last 60 days: the ones that look
       heated, the ones that look friendly, and an even spread of the rest. Long ones are cut short.

    2. Rate every message for heat, 0–3: how angry was the owner at the assistant? Heat means anger, not volume:
       capitals, swearing and !!! out of joy are 0 ("LETS GO", "lets fucking go", "faen så bra"), and sarcasm is heat
       ("great, you broke it again").

       - 0 calm: requests, questions, plain bug reports, pasted errors, happy or excited swearing
       - 1 irritated: impatient, correcting it, repeating themselves, a mild telling-off ("I said…", "jeg sa…", "no, not that")
       - 2 angry: clearly annoyed at the assistant, blaming it, sarcastic, harsh ("why did you delete that", "this is useless")
       - 3 furious: shouting in capitals, swearing at it, insulting it

    3. Rate every message again for cool, 0–3: how much does the owner talk to the assistant like their best bud?
       Cool is slang, banter, hype, nicknames, casual thanks and happy swearing. A formal "please" or "thank you" is 0,
       and so is a plain request.

       - 0 neutral: plain requests, questions, bug reports, polite or formal wording, anything without a buddy tone
       - 1 friendly: relaxed and warm, a casual "thx", "nice", a light joke
       - 2 buddy: slang, banter, nicknames, hype ("let's gooo", "legend", "nice one mate", "sykt bra, kompis")
       - 3 best bud: full banter or hype, roasting it with a laugh, happy swearing ("LETS FUCKING GO 🔥", "faen så rått")

       One message can be both: "you deleted my db AGAIN, you absolute clown 😂" is heat 2 and cool 3. Judge the tone
       toward the assistant, not the topic. Norwegian and English both occur. Rate every line, both times.

    4. Write the ratings to ~/Library/Application Support/Lunte/fuse/labels.json in exactly this shape, with sid and ts
       copied unchanged from step 1, "rating" for heat, "cool" for cool, and no message text:

           {"lunte": "fuse-labels", "v": 1, "rater": "<your model name>", "made": "<today as YYYY-MM-DD>",
            "labels": [{"sid": "…", "ts": 1792744463.009, "rating": 3, "cool": 0}, …]}

    5. Write about 20 personal vibes to ~/Library/Application Support/Lunte/fuse/vibes.json. A vibe names how a
       stretch of a session feels, in Lunte's voice: dry, understated, a bit British ("Running rather hot",
       "Firm but fair", "Suspiciously calm"). Base them on patterns you saw across the owner's chats: their kinds of
       work, hours, habits and pet peeves. Spread them over the bands: about 6 calm, 6 warm, 5 hot and 3 explosive.

           {"lunte": "fuse-vibes", "v": 1, "made": "<today as YYYY-MM-DD>", "vibes": [
             {"emoji": "🧯", "label": "Migration grief", "band": "hot", "topic": "code",
              "when": "the database keeps breaking and patience runs out",
              "story": "What began as a tidy rename slowly became a test of human patience."}, …]}

       - label: 2 to 4 words. emoji: one. when: when it fits, at most 12 words. story: one dry sentence, at most 15 words.
       - band: calm, warm, hot or explosive (explosive is right after the fuse blows).
       - topic: what the work is about when this vibe fits: code, design, writing, business, voice, shipping or ideas.
         Use "any" for vibes about mood, time or habits rather than a kind of work. A topic vibe only shows up when
         the session is about that topic.
       - About the mood, not the content: no quotes from messages, no names, nothing private.
       - Don't show the vibes to the owner. They're found by playing.

    6. Check both files, and fix anything it reports:

           "$HOME/Library/Application Support/Lunte/lunte-hook" check-fuse

    7. Finish with one short line to the owner: how many messages you rated, that their vibes are set (without
       listing them), and that they should now type `3 2 1 pow` to light their tuned fuse. Lunte tunes itself as soon
       as the files appear.
    """
}

/// labels.json, written by your AI: a heat and a cool rating per message, by reference. No message text.
public struct FuseLabels: Codable, Equatable, Sendable {
    public struct Label: Codable, Equatable, Sendable {
        public var sid: String
        public var ts: Double
        /// Heat, 0–3.
        public var rating: Int
        /// Cool, 0–3. Nil in files from before cool.
        public var cool: Int? = nil
    }
    public var lunte: String
    public var v: Int
    public var rater: String?
    public var made: String?
    public var labels: [Label]

    /// What stops it tuning, or [] when it's fine. A file without cool still tunes heat; `check-fuse` also wants
    /// `missingCool` at 0.
    public var problems: [String] {
        var out: [String] = []
        if lunte != "fuse-labels" { out.append(#""lunte" must be "fuse-labels""#) }
        if v != 1 { out.append(#""v" must be 1"#) }
        let bad = labels.filter { !(0...3).contains($0.rating) }.count
        if bad > 0 { out.append("\(bad) ratings are outside 0–3") }
        let badCool = labels.filter { $0.cool.map { !(0...3).contains($0) } ?? false }.count
        if badCool > 0 { out.append("\(badCool) cool ratings are outside 0–3") }
        if labels.count < 30 { out.append("only \(labels.count) ratings; rate at least 30, ideally all of them") }
        return out
    }

    /// How many messages have no cool rating.
    public var missingCool: Int { labels.filter { $0.cool == nil }.count }
}

/// profile.json, written by Lunte: your personal layer on top of Laya. A ridge regression over the log probabilities of
/// Laya's answers to the probe questions, trained on your AI's 0–3 ratings, ranks how heated a message is. Your range
/// sets the scale: `cuts` are the scores your top irritated, angry and furious shares start at, and they map to heat
/// 1/3, 2/3 and 1. So if your AI rated 1% of your messages furious, scoring like your top 1% blows a fresh stick.
/// cool.json is the same model trained on the cool ratings: there, read heat as cool.
public struct PersonalFuse: Codable, Equatable, Sendable {
    public var v = 1
    /// The probe questions, in feature order. A profile only fits the probes it was trained with.
    public var probes: [String]
    public var mean: [Double]
    public var sd: [Double]
    public var weights: [Double]
    public var bias: Double
    /// The predicted rating where irritated, angry and furious begin for you; nil for a level you never reached.
    public var cuts: [Double?] = [nil, nil, nil]
    /// Your calm messages' median predicted rating: heat 0.
    public var floor: Double = 0
    public var lambda: Double
    public var trainedOn: Int
    /// How well it ranks irritated-or-worse above calm on messages it didn't train on (5-fold AUC), or nil without both.
    public var fit: Double?
    public var rater: String?
    public var made: String

    /// Heat 0...1 for one message's features: straight lines between floor 0, cuts 1/3, 2/3 and 1.
    public func heat(_ x: [Double]) -> Double {
        let r = rating(x)
        let anchors = [(floor, 0.0)] + cuts.enumerated().compactMap { c in c.element.map { ($0, Double(c.offset + 1) / 3) } }
        guard let top = anchors.last, r < top.0 else { return anchors.last?.1 ?? 0 }
        guard r > floor else { return 0 }
        let i = anchors.firstIndex { r < $0.0 }!
        let (a, b) = (anchors[i - 1], anchors[i])
        return b.0 > a.0 ? a.1 + (r - a.0) / (b.0 - a.0) * (b.1 - a.1) : b.1
    }

    /// The predicted 0–3 rating, unclamped.
    func rating(_ x: [Double]) -> Double {
        zip(zip(x, mean), zip(sd, weights)).reduce(bias) { $0 + ($1.0.0 - $1.0.1) / $1.1.0 * $1.1.1 }
    }

    static let lambdas = [0.01, 0.03, 0.1, 0.3, 1, 3]

    /// Picks the regularisation by 5-fold cross-validation, then trains on everything.
    public static func train(features: [[Double]], ratings: [Int], probes: [String], rater: String?, made: String) -> PersonalFuse {
        var best: (fit: Double?, lambda: Double) = (nil, 1)
        for lambda in lambdas {
            let fit = crossValidated(features, ratings, lambda: lambda)
            if let f = fit, f >= (best.fit ?? -1) { best = (f, lambda) }
        }
        var model = fitRidge(features, ratings, lambda: best.lambda)
        // Your range: each level's cut is the predicted score its share of your messages starts at.
        let predicted = features.map(model.rating).sorted()
        model.cuts = (1...3).map { level in
            let share = Double(ratings.filter { $0 >= level }.count) / Double(ratings.count)
            guard share > 0 else { return nil }
            return predicted[min(predicted.count - 1, Int((1 - share) * Double(predicted.count)))] as Double?
        }
        let calm = zip(features, ratings).filter { $0.1 == 0 }.map { model.rating($0.0) }.sorted()
        model.floor = min(calm.isEmpty ? 0 : calm[calm.count / 2], model.cuts[0] ?? .greatestFiniteMagnitude)
        model.probes = probes
        model.fit = best.fit
        model.rater = rater
        model.made = made
        return model
    }

    static func crossValidated(_ x: [[Double]], _ y: [Int], lambda: Double) -> Double? {
        var predicted = [Double](repeating: 0, count: y.count)
        for k in 0..<5 {
            let test = y.indices.filter { $0 % 5 == k }, train = y.indices.filter { $0 % 5 != k }
            guard !test.isEmpty, !train.isEmpty else { return nil }
            let m = fitRidge(train.map { x[$0] }, train.map { y[$0] }, lambda: lambda)
            for i in test { predicted[i] = m.rating(x[i]) }
        }
        return auc(predicted, positive: y.map { $0 >= 1 })
    }

    static func fitRidge(_ x: [[Double]], _ y: [Int], lambda: Double) -> PersonalFuse {
        let n = Double(y.count), d = x.first?.count ?? 0
        let mean = (0..<d).map { j in x.reduce(0) { $0 + $1[j] } / n }
        let sd = (0..<d).map { j in max(1e-6, sqrt(x.reduce(0) { $0 + pow($1[j] - mean[j], 2) } / n)) }
        let z = x.map { row in (0..<d).map { (row[$0] - mean[$0]) / sd[$0] } }
        let ybar = Double(y.reduce(0, +)) / n
        var a = (0..<d).map { i in (0..<d).map { j in z.reduce(0) { $0 + $1[i] * $1[j] } + (i == j ? lambda * n : 0) } }
        var b = (0..<d).map { i in zip(z, y).reduce(0) { $0 + $1.0[i] * (Double($1.1) - ybar) } }
        let w = solve(&a, &b)
        return PersonalFuse(probes: [], mean: mean, sd: sd, weights: w, bias: ybar, lambda: lambda, trainedOn: y.count, fit: nil, rater: nil, made: "")
    }

    /// Gaussian elimination with partial pivoting; the matrix is small (one row per probe answer) and positive definite.
    static func solve(_ a: inout [[Double]], _ b: inout [Double]) -> [Double] {
        let n = b.count
        for c in 0..<n {
            let p = (c..<n).max { abs(a[$0][c]) < abs(a[$1][c]) }!
            a.swapAt(c, p); b.swapAt(c, p)
            for r in (c + 1)..<max(c + 1, n) where a[c][c] != 0 {
                let f = a[r][c] / a[c][c]
                for k in c..<n { a[r][k] -= f * a[c][k] }
                b[r] -= f * b[c]
            }
        }
        var x = [Double](repeating: 0, count: n)
        for r in stride(from: n - 1, through: 0, by: -1) {
            let s = ((r + 1)..<n).reduce(b[r]) { $0 - a[r][$1] * x[$1] }
            x[r] = a[r][r] == 0 ? 0 : s / a[r][r]
        }
        return x
    }

    /// The chance a random positive scores above a random negative; nil without both.
    public static func auc(_ scores: [Double], positive: [Bool]) -> Double? {
        let pos = scores.indices.filter { positive[$0] }.map { scores[$0] }, neg = scores.indices.filter { !positive[$0] }.map { scores[$0] }
        guard !pos.isEmpty, !neg.isEmpty else { return nil }
        let wins = pos.reduce(0.0) { acc, p in acc + neg.reduce(0.0) { $0 + (p > $1 ? 1 : p == $1 ? 0.5 : 0) } }
        return wins / Double(pos.count * neg.count)
    }
}
