// Prompt -> Burn (contract §3). Case-insensitive, Unicode word boundaries, ``` blocks ignored.
import Foundation

public enum Classifier {
    public static func classify(_ prompt: String) -> Burn {
        let text = clean(prompt)
        if has(testPhrase, in: text) { return .test } // the onboarding phrase: "3 2 1 boom" (or "pow", as it used to be)
        let happy = has(happyWords, in: text)
        if has(losePhrases, in: text) || (!happy && has(swears, in: text)) { return .lose }
        // Why: heat is anger, not volume; !! and CAPS only turn a telling-off up (docs/why.md#heat-not-volume)
        if has(tellPhrases, in: text) { return !happy && (hasCaps(text) || hasBangs(text)) ? .lose : .tell }
        return .none
    }

    /// Why a prompt got its Burn, for display only: ["told off: why did you", "swear", "CAPS"].
    public static func signals(_ prompt: String) -> [String] {
        let text = clean(prompt)
        if has(testPhrase, in: text) { return ["the onboarding phrase"] }
        let happy = first(happyWords, in: text)
        let but = happy == nil ? "" : ", but happy"
        var out: [String] = []
        if let m = first(losePhrases, in: text) { out.append("lost it: " + m.lowercased()) }
        if has(swears, in: text) { out.append("swear" + but) }
        if hasCaps(text) { out.append("CAPS" + but) }
        if hasBangs(text) { out.append("!!" + but) }
        if let m = first(tellPhrases, in: text) { out.append("told off: " + m.lowercased()) }
        if let happy { out.append("happy: " + happy.lowercased()) }
        return out
    }

    /// The part of a prompt a human typed. Claude Code also submits subagent hand-backs, task notifications and
    /// system reminders as prompts, sometimes glued to a message typed mid-turn, and the app adds what you pasted,
    /// image paths, what's on an open artifact, its PR instructions and its "please continue" notes. All of those are
    /// cut out: none of it is your tone.
    public static func human(_ prompt: String) -> String {
        prompt.replacingOccurrences(of: "(?s)<(task-notification|agent-message|system-reminder|local-command-\\w+|pasted_content|artifact-view-context|create-pr-command)\\b[^>]*>.*?(</\\1>|$)",
                                    with: " ", options: .regularExpression)
            .replacingOccurrences(of: "\\[Image(?: #\\d+|: source: [^\\]]*)\\]", with: " ", options: .regularExpression)
            .replacingOccurrences(of: "[^.\\n]* while you were working\\. Please continue from where you left off\\.", with: " ", options: .regularExpression)
            .replacingOccurrences(of: "Another Claude session sent a message:", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Looks like banter at a glance: a happy word, slang, a laugh or an emoji. It only picks messages for your AI to
    /// rate at setup (`Fuse.candidates`), so a miss costs nothing; it never scores one.
    public static func looksCool(_ prompt: String) -> Bool {
        let text = clean(prompt)
        return has(happyWords, in: text) || has(buddyWords, in: text) || text.range(of: "\\p{Extended_Pictographic}", options: .regularExpression) != nil
    }

    /// A prompt with its swears starred out past their first letter ("WHY THE F*** DID YOU"), for display, so a
    /// screenshot of it is safe to post.
    // Why: the session card is the screenshot (docs/why.md#session-story)
    public static func bleep(_ prompt: String) -> String {
        let out = NSMutableString(string: prompt)
        let swear = try! NSRegularExpression(pattern: swears, options: .caseInsensitive)
        for m in swear.matches(in: prompt, range: NSRange(location: 0, length: out.length)).reversed() { // back to front, so earlier ranges hold
            let word = out.substring(with: m.range)
            out.replaceCharacters(in: m.range, with: word.prefix(1) + String(repeating: "*", count: word.count - 1))
        }
        return out as String
    }

    static func clean(_ prompt: String) -> String {
        prompt.replacingOccurrences(of: "(?s)```.*?(```|$)", with: " ", options: .regularExpression)
            .precomposedStringWithCanonicalMapping // so "rått" matches however å was typed
    }

    static func first(_ pattern: String, in text: String) -> String? {
        text.range(of: pattern, options: [.regularExpression, .caseInsensitive]).map { String(text[$0]) }
    }

    static let testPhrase = "(?<![0-9])3\\W*2\\W*1\\W*(?:boom|pow)(?!\(wordChar))"

    // Pattern mini-language: a space is any whitespace, a trailing * is "any word ending", ' is either apostrophe.
    static let swears = words("fuck* shit* bitch* damn* crap* asshole* bastard* dick piss* bollocks wtf ffs omfg hell faen* helvete hælvete jævl* dritt* satan kuk pikk")
    static let losePhrases = phrases(["useless", "stupid", "are you kidding", "what the hell", "herregud", "seriøst"])
    static let tellPhrases = phrases([
        "i said", "i told you", "i already said", "i asked you", "why did you", "why would you", "why are you",
        "you (just )?(broke|deleted|ignored|removed)", "not what i (asked|said|wanted)", "that's wrong", "that's not it",
        "stop (it|that|doing)", "come on", "seriously", "ugh", "argh",
        "jeg sa", "jeg har sagt", "hvorfor gjorde du", "hvorfor gjør du", "du slettet", "du ødela", "kom igjen",
    ])
    static let happyWords = phrases([
        "awesome", "amazing", "love", "perfect", "great", "nice", "cool", "sick", "wow", "insane", "let's go", "yay",
        "hell yeah", "thanks", "thank you", "thx", "appreciate", "legend", "bra", "digg", "rått", "takk", "nydelig", "herlig",
    ])
    static let buddyWords = phrases([
        "lol", "lmao", "haha*", "hehe*", "bro", "dude", "mate", "buddy", "kompis", "lets go*", "let's go*", "lets fucking go*", "let's fucking go*", "lfg", "gg",
        "goat*", "banger", "well done", "good job", "nice one", "you rock", "sykt", "nais", "bra jobba",
    ])

    static let wordChar = "[\\p{L}\\p{M}\\p{N}_]"

    static func words(_ list: String) -> String { phrases(list.split(separator: " ").map(String.init)) }

    /// One alternation, anchored on Unicode word boundaries.
    static func phrases(_ list: [String]) -> String {
        let alts = list.map {
            $0.replacingOccurrences(of: " ", with: "\\s+")
                .replacingOccurrences(of: "'", with: "['’]")
                .replacingOccurrences(of: "*", with: "\(wordChar)*")
        }
        return "(?<!\(wordChar))(?:\(alts.joined(separator: "|")))(?!\(wordChar))"
    }

    static func has(_ pattern: String, in text: String) -> Bool {
        text.range(of: pattern, options: [.regularExpression, .caseInsensitive]) != nil
    }

    /// `!!`, `?!` or `!?`.
    static func hasBangs(_ text: String) -> Bool { text.range(of: "!!|\\?!|!\\?", options: .regularExpression) != nil }

    /// Three all-caps words in a row ("I SAID DONT"), split by spaces or sentence punctuation, so MAX_RETRY_COUNT isn't one.
    // ponytail: a run of three acronyms ("ENV VAR PATH") also counts
    static func hasCaps(_ text: String) -> Bool {
        let w = "\\p{Lu}+(?:['’]\\p{Lu}+)*"
        let pattern = "(?<!\(wordChar))\(w)(?:[\\s,.;:!?]+\(w)){2}(?!\(wordChar))"
        return text.range(of: pattern, options: .regularExpression) != nil
    }
}
