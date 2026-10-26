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
            ("it's still broken!!", .none),
            ("WHY IS IT STILL BROKEN", .none),
        ]
        for (prompt, burn) in rows { XCTAssertEqual(Classifier.classify(prompt), burn, prompt) }
    }

    /// Guards docs/why.md#heat-not-volume: `!!` and CAPS are volume. Alone they don't burn, and they only turn a
    /// telling-off into losing it. Swearing and telling off still count.
    func testBangsAndCapsAloneDontBurn() {
        let rows: [(String, Burn)] = [
            ("did it work?!", .none),
            ("NOT WORKING AGAIN", .none),
            ("STILL BROKEN!!", .none), // both, and nothing else
            ("stop it!!", .lose),
            ("I TOLD YOU so", .lose),
            ("stop it!! thanks", .tell), // happy: no turning up
            ("STILL BROKEN, SHIT", .lose),
            ("i said use the other table", .tell),
        ]
        for (prompt, burn) in rows { XCTAssertEqual(Classifier.classify(prompt), burn, prompt) }
        XCTAssertEqual(Classifier.signals("it's still broken!!"), ["!!"]) // still shown on hover
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
        // What the app adds isn't you either: a paste, an image, its own notes. An image path lit a Boom on 25 Oct.
        XCTAssertEqual(Classifier.human("why is this still broken <pasted_content id=\"a242\">\nFATAL: idiot\n</pasted_content>"), "why is this still broken")
        XCTAssertEqual(Classifier.human("[Image: source: /private/tmp/x/images/4.png]"), "")
        XCTAssertEqual(Classifier.human("same size please [Image #10]"), "same size please")
        XCTAssertEqual(Classifier.human("The app was quit while you were working. Please continue from where you left off."), "")
        XCTAssertEqual(Classifier.human("<create-pr-command>\n## Overview\n</create-pr-command>"), "")
    }

    /// Setup asks your AI to rate messages that look like banter, so the cool model has some to learn from.
    func testLooksCool() {
        for text in ["lets fucking go!", "nice one bro", "haha nailed it", "sykt bra 🔥", "good job on the close call"] {
            XCTAssertTrue(Classifier.looksCool(text), text)
        }
        for text in ["rename foo to bar", "automate the material", "fix the login bug", "add eggs"] {
            XCTAssertFalse(Classifier.looksCool(text), text)
        }
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
