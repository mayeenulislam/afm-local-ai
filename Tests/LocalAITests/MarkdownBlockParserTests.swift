import XCTest
@testable import LocalAI

final class MarkdownBlockParserTests: XCTestCase {

    // MARK: - ChatMarkdownFormatter.polish

    func testPolishEmptyString() {
        XCTAssertEqual(ChatMarkdownFormatter.polish(""), "")
        XCTAssertEqual(ChatMarkdownFormatter.polish("   \n  \t "), "")
    }

    func testPolishPlainMarkdownUnchanged() {
        let input = "# Heading\n\nSome paragraph text."
        XCTAssertEqual(ChatMarkdownFormatter.polish(input), input)
    }

    func testPolishAlreadyHasCodeBlockUnchanged() {
        let input = "```swift\nfunc hello() {}\n```"
        XCTAssertEqual(ChatMarkdownFormatter.polish(input), input)
    }

    func testPolishAlreadyHasHeadingUnchanged() {
        let input = "# My Title\n\nText"
        XCTAssertEqual(ChatMarkdownFormatter.polish(input), input)
    }

    func testPolishWrapsCodeSignalsInFence() {
        let input = "func hello() {\n    return 42\n}\nprint(hello())"
        let result = ChatMarkdownFormatter.polish(input)
        XCTAssertTrue(result.hasPrefix("```text"))
        XCTAssertTrue(result.hasSuffix("```"))
        XCTAssertTrue(result.contains("func hello"))
    }

    func testPolishQuotedStringBecomesBlockquote() {
        let input = "\"This is a quoted response.\""
        let result = ChatMarkdownFormatter.polish(input)
        XCTAssertTrue(result.hasPrefix("> "))
        XCTAssertFalse(result.contains("\""))
    }

    func testPolishSingleLinePlainTextUnchanged() {
        let input = "A simple answer."
        XCTAssertEqual(ChatMarkdownFormatter.polish(input), input)
    }

    func testPolishMultilineWithoutCodeSignalsUnchanged() {
        let input = "First paragraph here.\n\nSecond paragraph here."
        XCTAssertEqual(ChatMarkdownFormatter.polish(input), input)
    }

    func testPolishCalloutUnchanged() {
        let input = "> [!NOTE]\n> This is a note."
        XCTAssertEqual(ChatMarkdownFormatter.polish(input), input)
    }

    // MARK: - ChatMarkdownFormatter.chatFriendly

    func testChatFriendlyStripsLeadingHeadingSingleParagraph() {
        let input = "# My Answer\n\nThis is the response body."
        let result = ChatMarkdownFormatter.chatFriendly(input)
        XCTAssertEqual(result, "This is the response body.")
    }

    func testChatFriendlyKeepsHeadingForMultiSection() {
        let input = "# Title\n\nPara one.\n\n| Col |\n\n---|\n\nMore."
        let result = ChatMarkdownFormatter.chatFriendly(input)
        XCTAssertEqual(result, input)
    }

    func testChatFriendlyNoHeadingReturnsUnchanged() {
        let input = "Just a plain response."
        XCTAssertEqual(ChatMarkdownFormatter.chatFriendly(input), input)
    }

    func testChatFriendlySkipsBlankLinesBetweenHeadingAndBody() {
        let input = "# Title\n\n\n\nBody text here."
        let result = ChatMarkdownFormatter.chatFriendly(input)
        XCTAssertEqual(result, "Body text here.")
    }

    func testChatFriendlyKeepsContentWithTable() {
        let input = "# Summary\n\n| A | B |\n|---|---|\n| 1 | 2 |"
        let result = ChatMarkdownFormatter.chatFriendly(input)
        XCTAssertEqual(result, input)
    }

    func testChatFriendlyKeepsContentWithCodeBlock() {
        let input = "# Code\n\n```swift\nlet x = 1\n```"
        let result = ChatMarkdownFormatter.chatFriendly(input)
        XCTAssertEqual(result, input)
    }

    func testChatFriendlyKeepsContentWithList() {
        let input = "# Notes\n\n- item one\n- item two"
        let result = ChatMarkdownFormatter.chatFriendly(input)
        XCTAssertEqual(result, input)
    }

    // MARK: - MarkdownBlockParser.parse

    func testParseHeading() {
        let result = MarkdownBlockParser.parse("# My Heading")
        XCTAssertEqual(result.count, 1)
        guard case .heading(let level, let text) = result[0] else {
            XCTFail("Expected heading")
            return
        }
        XCTAssertEqual(level, 1)
        XCTAssertEqual(text, "My Heading")
    }

