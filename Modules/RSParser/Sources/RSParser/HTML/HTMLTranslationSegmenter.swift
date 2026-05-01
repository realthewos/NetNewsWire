//
//  HTMLTranslationSegmenter.swift
//  RSParser
//
//  Created by OpenAI on 4/30/26.
//

import Foundation

public struct HTMLTranslationSegment: Equatable, Sendable, Codable {

	public enum Kind: String, Sendable, Codable {
		case body
	}

	public let id: String
	public let kind: Kind
	public let text: String

	public init(id: String, kind: Kind, text: String) {
		self.id = id
		self.kind = kind
		self.text = text
	}
}

public struct HTMLTranslationSegmentedDocument: Equatable, Sendable {

	public let html: String
	public let segments: [HTMLTranslationSegment]

	public init(html: String, segments: [HTMLTranslationSegment]) {
		self.html = html
		self.segments = segments
	}
}

public enum HTMLTranslationSegmenter {

	public static func segment(_ html: String) -> HTMLTranslationSegmentedDocument {
		let parser = HTMLTranslationParser(html: html)
		return HTMLTranslationSegmentedDocument(html: html, segments: parser.parse().map(\.segment))
	}

	public static func htmlByAddingTranslations(to html: String, translations: [String: String]) -> String {
		guard !translations.isEmpty else {
			return html
		}

		let parser = HTMLTranslationParser(html: html)
		let insertions = parser.parse().compactMap { parsedSegment -> HTMLTranslationInsertion? in
			guard let endOffset = parsedSegment.endOffset, let translation = translations[parsedSegment.segment.id] else {
				return nil
			}
			return HTMLTranslationInsertion(offset: endOffset, html: translationHTML(id: parsedSegment.segment.id, text: translation))
		}

		guard !insertions.isEmpty else {
			return html
		}

		let bytes = Array(html.utf8)
		var output = [UInt8]()
		output.reserveCapacity(bytes.count + insertions.reduce(0) { $0 + $1.html.utf8.count })

		var previousOffset = 0
		for insertion in insertions.sorted(by: { $0.offset < $1.offset }) {
			output.append(contentsOf: bytes[previousOffset..<insertion.offset])
			output.append(contentsOf: insertion.html.utf8)
			previousOffset = insertion.offset
		}
		output.append(contentsOf: bytes[previousOffset..<bytes.count])

		return String(decoding: output, as: UTF8.self)
	}
}

// MARK: - Private Types

private struct HTMLTranslationParsedSegment {
	let segment: HTMLTranslationSegment
	let endOffset: Int?
}

private struct HTMLTranslationInsertion {
	let offset: Int
	let html: String
}

private struct HTMLTranslationTag {
	let name: String
	let isEnd: Bool
	let isSelfClosing: Bool
	let endOffset: Int
}

private struct HTMLTranslationOpenBlock {
	let tagName: String
	var textBytes: [UInt8] = []
}

// MARK: - Parser

private final class HTMLTranslationParser {

	private let bytes: [UInt8]

	private var position = 0
	private var openBlocks: [HTMLTranslationOpenBlock] = []
	private var skipStack: [String] = []
	private var parsedSegments: [HTMLTranslationParsedSegment] = []

	init(html: String) {
		self.bytes = Array(html.utf8)
	}

	func parse() -> [HTMLTranslationParsedSegment] {
		while position < bytes.count {
			if bytes[position] == .asciiLessThan {
				scanMarkup()
			} else {
				scanText()
			}
		}

		while let block = openBlocks.popLast() {
			finish(block: block, endOffset: nil)
		}

		return parsedSegments
	}
}

// MARK: - Scanning

private extension HTMLTranslationParser {

	func scanMarkup() {
		let start = position
		if consumeSilentMarkup() {
			return
		}

		guard let tag = scanTag() else {
			appendText(bytes: bytes[start...start])
			position = start + 1
			return
		}

		if tag.isEnd {
			handleEndTag(tag)
		} else {
			let skipDepthBeforeStartTag = skipStack.count
			handleStartTag(tag)
			if HTMLTranslationParser.rawTextTags.contains(tag.name) && !tag.isSelfClosing {
				position = offsetAfterRawTextElement(named: tag.name, from: tag.endOffset)
				if skipStack.count > skipDepthBeforeStartTag, skipStack.last == tag.name {
					skipStack.removeLast()
				}
			}
		}
	}

