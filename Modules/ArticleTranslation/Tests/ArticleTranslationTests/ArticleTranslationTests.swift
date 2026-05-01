import ArticleTranslation
import Foundation
import RSWeb
import XCTest

final class ArticleTranslationTests: XCTestCase {

	func testDirectionDetectionTreatsMeaningfulCJKAsChineseToEnglish() {
		let direction = TranslationDirection.detect(for: "今天的新闻提到 RSS 阅读器的更新。")

		XCTAssertEqual(direction, .chineseToEnglish)
		XCTAssertEqual(direction.targetLanguageName, "English")
	}

	func testDirectionDetectionTreatsEnglishAsToSimplifiedChinese() {
		let direction = TranslationDirection.detect(for: "Today the feed reader received a useful update.")

		XCTAssertEqual(direction, .toSimplifiedChinese)
		XCTAssertEqual(direction.targetLanguageName, "Simplified Chinese")
	}

	func testRequestConstructionUsesOpenAICompatibleChatCompletions() async throws {
		let transport = RecordingTransport(responseObject: [
			"choices": [
				[
					"message": [
						"content": #"{"title":"译文标题","body":"译文正文"}"#
					]
				]
			]
		])
		let client = OpenAIChatCompletionsClient(transport: transport)
		let configuration = TranslationConfiguration(
			baseURL: Self.url("https://example.com/v1"),
			model: "example-model",
			apiKey: "test-key"
		)
		let segments = [
			TranslationSegment(id: "title", text: "Original title"),
			TranslationSegment(id: "body", text: "Original body")
		]

		_ = try await client.translate(
			segments: segments,
			direction: .toSimplifiedChinese,
			configuration: configuration
		)

		let recordedCall = await transport.onlyCall
		let call = try XCTUnwrap(recordedCall)
		XCTAssertEqual(call.request.url?.absoluteString, "https://example.com/v1/chat/completions")
		XCTAssertEqual(call.method, "POST")
		XCTAssertEqual(call.request.value(forHTTPHeaderField: "Authorization"), "Bearer test-key")
		XCTAssertEqual(call.request.value(forHTTPHeaderField: "Content-Type"), "application/json; charset=utf-8")

		let body = try XCTUnwrap(JSONSerialization.jsonObject(with: call.payload) as? [String: Any])
		XCTAssertEqual(body["model"] as? String, "example-model")
		XCTAssertEqual(body["temperature"] as? Int, 0)

		let messages = try XCTUnwrap(body["messages"] as? [[String: String]])
		let messageText = messages.map { "\($0["role"] ?? "") \($0["content"] ?? "")" }.joined(separator: "\n")
		XCTAssertTrue(messageText.contains("Simplified Chinese"))
		XCTAssertTrue(messageText.contains("title"))
		XCTAssertTrue(messageText.contains("Original title"))
		XCTAssertTrue(messageText.contains("body"))
		XCTAssertTrue(messageText.contains("Original body"))
		XCTAssertTrue(messageText.contains("JSON object"))
	}

