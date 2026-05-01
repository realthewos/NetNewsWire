//
//  ArticleTranslationRendering.swift
//  NetNewsWire
//
//  Created by OpenAI on 4/30/26.
//  Copyright © 2026 Ranchero Software. All rights reserved.
//

import Foundation
import ArticleTranslation
import Articles
import RSParser

struct PreparedArticleTranslation: Sendable {
	let articleID: String
	let sourceHash: String
	let sourceTextForDirectionDetection: String
	let segments: [TranslationSegment]
}

enum ArticleTranslationRendering {

	static func prepare(article: Article, extractedArticle: ExtractedArticle? = nil) -> PreparedArticleTranslation {
		let sourceHTML = html(article: article, extractedArticle: extractedArticle)
		let titleSegment = titleSegment(for: article)
		let segmentedDocument = HTMLTranslationSegmenter.segment(sourceHTML)
		let bodySegments = segmentedDocument.segments.map { segment in
			TranslationSegment(id: segment.id, text: segment.text)
		}
		let segments = [titleSegment].compactMap { $0 } + bodySegments
		let sourceTextForDirectionDetection = segments.map(\.text).joined(separator: "\n\n")
		let sourceHash = hash([article.title ?? "", sourceHTML].joined(separator: "\n\n"))

		return PreparedArticleTranslation(
			articleID: articleID(article: article, extractedArticle: extractedArticle),
			sourceHash: sourceHash,
			sourceTextForDirectionDetection: sourceTextForDirectionDetection,
			segments: segments
		)
	}

	static func sourceKey(article: Article, extractedArticle: ExtractedArticle? = nil) -> String {
		let prepared = prepare(article: article, extractedArticle: extractedArticle)
		return sourceKey(articleID: prepared.articleID, sourceHash: prepared.sourceHash)
	}

	static func sourceKey(articleID: String, sourceHash: String) -> String {
		"\(articleID):\(sourceHash)"
	}

	static func html(article: Article, extractedArticle: ExtractedArticle? = nil) -> String {
		if let content = extractedArticle?.content {
			return content
		}
		return article.body ?? ""
	}

	static func htmlByAddingTranslations(to html: String, translations: [String: String]) -> String {
		HTMLTranslationSegmenter.htmlByAddingTranslations(to: html, translations: translations)
	}

	static func titleSegmentID(for article: Article) -> String? {
		titleSegment(for: article)?.id
	}

	static func hash(_ text: String) -> String {
		var hash: UInt32 = 2_166_136_261
		for byte in text.utf8 {
			hash ^= UInt32(byte)
			hash = hash &* 16_777_619
		}
		return String(format: "%08x", hash)
	}
}

private extension ArticleTranslationRendering {

	static func titleSegment(for article: Article) -> TranslationSegment? {
		guard let title = ArticleStringFormatter.sanitizedTitle(article.title, forHTML: false) else {
			return nil
		}
		let normalizedTitle = normalizedText(title)
		guard !normalizedTitle.isEmpty else {
			return nil
		}
		return TranslationSegment(id: "title-0001-\(hash(normalizedTitle))", text: normalizedTitle)
	}

	static func articleID(article: Article, extractedArticle: ExtractedArticle?) -> String {
		if extractedArticle == nil {
			return article.articleID
		}
		return "\(article.articleID):extracted"
	}

	static func normalizedText(_ text: String) -> String {
		text.components(separatedBy: .whitespacesAndNewlines).filter { !$0.isEmpty }.joined(separator: " ")
	}
}
