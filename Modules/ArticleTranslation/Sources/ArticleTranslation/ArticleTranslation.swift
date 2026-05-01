import Foundation
import RSWeb

public struct TranslationConfiguration: Equatable, Sendable {
	public let baseURL: URL
	public let model: String
	public let apiKey: String

	public init(baseURL: URL, model: String, apiKey: String) {
		self.baseURL = baseURL
		self.model = model
		self.apiKey = apiKey
	}

	public static let deepSeekDefaultBaseURL = URL(string: "https://api.deepseek.com")!
	public static let deepSeekDefaultModel = "deepseek-v4-flash"
}

public enum TranslationDirection: Equatable, Sendable {
	case chineseToEnglish
	case toSimplifiedChinese

	public static func detect(for text: String) -> TranslationDirection {
		let cjkScalarCount = text.unicodeScalars.reduce(0) { count, scalar in
			count + (scalar.isCJKUnifiedIdeograph ? 1 : 0)
		}

		return cjkScalarCount >= 2 ? .chineseToEnglish : .toSimplifiedChinese
	}

	public var targetLanguageName: String {
		switch self {
		case .chineseToEnglish:
			return "English"
		case .toSimplifiedChinese:
			return "Simplified Chinese"
		}
	}
}

public struct TranslationSegment: Equatable, Sendable, Codable {
	public let id: String
	public let text: String

	public init(id: String, text: String) {
		self.id = id
		self.text = text
	}
}

public actor ArticleTranslationMemoryCache {
	private struct Key: Hashable {
		let articleID: String
		let sourceHash: String
		let direction: TranslationDirection
		let baseURLString: String
		let model: String
	}

	private var translationsByKey = [Key: [String: String]]()

	public init() {
	}

	public func get(
		articleID: String,
		sourceHash: String,
		direction: TranslationDirection,
		configuration: TranslationConfiguration
	) -> [String: String]? {
		translationsByKey[Self.key(
			articleID: articleID,
			sourceHash: sourceHash,
			direction: direction,
			configuration: configuration
		)]
	}

	public func set(
		_ translations: [String: String],
		articleID: String,
		sourceHash: String,
		direction: TranslationDirection,
		configuration: TranslationConfiguration
	) {
		translationsByKey[Self.key(
			articleID: articleID,
			sourceHash: sourceHash,
			direction: direction,
			configuration: configuration
		)] = translations
	}

	private static func key(
		articleID: String,
		sourceHash: String,
		direction: TranslationDirection,
		configuration: TranslationConfiguration
	) -> Key {
		Key(
			articleID: articleID,
			sourceHash: sourceHash,
			direction: direction,
			baseURLString: configuration.baseURL.absoluteString,
			model: configuration.model
		)
	}
}

public enum ArticleTranslationError: Error, Equatable, Sendable {
	case missingResponse
	case malformedTranslationJSON
}

public final class OpenAIChatCompletionsClient: Sendable {
	private let transport: any Transport

	public init(transport: any Transport = URLSession.webserviceTransport()) {
		self.transport = transport
	}

	public func translate(
		segments: [TranslationSegment],
		direction: TranslationDirection,
		configuration: TranslationConfiguration
	) async throws -> [String: String] {
		var request = URLRequest(url: Self.chatCompletionsURL(for: configuration.baseURL))
		request.setValue("Bearer \(configuration.apiKey)", forHTTPHeaderField: "Authorization")
		request.setValue("application/json; charset=utf-8", forHTTPHeaderField: HTTPRequestHeader.contentType)

		let payload = ChatCompletionRequest(
			model: configuration.model,
			temperature: 0,
			messages: Self.messages(for: segments, direction: direction)
		)
		let data = try JSONEncoder().encode(payload)
		let (_, responseData) = try await transport.send(request: request, method: "POST", payload: data)

		guard let responseData, !responseData.isEmpty else {
			throw ArticleTranslationError.missingResponse
		}

		let response = try JSONDecoder().decode(ChatCompletionResponse.self, from: responseData)

		guard let content = response.choices.first?.message.content else {
			throw ArticleTranslationError.missingResponse
		}

		guard let contentData = content.data(using: .utf8),
			  let translations = try? JSONDecoder().decode([String: String].self, from: contentData) else {
			throw ArticleTranslationError.malformedTranslationJSON
		}

		return translations
	}

	private static func chatCompletionsURL(for baseURL: URL) -> URL {
		guard var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: false) else {
			return baseURL
		}

		let trimmedPath = components.path.trimmingTrailingSlashes()
		if trimmedPath.hasSuffix("/chat/completions") {
			components.path = trimmedPath
		} else if trimmedPath.isEmpty {
			components.path = "/chat/completions"
		} else {
			components.path = "\(trimmedPath)/chat/completions"
		}

		return components.url ?? baseURL
	}

	private static func messages(for segments: [TranslationSegment], direction: TranslationDirection) -> [ChatCompletionMessage] {
		let segmentJSON = (try? String(data: JSONEncoder().encode(segments), encoding: .utf8)) ?? "[]"
		return [
			ChatCompletionMessage(
				role: "system",
				content: "Translate each segment to \(direction.targetLanguageName). Return a JSON object keyed by segment id with plain text string values only. Do not include Markdown, code fences, arrays, explanations, or extra keys."
			),
			ChatCompletionMessage(
				role: "user",
				content: "Segments: \(segmentJSON)"
			)
		]
	}
}

public final class ArticleTranslationService: Sendable {
	private let client: OpenAIChatCompletionsClient
	private let cache: ArticleTranslationMemoryCache

	public init(
		client: OpenAIChatCompletionsClient = .init(),
		cache: ArticleTranslationMemoryCache = .init()
	) {
		self.client = client
		self.cache = cache
	}

	public func translate(
		articleID: String,
		sourceHash: String,
		sourceTextForDirectionDetection: String,
		segments: [TranslationSegment],
		configuration: TranslationConfiguration
	) async throws -> [String: String] {
		let direction = TranslationDirection.detect(for: sourceTextForDirectionDetection)

		if let translations = await cache.get(
			articleID: articleID,
			sourceHash: sourceHash,
			direction: direction,
			configuration: configuration
		) {
			return translations
		}

		let translations = try await client.translate(
			segments: segments,
			direction: direction,
			configuration: configuration
		)
		await cache.set(
			translations,
			articleID: articleID,
			sourceHash: sourceHash,
			direction: direction,
			configuration: configuration
		)
		return translations
	}
}

private struct ChatCompletionRequest: Encodable {
	let model: String
	let temperature: Int
	let messages: [ChatCompletionMessage]
}

private struct ChatCompletionMessage: Encodable {
	let role: String
	let content: String
}

private struct ChatCompletionResponse: Decodable {
	struct Choice: Decodable {
		struct Message: Decodable {
			let content: String
		}

		let message: Message
	}

	let choices: [Choice]
}

private extension String {
	func trimmingTrailingSlashes() -> String {
		var result = self
		while result.hasSuffix("/") {
			result.removeLast()
		}
		return result
	}
}

private extension Unicode.Scalar {
	var isCJKUnifiedIdeograph: Bool {
		(0x3400...0x4DBF).contains(value) ||
			(0x4E00...0x9FFF).contains(value) ||
			(0xF900...0xFAFF).contains(value)
	}
}