	func testBaseURLNormalization() async throws {
		let cases = [
			("https://example.com", "https://example.com/chat/completions"),
			("https://example.com/v1", "https://example.com/v1/chat/completions"),
			("https://example.com/chat/completions", "https://example.com/chat/completions")
		]

		for (baseURLString, expectedURLString) in cases {
			let transport = RecordingTransport(responseObject: Self.responseObject(content: #"{"segment":"translated"}"#))
			let client = OpenAIChatCompletionsClient(transport: transport)
			let configuration = TranslationConfiguration(
				baseURL: Self.url(baseURLString),
				model: "model",
				apiKey: "key"
			)

			_ = try await client.translate(
				segments: [TranslationSegment(id: "segment", text: "text")],
				direction: .toSimplifiedChinese,
				configuration: configuration
			)

			let recordedURLString = await transport.onlyCall?.request.url?.absoluteString
			XCTAssertEqual(recordedURLString, expectedURLString)
		}
	}

	func testResponseDecodingParsesJSONContentFromFirstChoice() async throws {
		let transport = RecordingTransport(responseObject: Self.responseObject(content: #"{"a":"Alpha","b":"Beta"}"#))
		let client = OpenAIChatCompletionsClient(transport: transport)

		let translations = try await client.translate(
			segments: [
				TranslationSegment(id: "a", text: "A"),
				TranslationSegment(id: "b", text: "B")
			],
			direction: .toSimplifiedChinese,
			configuration: Self.configuration
		)

		XCTAssertEqual(translations, ["a": "Alpha", "b": "Beta"])
	}

	func testMalformedJSONContentThrows() async throws {
		let transport = RecordingTransport(responseObject: Self.responseObject(content: "not json"))
		let client = OpenAIChatCompletionsClient(transport: transport)

		do {
			_ = try await client.translate(
				segments: [TranslationSegment(id: "a", text: "A")],
				direction: .toSimplifiedChinese,
				configuration: Self.configuration
			)
			XCTFail("Expected malformed JSON content to throw.")
		} catch {
			// Expected.
		}
	}

	func testCacheHitAvoidsSecondTransportCall() async throws {
		let transport = RecordingTransport(responseObject: Self.responseObject(content: #"{"a":"Alpha"}"#))
		let service = ArticleTranslationService(
			client: OpenAIChatCompletionsClient(transport: transport),
			cache: ArticleTranslationMemoryCache()
		)

		let first = try await service.translate(
			articleID: "article",
			sourceHash: "hash",
			sourceTextForDirectionDetection: "English text",
			segments: [TranslationSegment(id: "a", text: "A")],
			configuration: Self.configuration
		)
		let second = try await service.translate(
			articleID: "article",
			sourceHash: "hash",
			sourceTextForDirectionDetection: "English text",
			segments: [TranslationSegment(id: "a", text: "A")],
			configuration: Self.configuration
		)

		XCTAssertEqual(first, ["a": "Alpha"])
		XCTAssertEqual(second, ["a": "Alpha"])
		let callCount = await transport.callCount
		XCTAssertEqual(callCount, 1)
	}

	func testDifferentModelBaseURLAndSourceHashMissCache() async throws {
		let transport = RecordingTransport(responseObjects: [
			Self.responseObject(content: #"{"a":"One"}"#),
			Self.responseObject(content: #"{"a":"Two"}"#),
			Self.responseObject(content: #"{"a":"Three"}"#),
			Self.responseObject(content: #"{"a":"Four"}"#)
		])
		let service = ArticleTranslationService(
			client: OpenAIChatCompletionsClient(transport: transport),
			cache: ArticleTranslationMemoryCache()
		)

		_ = try await service.translate(
			articleID: "article",
			sourceHash: "hash-1",
			sourceTextForDirectionDetection: "English text",
			segments: [TranslationSegment(id: "a", text: "A")],
			configuration: Self.configuration
		)
		_ = try await service.translate(
			articleID: "article",
			sourceHash: "hash-2",
			sourceTextForDirectionDetection: "English text",
			segments: [TranslationSegment(id: "a", text: "A")],
			configuration: Self.configuration
		)
		_ = try await service.translate(
			articleID: "article",
			sourceHash: "hash-1",
			sourceTextForDirectionDetection: "English text",
			segments: [TranslationSegment(id: "a", text: "A")],
			configuration: TranslationConfiguration(
				baseURL: Self.configuration.baseURL,
				model: "other-model",
				apiKey: Self.configuration.apiKey
			)
		)
		_ = try await service.translate(
			articleID: "article",
			sourceHash: "hash-1",
			sourceTextForDirectionDetection: "English text",
			segments: [TranslationSegment(id: "a", text: "A")],
			configuration: TranslationConfiguration(
				baseURL: Self.url("https://other.example.com"),
				model: Self.configuration.model,
				apiKey: Self.configuration.apiKey
			)
		)

		let callCount = await transport.callCount
		XCTAssertEqual(callCount, 4)
	}

	private static let configuration = TranslationConfiguration(
		baseURL: url("https://example.com"),
		model: "test-model",
		apiKey: "test-key"
	)

	private static func url(_ string: String) -> URL {
		guard let url = URL(string: string) else {
			fatalError("Invalid test URL: \(string)")
		}

		return url
	}

	private static func responseObject(content: String) -> [String: Any] {
		[
			"choices": [
				[
					"message": [
						"content": content
					]
				]
			]
		]
	}
}

private final class RecordingTransport: Transport, @unchecked Sendable {
	struct Call: Sendable {
		let request: URLRequest
		let method: String
		let payload: Data
	}

	private let lock = NSLock()
	private var responseObjects: [[String: Any]]
	private var calls = [Call]()

	init(responseObject: [String: Any]) {
		self.responseObjects = [responseObject]
	}

	init(responseObjects: [[String: Any]]) {
		self.responseObjects = responseObjects
	}

	var onlyCall: Call? {
		get async {
			lock.withLock {
				calls.first
			}
		}
	}

	var callCount: Int {
		get async {
			lock.withLock {
				calls.count
			}
		}
	}

	func cancelAll() {
	}

	func send(request: URLRequest) async throws -> (HTTPURLResponse, Data?) {
		throw TestTransportError.unimplemented
	}

	func send(request: URLRequest, completion: @escaping @Sendable (Result<(HTTPURLResponse, Data?), Error>) -> Void) {
		completion(.failure(TestTransportError.unimplemented))
	}

	func send(request: URLRequest, method: String) async throws {
		throw TestTransportError.unimplemented
	}

	func send(request: URLRequest, method: String, completion: @escaping @Sendable (Result<Void, Error>) -> Void) {
		completion(.failure(TestTransportError.unimplemented))
	}

	func send(request: URLRequest, method: String, payload: Data) async throws -> (HTTPURLResponse, Data?) {
		let responseObject = lock.withLock {
			calls.append(Call(request: request, method: method, payload: payload))
			return responseObjects.removeFirst()
		}
		let data = try JSONSerialization.data(withJSONObject: responseObject)
		return (Self.httpResponse(for: request), data)
	}

	func send(request: URLRequest, method: String, payload: Data, completion: @escaping @Sendable (Result<(HTTPURLResponse, Data?), Error>) -> Void) {
		Task {
			do {
				completion(.success(try await send(request: request, method: method, payload: payload)))
			} catch {
				completion(.failure(error))
			}
		}
	}

	private static func httpResponse(for request: URLRequest) -> HTTPURLResponse {
		guard let url = request.url else {
			fatalError("Attempting to mock a response for a request without a URL.")
		}

		guard let response = HTTPURLResponse(
			url: url,
			statusCode: 200,
			httpVersion: "HTTP/1.1",
			headerFields: nil
		) else {
			fatalError("Unable to create test HTTP response.")
		}

		return response
	}
}

private enum TestTransportError: Error {
	case unimplemented
}
