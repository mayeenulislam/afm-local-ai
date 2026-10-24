import XCTest
@testable import LocalAI

final class ObsidianMetadataParserTests: XCTestCase {
    private let parser = ObsidianMetadataParser()

    // MARK: - Frontmatter parsing

    func testNoFrontmatter() {
        let result = parser.parse("Just a regular note.\n\nNo frontmatter here.")
        XCTAssertTrue(result.frontmatter.isEmpty)
        XCTAssertEqual(result.bodyText, "Just a regular note.\n\nNo frontmatter here.")
        XCTAssertTrue(result.tags.isEmpty)
        XCTAssertTrue(result.wikilinks.isEmpty)
        XCTAssertTrue(result.aliases.isEmpty)
    }

    func testSimpleFrontmatter() {
        let text = """
        ---
        title: My Note
        author: Alice
        ---
        Body text here.
        """
        let result = parser.parse(text)
        XCTAssertEqual(result.frontmatter["title"], "My Note")
        XCTAssertEqual(result.frontmatter["author"], "Alice")
        XCTAssertEqual(result.bodyText, "Body text here.")
    }

    func testFrontmatterWithListTags() {
        let text = """
        ---
        tags: tag1, tag2
        ---
        Body.
        """
        let result = parser.parse(text)
        XCTAssertEqual(result.tags, ["tag1", "tag2"])
    }

    func testFrontmatterWithBracketedTags() {
        let text = """
        ---
        tags: [tag1, tag2, tag3]
        ---
        Body.
        """
        let result = parser.parse(text)
        XCTAssertEqual(result.tags, ["tag1", "tag2", "tag3"])
    }

    func testFrontmatterWithIndentedListTags() {
        let text = """
        ---
        tags:
        - tag-one
        - tag-two
        ---
        Body.
        """
        let result = parser.parse(text)
        XCTAssertEqual(result.tags, ["tag-one", "tag-two"])
    }

    func testFrontmatterWithAliases() {
        let text = """
        ---
        alias:
        - alias1
        - alias2
        ---
        Body.
        """
        let result = parser.parse(text)
        XCTAssertEqual(result.aliases, ["alias1", "alias2"])
    }

    func testFrontmatterWithAliasesBracketed() {
        let text = """
        ---
        aliases: [alias1, alias2]
        ---
        Body.
        """
        let result = parser.parse(text)
        XCTAssertEqual(result.aliases, ["alias1", "alias2"])
    }

    func testFrontmatterEmptyValue() {
        let text = """
        ---
        title:
        ---
        Body.
        """
        let result = parser.parse(text)
        XCTAssertNil(result.frontmatter["title"])
    }

    func testFrontmatterKeyWithoutColonNotParsed() {
        let text = """
        ---
        this is just text without colon
        ---
        Body.
        """
        let result = parser.parse(text)
        XCTAssertTrue(result.frontmatter.isEmpty)
        XCTAssertEqual(result.bodyText, "this is just text without colon\n\nBody.")
    }

    func testFrontmatterNoClosingDelimiter() {
        let text = """
        ---
        title: No closing
        This should be body.
        """
        let result = parser.parse(text)
        XCTAssertTrue(result.frontmatter.isEmpty)
        XCTAssertTrue(result.bodyText.contains("No closing"))
    }

    // MARK: - Inline tags

    func testInlineTags() {
        let result = parser.parse("#tag1 some text #tag2 more text")
        XCTAssertEqual(result.tags, ["tag1", "tag2"])
    }

    func testInlineTagAtStart() {
        let result = parser.parse("#project-name some content")
        XCTAssertEqual(result.tags, ["project-name"])
    }

    func testInlineTagNotAfterHashHeading() {
        let result = parser.parse("## Heading\n\n#body-tag content")
        XCTAssertEqual(result.tags, ["body-tag"])
    }

    func testInlineTagWithSlashes() {
        let result = parser.parse("text #tag/sub/value here")
        XCTAssertEqual(result.tags, ["tag/sub/value"])
    }

    func testNoTagInHashtagWordWithoutSeparator() {
        let result = parser.parse("check #1234 issue")
        XCTAssertFalse(result.tags.contains("1234"))
    }

    // MARK: - Wikilinks