    func testParseHeadingLevels() {
        let levels = MarkdownBlockParser.parse("## Two\n\n#### Four")
        guard case .heading(let l1, _) = levels[0] else { XCTFail(); return }
        guard case .heading(let l2, _) = levels[1] else { XCTFail(); return }
        XCTAssertEqual(l1, 2)
        XCTAssertEqual(l2, 4)
    }

    func testParseEmptyInput() {
        let result = MarkdownBlockParser.parse("")
        XCTAssertTrue(result.isEmpty)
    }

    func testParseBlankLinesSkipped() {
        let result = MarkdownBlockParser.parse("\n\n\n# Heading\n\n\n")
        XCTAssertEqual(result.count, 1)
    }

    func testParseParagraph() {
        let result = MarkdownBlockParser.parse("A simple paragraph.")
        XCTAssertEqual(result.count, 1)
        guard case .paragraph(let text) = result[0] else {
            XCTFail("Expected paragraph")
            return
        }
        XCTAssertEqual(text, "A simple paragraph.")
    }

    func testParseMultilineParagraph() {
        let result = MarkdownBlockParser.parse("Line one.\nLine two.\nLine three.")
        XCTAssertEqual(result.count, 1)
        guard case .paragraph(let text) = result[0] else {
            XCTFail("Expected paragraph")
            return
        }
        XCTAssertEqual(text, "Line one.\nLine two.\nLine three.")
    }

    func testParseUnorderedListDash() {
        let result = MarkdownBlockParser.parse("- item 1\n- item 2\n- item 3")
        XCTAssertEqual(result.count, 1)
        guard case .unordered(let items) = result[0] else {
            XCTFail("Expected unordered list")
            return
        }
        XCTAssertEqual(items, ["item 1", "item 2", "item 3"])
    }

    func testParseUnorderedListStar() {
        let result = MarkdownBlockParser.parse("* item 1\n* item 2")
        guard case .unordered(let items) = result[0] else { XCTFail(); return }
        XCTAssertEqual(items, ["item 1", "item 2"])
    }

    func testParseUnorderedListPlus() {
        let result = MarkdownBlockParser.parse("+ item 1\n+ item 2")
        guard case .unordered(let items) = result[0] else { XCTFail(); return }
        XCTAssertEqual(items, ["item 1", "item 2"])
    }

    func testParseOrderedListDot() {
        let result = MarkdownBlockParser.parse("1. first\n2. second\n3. third")
        guard case .ordered(let items) = result[0] else { XCTFail(); return }
        XCTAssertEqual(items, ["first", "second", "third"])
    }

    func testParseOrderedListParen() {
        let result = MarkdownBlockParser.parse("1) first\n2) second")
        guard case .ordered(let items) = result[0] else { XCTFail(); return }
        XCTAssertEqual(items, ["first", "second"])
    }

    func testParseCodeBlock() {
        let result = MarkdownBlockParser.parse("```swift\nfunc hello() {}\n```")
        XCTAssertEqual(result.count, 1)
        guard case .code(let content) = result[0] else {
            XCTFail("Expected code block")
            return
        }
        XCTAssertEqual(content, "func hello() {}")
    }

    func testParseCodeBlockWithLanguage() {
        let result = MarkdownBlockParser.parse("```python\ndef hello():\n    pass\n```")
        guard case .code(let content) = result[0] else { XCTFail(); return }
        XCTAssertEqual(content, "def hello():\n    pass")
    }

    func testParseBlockquote() {
        let result = MarkdownBlockParser.parse("> This is a quote.\n> Second line.")
        XCTAssertEqual(result.count, 1)
        guard case .quote(let text) = result[0] else {
            XCTFail("Expected quote")
            return
        }
        XCTAssertEqual(text, "This is a quote.\nSecond line.")
    }

    func testParseCallout() {
        let result = MarkdownBlockParser.parse("> [!NOTE]\n> This is a note.\n> Second line.")
        XCTAssertEqual(result.count, 1)
        guard case .callout(let kind, let text) = result[0] else {
            XCTFail("Expected callout")
            return
        }
        XCTAssertEqual(kind, "NOTE")
        XCTAssertEqual(text, "This is a note.\nSecond line.")
    }

    func testParseDividerDashes() {
        let result = MarkdownBlockParser.parse("---")
        XCTAssertEqual(result.count, 1)
        guard case .divider = result[0] else {
            XCTFail("Expected divider")
            return
        }
    }

