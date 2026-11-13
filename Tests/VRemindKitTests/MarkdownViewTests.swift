import AppKit
import Foundation
import SwiftUI
import Testing
@testable import VRemindKit

struct MarkdownViewTests {
    @Test func testParsesHeadingsParagraphsBulletsAndDividers() {
        let md = """
        # v1.1 — The Native Desktop Release

        What started as a vibecoded app
        has evolved.

        ### Highlights & What's New
        - Native widgets
        * Menu bar popover

        ---
        """

        let blocks = MarkdownParser.parse(md)
        #expect(blocks == [
            .heading(level: 1, text: "v1.1 — The Native Desktop Release"),
            .paragraph(text: "What started as a vibecoded app has evolved."),
            .heading(level: 3, text: "Highlights & What's New"),
            .bullet(text: "Native widgets"),
            .bullet(text: "Menu bar popover"),
            .divider
        ])
    }

    @Test func testParsesMarkdownAndGitHubHTMLImages() {
        let md = """
        #### 🎨 Native macOS Desktop Widgets

        <img width="759" height="732" alt="widgets" src="https://github.com/user-attachments/assets/87bcf9de-91cc-4c98-85a1-e344d591f90d" />

        ![preview](https://example.com/preview.png)
        """

        let blocks = MarkdownParser.parse(md)
        #expect(blocks == [
            .heading(level: 4, text: "🎨 Native macOS Desktop Widgets"),
            .image(
                url: URL(string: "https://github.com/user-attachments/assets/87bcf9de-91cc-4c98-85a1-e344d591f90d")!,
                alt: "widgets"
            ),
            .image(
                url: URL(string: "https://example.com/preview.png")!,
                alt: "preview"
            )
        ])
    }

    @Test func testParsesCodeBlocks() {
        let md = """
        ```swift
        let x = 1
        ```
        """
        let blocks = MarkdownParser.parse(md)
        #expect(blocks == [.codeBlock(code: "let x = 1")])
    }

    @Test @MainActor func testMarkdownViewRendersInHostingController() {
        let view = MarkdownView(markdown: "# Title\n\n**Bold** and `code`.\n\n- Item 1")
        let controller = NSHostingController(rootView: view)
        #expect(controller.view.fittingSize.width >= 0)
    }

    @Test func testParsesSingleAndMultilineBlockquotes() {
        let single = MarkdownParser.parse("> yes, we're a version number late")
        #expect(single == [.blockquote(text: "yes, we're a version number late")])

        let multiline = MarkdownParser.parse("""
        >Line 1
        > Line 2
        >
        > Second para
        """)
        #expect(multiline == [.blockquote(text: "Line 1 Line 2\n\nSecond para")])
    }

    @Test func testParsesNestedBulletsNumberedListsAndTaskItems() {
        let md = """
        - Top
          - Child
            * Grandchild
        1. First
        2. Second
        - [ ] Todo
        - [x] Done
        """
        let blocks = MarkdownParser.parse(md)
        #expect(blocks == [
            .bullet(text: "Top"),
            .nestedBullet(indent: 1, text: "Child"),
            .nestedBullet(indent: 2, text: "Grandchild"),
            .numberedList(index: 1, text: "First"),
            .numberedList(index: 2, text: "Second"),
            .taskItem(checked: false, text: "Todo"),
            .taskItem(checked: true, text: "Done")
        ])
    }

    @Test func testParsesGFMTables() {
        let md = """
        | Platform | Keyless |
        | :--- | :---: |
        | YouTube | Yes |
        | Twitch | Yes |
        """
        let blocks = MarkdownParser.parse(md)
        #expect(blocks == [
            .table(
                headers: ["Platform", "Keyless"],
                rows: [
                    ["YouTube", "Yes"],
                    ["Twitch", "Yes"]
                ]
            )
        ])
    }

    @Test func testParsesVideoTagsAndDistinguishesGitHubAssetURLs() {
        let md = """
        <video src="https://github.com/user-attachments/assets/abc-123" controls></video>

        <video controls muted>
          <source src="https://example.com/demo.mp4" type="video/mp4">
        </video>

        ![clip](https://example.com/clip.mov?raw=true)

        [watch](https://example.com/clip.m4v)

        [webm](https://example.com/clip.webm)

        https://github.com/user-attachments/assets/def-456

        [![badge](https://example.com/badge.png)](https://example.com)
        """
        let blocks = MarkdownParser.parse(md)
        #expect(blocks == [
            .video(url: URL(string: "https://github.com/user-attachments/assets/abc-123")!, alt: nil),
            .video(url: URL(string: "https://example.com/demo.mp4")!, alt: nil),
            .video(url: URL(string: "https://example.com/clip.mov?raw=true")!, alt: "clip"),
            .video(url: URL(string: "https://example.com/clip.m4v")!, alt: "watch"),
            .paragraph(text: "[webm](https://example.com/clip.webm)"),
            .paragraph(text: "https://github.com/user-attachments/assets/def-456"),
            .image(url: URL(string: "https://example.com/badge.png")!, alt: "badge")
        ])
    }

    @Test @MainActor func testRendersExtendedMarkdownBlocksInHostingController() {
        let md = """
        # Release 1.3.1

        > Quoted note<br>with break

        - Top
          - Nested
        1. First
        - [ ] Open
        - [x] Closed

        | Col A | Col B |
        | --- | --- |
        | 1 | 2 |

        ```swift
        let a = 1
        ```

        ---

        https://example.com/bare-link
        """
        let view = MarkdownView(markdown: md)
        let controller = NSHostingController(rootView: view)
        #expect(controller.view.fittingSize.width >= 0)
    }
}
