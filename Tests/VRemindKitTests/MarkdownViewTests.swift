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
}