    func testParseDividerStars() {
        let result = MarkdownBlockParser.parse("***")
        XCTAssertEqual(result.count, 1)
        guard case .divider = result[0] else { XCTFail(); return }
    }

    func testParseDividerUnderscores() {
        let result = MarkdownBlockParser.parse("___")
        XCTAssertEqual(result.count, 1)
        guard case .divider = result[0] else { XCTFail(); return }
    }

    func testParseTableBlock() {
        let input = "| A | B |\n|---|---|\n| 1 | 2 |"
        let result = MarkdownBlockParser.parse(input)
        XCTAssertEqual(result.count, 1)
        guard case .table(let header, let rows) = result[0] else {
            XCTFail("Expected table block")
            return
        }
        XCTAssertEqual(header, ["A", "B"])
        XCTAssertEqual(rows, [["1", "2"]])
    }

    func testParseTableMultipleRows() {
        let input = "| Category | Stiletto | Wedge |\n|---|---|---|\n| Stability | Low | High |\n| Comfort | Low | High |"
        let result = MarkdownBlockParser.parse(input)
        XCTAssertEqual(result.count, 1)
        guard case .table(let header, let rows) = result[0] else {
            XCTFail("Expected table block")
            return
        }
        XCTAssertEqual(header, ["Category", "Stiletto", "Wedge"])
        XCTAssertEqual(rows, [["Stability", "Low", "High"], ["Comfort", "Low", "High"]])
    }

    func testParseTableAlignmentsStripped() {
        let input = "| A | B |\n|:---|--:|\n| 1 | 2 |"
        let result = MarkdownBlockParser.parse(input)
        guard case .table(let header, let rows) = result[0] else { XCTFail("Expected table"); return }
        XCTAssertEqual(header, ["A", "B"])
        XCTAssertEqual(rows, [["1", "2"]])
    }

    func testParseTableMissingSeparatorBecomesFragment() {
        let input = "| A | B |\n| 1 | 2 |"
        let result = MarkdownBlockParser.parse(input)
        XCTAssertEqual(result.count, 1)
        guard case .table(let header, let rows) = result[0] else {
            XCTFail("Expected table fragment for pipe-led lines without separator")
            return
        }
        XCTAssertEqual(header, ["A", "B"])
        XCTAssertEqual(rows, [["1", "2"]])
    }

    func testParseSingleLineTruncatedTableFragment() {
        let input = "| Feature | **Stiletto Pumps**"
        let result = MarkdownBlockParser.parse(input)
        XCTAssertEqual(result.count, 1)
        guard case .table(let header, let rows) = result[0] else {
            XCTFail("Expected header-only table from truncated single-line fragment")
            return
        }
        XCTAssertEqual(header, ["Feature", "**Stiletto Pumps**"])
        XCTAssertTrue(rows.isEmpty)
    }

    func testParsePipeLedLineWithSingleCellStaysParagraph() {
        let input = "| A note with a single cell"
        let result = MarkdownBlockParser.parse(input)
        XCTAssertEqual(result.count, 1)
        guard case .paragraph(let text) = result[0] else {
            XCTFail("Expected a lone pipe-led line to stay a paragraph")
            return
        }
        XCTAssertTrue(text.hasPrefix("| A note"))
    }

    func testParseTruncatedTableFragmentFollowedByParagraph() {
        let input = "| A | B |\nSome trailing note."
        let result = MarkdownBlockParser.parse(input)
        XCTAssertEqual(result.count, 2)
        guard case .table(let header, _) = result[0] else { XCTFail("Expected table fragment"); return }
        XCTAssertEqual(header, ["A", "B"])
        guard case .paragraph(let text) = result[1] else { XCTFail("Expected trailing paragraph"); return }
        XCTAssertEqual(text, "Some trailing note.")
    }

    func testParseIncompleteTableDuringStreaming() {
        let input = "| Category | Stiletto | Wedge |\n|---|---|---|"
        let result = MarkdownBlockParser.parse(input)
        XCTAssertEqual(result.count, 1)
        guard case .table(let header, let rows) = result[0] else {
            XCTFail("Expected table from partial stream")
            return
        }
        XCTAssertEqual(header, ["Category", "Stiletto", "Wedge"])
        XCTAssertTrue(rows.isEmpty)
    }

    func testParseTableSurroundedByOtherBlocks() {
        let input = "Intro\n\n| A | B |\n|---|---|\n| 1 | 2 |\n\nOutro"
        let result = MarkdownBlockParser.parse(input)
        XCTAssertEqual(result.count, 3)
        guard case .table = result[1] else { XCTFail("Expected table in middle"); return }
    }

