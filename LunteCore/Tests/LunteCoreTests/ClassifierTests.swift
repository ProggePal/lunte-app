import XCTest
@testable import LunteCore

final class ClassifierTests: XCTestCase {
    // The contract §3 table, row for row.
    func testContractTable() {
        let rows: [(String, Burn)] = [
            ("this is still broken", .none),
            ("still broken wtf", .lose),
            ("fucking awesome, thanks!", .none),
            ("faen så bra", .none),
            ("tusen takk faen", .none),
            ("faen, det funker ikke", .lose),
            ("I SAID DONT TOUCH IT", .lose),
            ("no, why did you delete the tests", .tell),
            ("no, use the other table", .none),
            ("hvorfor gjorde du det?!", .lose),
            ("jeg sa ikke det", .tell),
            ("fix it:\n```\nError: build broken, wtf\n```", .none),
            ("amazing!!", .none),
            ("rename foo to bar", .none),
            ("hello shell", .none),
            ("what the hell are you doing", .lose),
            ("come on", .tell),
        ]
        for (prompt, burn) in rows { XCTAssertEqual(Classifier.classify(prompt), burn, prompt) }
    }

    // Machine-made prompts are cut out, so only what you typed can burn. These leaked as Booms on 22 Oct.
    func testHumanText() {
        let handback = "Another Claude session sent a message:\n<agent-message from=\"a7d0\">\n[Subagent hand-back] “WHY DID YOU DELETE MY MIGR…” wtf!!\n</agent-message>"
        XCTAssertEqual(Classifier.human(handback), "")
        XCTAssertEqual(Classifier.human("<task-notification>\n<task-id>a77d</task-id>\n<summary>why did you</summary>\n</task-notification>"), "")
        let midTurn = "<system-reminder>\nI SAID DONT TOUCH IT\n</system-reminder>\nmaybe the boom should come from the icon"
        XCTAssertEqual(Classifier.human(midTurn), "maybe the boom should come from the icon")
        XCTAssertEqual(Classifier.classify(Classifier.human(midTurn)), .none)
        XCTAssertEqual(Classifier.human("<agent-message from=\"x\">cut off mid-report, wtf"), "") // unclosed block
        XCTAssertEqual(Classifier.human("why did you <b>delete</b> it"), "why did you <b>delete</b> it")
    }

    // Word boundaries, Norwegian letters and a few near misses.
    func testEdges() {
        let rows: [(String, Burn)] = [
            ("du ødela alt", .tell),
            ("du ødelagte", .none),
            ("seriøst?", .lose),
            ("jævla tull", .lose),
            ("that’s wrong", .tell),
            ("you just deleted my file", .tell),
            ("set MAX_RETRY_COUNT to 5", .none),
            ("read dickens and bash scripts in the shell", .none),
            ("great, but this is useless", .lose),
            ("fix it\n```\nwtf\n", .none),
            ("", .none),
        ]
        for (prompt, burn) in rows { XCTAssertEqual(Classifier.classify(prompt), burn, prompt) }
    }
}