    func testSimpleWikilinks() {
        let result = parser.parse("See [[SomeNote]] for details.")
        XCTAssertEqual(result.wikilinks, ["SomeNote"])
    }

    func testMultipleWikilinks() {
        let result = parser.parse("[[Note1]] and [[Note2]] and [[Note3]]")
        XCTAssertEqual(result.wikilinks, ["Note1", "Note2", "Note3"])
    }

    func testWikilinkWithAlias() {
        let result = parser.parse("[[TargetNote|Display Name]]")
        XCTAssertEqual(result.wikilinks, ["TargetNote"])
    }

    func testWikilinkWithHeading() {
        let result = parser.parse("[[Note#Section 1]]")
        XCTAssertEqual(result.wikilinks, ["Note"])
    }

    func testWikilinkWithBlock() {
        let result = parser.parse("[[Note^block-id]]")
        XCTAssertEqual(result.wikilinks, ["Note"])
    }

    func testWikilinkWithAliasAndHeading() {
        let result = parser.parse("[[Note#Section|Custom Name]]")
        XCTAssertEqual(result.wikilinks, ["Note"])
    }

    func testWikilinkDeduplicatedAndSorted() {
        let result = parser.parse("[[Zebra]] [[Apple]] [[Apple]] [[Zebra]]")
        XCTAssertEqual(result.wikilinks, ["Apple", "Zebra"])
    }

    // MARK: - Combined frontmatter + body

    func testFrontmatterTagsMergedWithInlineTags() {
        let text = """
        ---
        tags: [front-tag]
        ---
        #inline-tag body text
        """
        let result = parser.parse(text)
        XCTAssertEqual(result.tags, ["front-tag", "inline-tag"])
    }

    func testFrontmatterWikilinksFromBody() {
        let text = """
        ---
        title: Test
        ---
        See [[Link1]] and [[Link2]].
        """
        let result = parser.parse(text)
        XCTAssertEqual(result.wikilinks, ["Link1", "Link2"])
    }

    func testBodyTextStripped() {
        let text = """
        ---
        title: Test
        ---
          Trimmed body.  
        """
        let result = parser.parse(text)
        XCTAssertEqual(result.bodyText, "Trimmed body.")
    }

    // MARK: - ObsidianIndexAccumulator

    func testAccumulatorSummaryWithNoRecords() {
        let acc = ObsidianMetadataParser()
        var accumulator = ObsidianIndexAccumulator()
        XCTAssertNil(accumulator.summary)
    }

    func testAccumulatorSummaryWithRecords() {
        var accumulator = ObsidianIndexAccumulator()
        accumulator.record(ObsidianMetadata(frontmatter: [:], tags: ["alpha"], wikilinks: ["Note1"], aliases: [], bodyText: "body1"))
        accumulator.record(ObsidianMetadata(frontmatter: ["title": "x"], tags: ["alpha", "beta"], wikilinks: ["Note2"], aliases: [], bodyText: "body2"))
        accumulator.record(ObsidianMetadata(frontmatter: [:], tags: ["gamma"], wikilinks: ["Note1"], aliases: [], bodyText: "body3"))

        guard let summary = accumulator.summary else {
            XCTFail("Expected summary")
            return
        }

        XCTAssertEqual(summary.noteCount, 3)
        XCTAssertEqual(summary.frontmatterFieldCount, 1)
        XCTAssertEqual(summary.uniqueTags, ["alpha", "beta", "gamma"])
        XCTAssertEqual(summary.wikilinkCount, 3)
        XCTAssertEqual(summary.uniqueWikilinks, 2)
        XCTAssertEqual(summary.topTags, ["#alpha", "#beta", "#gamma"])
    }

    func testAccumulatorTopTagsByFrequency() {
        var accumulator = ObsidianIndexAccumulator()
        accumulator.record(ObsidianMetadata(frontmatter: [:], tags: ["common", "common", "common", "rare"], wikilinks: [], aliases: [], bodyText: ""))
        accumulator.record(ObsidianMetadata(frontmatter: [:], tags: ["rare"], wikilinks: [], aliases: [], bodyText: ""))

        guard let summary = accumulator.summary else {
            XCTFail("Expected summary")
            return
        }

        XCTAssertEqual(summary.topTags, ["#common", "#rare"])
    }
}