	func scanText() {
		let start = position
		while position < bytes.count && bytes[position] != .asciiLessThan {
			position += 1
		}
		appendText(bytes: bytes[start..<position])
	}

	func scanTag() -> HTMLTranslationTag? {
		assert(bytes[position] == .asciiLessThan)

		var i = position + 1
		var isEnd = false
		if i < bytes.count && bytes[i] == .asciiSlash {
			isEnd = true
			i += 1
		}

		while i < bytes.count && bytes[i].isASCIIWhitespace {
			i += 1
		}

		let nameStart = i
		while i < bytes.count && bytes[i].isHTMLTranslationNameChar {
			i += 1
		}
		guard nameStart < i else {
			return nil
		}

		let name = String(decoding: bytes[nameStart..<i], as: UTF8.self).lowercased()
		var quote: UInt8?
		var lastNonWhitespace: UInt8?

		while i < bytes.count {
			let b = bytes[i]
			if let q = quote {
				if b == q {
					quote = nil
				}
				i += 1
				continue
			}

			if b == .asciiDoubleQuote || b == .asciiSingleQuote {
				quote = b
				i += 1
				continue
			}

			if b == .asciiGreaterThan {
				let endOffset = i + 1
				position = endOffset
				return HTMLTranslationTag(name: name,
				                          isEnd: isEnd,
				                          isSelfClosing: lastNonWhitespace == .asciiSlash,
				                          endOffset: endOffset)
			}

			if !b.isASCIIWhitespace {
				lastNonWhitespace = b
			}
			i += 1
		}

		return nil
	}

	func consumeSilentMarkup() -> Bool {
		guard position + 1 < bytes.count else {
			return false
		}

		if hasPrefix("<!--", at: position) {
			position = offsetAfter("-->", from: position + 4) ?? bytes.count
			return true
		}

		if bytes[position + 1] == .asciiExclamation || bytes[position + 1] == .asciiQuestion {
			while position < bytes.count && bytes[position] != .asciiGreaterThan {
				position += 1
			}
			if position < bytes.count {
				position += 1
			}
			return true
		}

		return false
	}
}

// MARK: - Tag Handling

private extension HTMLTranslationParser {

	func handleStartTag(_ tag: HTMLTranslationTag) {
		if !skipStack.isEmpty {
			pushSkipTagIfNeeded(tag)
			return
		}

		if Self.skippedSubtreeTags.contains(tag.name) {
			pushSkipTagIfNeeded(tag)
			return
		}

		if tag.name == "br" {
			appendText(bytes: [UInt8(ascii: " ")][...])
			return
		}

		if Self.translatableBlockTags.contains(tag.name) && !tag.isSelfClosing && !Self.voidTags.contains(tag.name) {
			openBlocks.append(HTMLTranslationOpenBlock(tagName: tag.name))
		}
	}

	func handleEndTag(_ tag: HTMLTranslationTag) {
		if !skipStack.isEmpty {
			if let index = skipStack.lastIndex(of: tag.name) {
				skipStack.removeSubrange(index..<skipStack.endIndex)
			}
			return
		}

		guard Self.translatableBlockTags.contains(tag.name),
		      let index = openBlocks.lastIndex(where: { $0.tagName == tag.name }) else {
			return
		}

		let block = openBlocks[index]
		openBlocks.removeSubrange(index..<openBlocks.endIndex)
		finish(block: block, endOffset: tag.endOffset)
	}

	func pushSkipTagIfNeeded(_ tag: HTMLTranslationTag) {
		guard Self.skippedSubtreeTags.contains(tag.name), !tag.isSelfClosing, !Self.voidTags.contains(tag.name) else {
			return
		}
		skipStack.append(tag.name)
	}

	func appendText(bytes textBytes: ArraySlice<UInt8>) {
		guard skipStack.isEmpty, !openBlocks.isEmpty else {
			return
		}

		var decoded = [UInt8]()
		decoded.reserveCapacity(textBytes.count)

		var i = textBytes.startIndex
		while i < textBytes.endIndex {
			let b = textBytes[i]
			if b == .asciiAmpersand {
				let result = XMLEntities.decode(bytes: bytes, at: i, mode: .html)
				decoded.append(contentsOf: result.bytes)
				i = result.nextIndex
			} else {
				decoded.append(b)
				i += 1
			}
		}

		openBlocks[openBlocks.count - 1].textBytes.append(contentsOf: decoded)
	}

