// Prompt -> Burn (contract §3). Case-insensitive, Unicode word boundaries, ``` blocks ignored.
import Foundation

public enum Classifier {
    public static func classify(_ prompt: String) -> Burn {
        let text = prompt.replacingOccurrences(of: "(?s)```.*?(```|$)", with: " ", options: .regularExpression)
            .precomposedStringWithCanonicalMapping // so "rått" matches however å was typed
        if text.range(of: "(?<![0-9])3\\W*2\\W*1\\W*pow(?!\(wordChar))", options: [.regularExpression, .caseInsensitive]) != nil {
            return .test // the onboarding phrase: "this is a test 3 2 1 pow"
        }
        let happy = has(happyWords, in: text)
        if has(losePhrases, in: text) { return .lose }
        if !happy && (has(swears, in: text) || hasCaps(text) || text.range(of: "!!|\\?!|!\\?", options: .regularExpression) != nil) {
            return .lose
        }
        if has(tellPhrases, in: text) { return .tell }
        return .none
    }

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

    /// Three all-caps words in a row ("I SAID DONT"), split by spaces or sentence punctuation, so MAX_RETRY_COUNT isn't one.
    // ponytail: a run of three acronyms ("ENV VAR PATH") also counts
    static func hasCaps(_ text: String) -> Bool {
        let w = "\\p{Lu}+(?:['’]\\p{Lu}+)*"
        let pattern = "(?<!\(wordChar))\(w)(?:[\\s,.;:!?]+\(w)){2}(?!\(wordChar))"
        return text.range(of: pattern, options: .regularExpression) != nil
    }
}
