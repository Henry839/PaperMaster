import XCTest
@testable import PaperMasterShared

final class ReaderMarkdownViewTests: XCTestCase {
    func testDocumentParsesHeadingsListsQuotesAndCodeBlocks() {
        let document = ReaderMarkdownDocument(markdown: """
        # Heading

        Paragraph with **bold**, [a link](https://example.com), and `code`.

        - First item
        - Second item

        > Quoted _text_

        ```swift
        let value = 1
        ```
        """)

        XCTAssertEqual(
            document.blocks,
            [
                .heading(level: 1, text: "Heading"),
                .paragraph("Paragraph with **bold**, [a link](https://example.com), and `code`."),
                .unorderedList(["First item", "Second item"]),
                .blockquote("Quoted _text_"),
                .codeBlock(language: "swift", code: "let value = 1")
            ]
        )
        XCTAssertEqual(document.blocks[1].plainText, "Paragraph with bold, a link, and code.")
        XCTAssertEqual(document.blocks[3].plainText, "Quoted text")
    }

    func testInlineRendererPreservesFormattedContentText() {
        let rendered = ReaderMarkdownRenderer.attributedText(
            from: "Text with **bold**, _italic_, [link](https://example.com), and `code`."
        )

        XCTAssertEqual(
            String(rendered.characters),
            "Text with bold, italic, link, and code."
        )
    }

    func testMalformedMarkdownFallsBackToSafeRenderableBlocks() {
        let document = ReaderMarkdownDocument(markdown: """
        ```swift
        let value = 1
        **still code**
        """)

        XCTAssertEqual(
            document.blocks,
            [
                .codeBlock(language: "swift", code: "let value = 1\n**still code**")
            ]
        )
        XCTAssertEqual(document.blocks.first?.plainText, "let value = 1\n**still code**")
    }
}