	func finish(block: HTMLTranslationOpenBlock, endOffset: Int?) {
		let text = Self.normalizedText(String(decoding: block.textBytes, as: UTF8.self))
		guard !text.isEmpty else {
			return
		}

		let ordinal = parsedSegments.count + 1
		let segment = HTMLTranslationSegment(id: Self.segmentID(ordinal: ordinal, text: text), kind: .body, text: text)
		parsedSegments.append(HTMLTranslationParsedSegment(segment: segment, endOffset: endOffset))
	}
}

// MARK: - Utilities

private extension HTMLTranslationParser {

	static let translatableBlockTags: Set<String> = [
		"p", "li", "blockquote", "figcaption",
		"h1", "h2", "h3", "h4", "h5", "h6",
		"td", "th", "dd", "dt"
	]

	static let rawTextTags: Set<String> = ["script", "style"]

	static let skippedSubtreeTags: Set<String> = [
		"script", "style", "pre", "code", "kbd", "samp", "textarea", "select", "svg", "math",
		"img", "picture", "video", "audio", "source", "iframe", "object", "embed", "canvas"
	]

	static let voidTags: Set<String> = [
		"area", "base", "br", "col", "embed", "hr", "img", "input", "link", "meta", "param", "source", "track", "wbr"
	]

	static func normalizedText(_ text: String) -> String {
		text.components(separatedBy: .whitespacesAndNewlines).filter { !$0.isEmpty }.joined(separator: " ")
	}

	static func segmentID(ordinal: Int, text: String) -> String {
		"body-\(String(format: "%04d", ordinal))-\(fnv1aHash(text))"
	}

	static func fnv1aHash(_ text: String) -> String {
		var hash: UInt32 = 2_166_136_261
		for byte in text.utf8 {
			hash ^= UInt32(byte)
			hash = hash &* 16_777_619
		}
		return String(format: "%08x", hash)
	}

	func offsetAfterRawTextElement(named name: String, from offset: Int) -> Int {
		var i = offset
		while i < bytes.count {
			if bytes[i] == .asciiLessThan && i + 2 < bytes.count && bytes[i + 1] == .asciiSlash {
				var nameStart = i + 2
				while nameStart < bytes.count && bytes[nameStart].isASCIIWhitespace {
					nameStart += 1
				}
				var nameEnd = nameStart
				while nameEnd < bytes.count && bytes[nameEnd].isHTMLTranslationNameChar {
					nameEnd += 1
				}
				if nameStart < nameEnd {
					let candidateName = String(decoding: bytes[nameStart..<nameEnd], as: UTF8.self).lowercased()
					if candidateName == name {
						while nameEnd < bytes.count && bytes[nameEnd] != .asciiGreaterThan {
							nameEnd += 1
						}
						return nameEnd < bytes.count ? nameEnd + 1 : bytes.count
					}
				}
			}
			i += 1
		}
		return bytes.count
	}

	func hasPrefix(_ prefix: StaticString, at offset: Int) -> Bool {
		let count = prefix.utf8CodeUnitCount
		guard offset + count <= bytes.count else {
			return false
		}

		return prefix.withUTF8Buffer { buffer in
			for i in 0..<count {
				if bytes[offset + i] != buffer[i] {
					return false
				}
			}
			return true
		}
	}

	func offsetAfter(_ needle: StaticString, from offset: Int) -> Int? {
		let count = needle.utf8CodeUnitCount
		guard count > 0, offset + count <= bytes.count else {
			return nil
		}

		return needle.withUTF8Buffer { needleBuffer in
			var i = offset
			while i + count <= bytes.count {
				var found = true
				for j in 0..<count {
					if bytes[i + j] != needleBuffer[j] {
						found = false
						break
					}
				}
				if found {
					return i + count
				}
				i += 1
			}
			return nil
		}
	}
}

private extension HTMLTranslationSegmenter {

	static func translationHTML(id: String, text: String) -> String {
		#"<div class="nnw-translation" data-nnw-translation-id="\#(id)">\#(escapeHTML(text))</div>"#
	}

	static func escapeHTML(_ text: String) -> String {
		var escaped = ""
		escaped.reserveCapacity(text.count)

		for character in text {
			switch character {
			case "&":
				escaped += "&amp;"
			case "<":
				escaped += "&lt;"
			case ">":
				escaped += "&gt;"
			case "\"":
				escaped += "&quot;"
			default:
				escaped.append(character)
			}
		}

		return escaped
	}
}

private extension UInt8 {

	var isHTMLTranslationNameChar: Bool {
		isXMLNameChar
	}
}
