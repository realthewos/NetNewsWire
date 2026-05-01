//
//  TranslationAPIKeyStore.swift
//  NetNewsWire
//
//  Created by OpenAI on 4/30/26.
//  Copyright © 2026 Ranchero Software. All rights reserved.
//

import Foundation

public enum TranslationAPIKeyStore {

	private static let server = "NetNewsWireArticleTranslation"
	private static let username = "default"

	public static func storeAPIKey(_ apiKey: String) throws {
		let trimmedAPIKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
		guard !trimmedAPIKey.isEmpty else {
			try removeAPIKey()
			return
		}

		let credentials = Credentials(type: .llmTranslationAPIKey, username: username, secret: trimmedAPIKey)
		try CredentialsManager.storeCredentials(credentials, server: server)
	}

	public static func retrieveAPIKey() throws -> String? {
		let credentials = try CredentialsManager.retrieveCredentials(type: .llmTranslationAPIKey, server: server, username: username)
		return credentials?.secret
	}

	public static func removeAPIKey() throws {
		try CredentialsManager.removeCredentials(type: .llmTranslationAPIKey, server: server, username: username)
	}
}