    func testChatFriendlyNoHeading() {
        let input = "# Title\n\nJust text."
        XCTAssertEqual(ChatMarkdownFormatter.chatFriendly(input), "Just text.")
    }

    func testFootnoteDefinitionFallback() {
        let result = MarkdownBlockParser.parse("A paragraph.")
        guard case .paragraph(let text) = result[0] else { XCTFail(); return }
        XCTAssertEqual(text, "A paragraph.")
    }

    // MARK: - Empty model response handling

    func testNonBlankPreservesContent() {
        XCTAssertEqual(ChatMarkdownFormatter.nonBlankResponse("Hello."), "Hello.")
        XCTAssertEqual(ChatMarkdownFormatter.nonBlankResponse("  Trimmed.  "), "Trimmed.")
    }

    func testNonBlankEmptyBecomesFailureCallout() {
        for blank in ["", "   \n\t ", "\n\n\n"] {
            let result = ChatMarkdownFormatter.nonBlankResponse(blank)
            XCTAssertTrue(result.hasPrefix("> [!ERROR]"), "Blank input should produce a failure callout, got \(result)")
            XCTAssertFalse(result.contains("**Prompt**"))
        }
    }

    func testNonBlankResponseDoesNotCorruptFailedMarkers() {
        let callout = "> [!WARNING]\n> Something to note."
        XCTAssertEqual(ChatMarkdownFormatter.nonBlankResponse(callout), callout)
    }

    // MARK: - Truncated table cue

    func testTruncatedTableFragmentGetsWarningCue() {
        let input = "| Feature | **Stiletto Pump**"
        let cue = ChatMarkdownFormatter.truncatedTableCue(input)
        XCTAssertTrue(cue.contains("[!WARNING]"), "Truncated fragment should carry a warning cue, got \(cue)")
    }

    func testCompleteTableGetsNoCue() {
        let input = "| Orange | Norange |\n| :--- | :--- |\n| A citrus fruit. | A bright yellow fruit. |"
        XCTAssertEqual(ChatMarkdownFormatter.truncatedTableCue(input), "")
    }

    func testPlainMarkdownGetsNoCue() {
        XCTAssertEqual(ChatMarkdownFormatter.truncatedTableCue("Just a thought."), "")
        XCTAssertEqual(ChatMarkdownFormatter.truncatedTableCue(""), "")
    }

    func testParseFootnoteDefinition() {
        let result = MarkdownBlockParser.parse("[^note1]: This is a footnote.")
        XCTAssertEqual(result.count, 1)
        guard case .footnote(let label, let content) = result[0] else {
            XCTFail("Expected footnote")
            return
        }
        XCTAssertEqual(label, "note1")
        XCTAssertEqual(content, "This is a footnote.")
    }

    func testParseFootnoteMultiline() {
        let result = MarkdownBlockParser.parse("[^note1]: First line.\n  Second line.")
        guard case .footnote(_, let content) = result[0] else { XCTFail(); return }
        XCTAssertEqual(content, "First line.\nSecond line.")
    }

    func testParseMixedBlocks() {
        let input = "# Title\n\nA paragraph.\n\n- item 1\n- item 2\n\n```swift\ncode\n```"
        let result = MarkdownBlockParser.parse(input)
        XCTAssertEqual(result.count, 4)
        guard case .heading = result[0] else { XCTFail(); return }
        guard case .paragraph = result[1] else { XCTFail(); return }
        guard case .unordered = result[2] else { XCTFail(); return }
        guard case .code = result[3] else { XCTFail(); return }
    }

    func testParseBlockStartsAfterParagraph() {
        let input = "Some text.\n# Heading"
        let result = MarkdownBlockParser.parse(input)
        XCTAssertEqual(result.count, 2)
        guard case .paragraph = result[0] else { XCTFail(); return }
        guard case .heading = result[1] else { XCTFail(); return }
    }

    func testParseOrderedAfterUnordered() {
        let input = "- bullet\n\n1. numbered"
        let result = MarkdownBlockParser.parse(input)
        XCTAssertEqual(result.count, 2)
        guard case .unordered = result[0] else { XCTFail(); return }
        guard case .ordered = result[1] else { XCTFail(); return }
    }

    func testParseHeadingWithSpecialChars() {
        let result = MarkdownBlockParser.parse("# Title: A & B")
        guard case .heading(_, let text) = result[0] else { XCTFail(); return }
        XCTAssertEqual(text, "Title: A & B")
    }
}
