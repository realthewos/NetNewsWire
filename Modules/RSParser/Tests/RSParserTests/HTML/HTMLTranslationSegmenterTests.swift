//
//  HTMLTranslationSegmenterTests.swift
//  RSParser
//
//  Created by OpenAI on 4/30/26.
//

import Foundation
import Testing
import RSParser

@Suite struct HTMLTranslationSegmenterTests {

	@Test func simpleParagraphsProduceStableIDsAndText() {
		let html = "<article><p>First paragraph.</p><p>Second paragraph.</p></article>"

		let document = HTMLTranslationSegmenter.segment(html)

		#expect(document.html == html)
		#expect(document.segments == [
			HTMLTranslationSegment(id: "body-0001-e1e2c623", kind: .body, text: "First paragraph."),
			HTMLTranslationSegment(id: "body-0002-633e7c27", kind: .body, text: "Second paragraph.")
		])
	}

	@Test func visibleLinkTextIncludedAndHrefUntouched() {
		let html = #"<p>Read <a href="/search?q=swift&amp;page=2">the full story</a>.</p>"#

		let document = HTMLTranslationSegmenter.segment(html)

		#expect(document.html == html)
		#expect(document.segments == [
			HTMLTranslationSegment(id: "body-0001-6e20ab64", kind: .body, text: "Read the full story.")
		])
	}

	@Test func preCodeScriptAndStyleAreSkipped() {
		let html = """
		<p>Visible text.</p>
		<pre>Preformatted text.</pre>
		<code>Inline code.</code>
		<script><p>Script text.</p></script>
		<style>p { content: "Style text."; }</style>
		<p>More visible text.</p>
		"""

		let document = HTMLTranslationSegmenter.segment(html)

		#expect(document.segments.map(\.text) == ["Visible text.", "More visible text."])
	}

	@Test func mediaOnlyBlocksAreSkipped() {
		let html = """
		<p><img src="image.jpg" alt="Do not translate alt"></p>
		<figure><picture><source srcset="image.webp"><img src="image.jpg"></picture></figure>
		<p>Caption candidate.</p>
		"""

		let document = HTMLTranslationSegmenter.segment(html)

		#expect(document.segments.map(\.text) == ["Caption candidate."])
	}

	@Test func entitiesAreDecodedForSegmentText() {
		let html = "<p>Tom &amp; Jerry &lt; Friends &gt; Everyone</p>"

		let document = HTMLTranslationSegmenter.segment(html)

		#expect(document.segments == [
			HTMLTranslationSegment(id: "body-0001-8ccc21bf", kind: .body, text: "Tom & Jerry < Friends > Everyone")
		])
	}

	@Test func duplicateParagraphsGetDifferentOrdinalIDs() {
		let html = "<p>Repeat</p><p>Repeat</p>"

		let document = HTMLTranslationSegmenter.segment(html)

		#expect(document.segments == [
			HTMLTranslationSegment(id: "body-0001-06626d4a", kind: .body, text: "Repeat"),
			HTMLTranslationSegment(id: "body-0002-06626d4a", kind: .body, text: "Repeat")
		])
	}

	@Test func reinsertionPreservesOriginalAndEscapesTranslation() {
		let html = #"<p class="lede">First paragraph.</p><p>Second paragraph.</p>"#
		let translated = HTMLTranslationSegmenter.htmlByAddingTranslations(to: html, translations: [
			"body-0001-e1e2c623": #"<script>alert("owned")</script> & safe"#
		])

		#expect(translated == #"<p class="lede">First paragraph.</p><div class="nnw-translation" data-nnw-translation-id="body-0001-e1e2c623">&lt;script&gt;alert(&quot;owned&quot;)&lt;/script&gt; &amp; safe</div><p>Second paragraph.</p>"#)
	}

	@Test func missingTranslationLeavesOriginalUnchanged() {
		let html = "<p>First paragraph.</p><p>Second paragraph.</p>"

		let translated = HTMLTranslationSegmenter.htmlByAddingTranslations(to: html, translations: [
			"body-9999-missing": "Ignored translation."
		])

		#expect(translated == html)
	}
}
