//
//  ArticleTranslationConfigurationProvider.swift
//  NetNewsWire
//
//  Created by OpenAI on 4/30/26.
//  Copyright © 2026 Ranchero Software. All rights reserved.
//

import Foundation
import ArticleTranslation
import Secrets

enum ArticleTranslationConfigurationError: LocalizedError {
	case missingAPIKey
	case invalidBaseURL(String)

	var errorDescription: String? {
		switch self {
		case .missingAPIKey:
			return NSLocalizedString("Add an API key in Translation settings before translating articles.", comment: "Missing translation API key")
		case .invalidBaseURL(let baseURLString):
			let format = NSLocalizedString("The translation provider URL is invalid: %@", comment: "Invalid translation URL")
			return String(format: format, baseURLString)
		}
	}
}

enum ArticleTranslationConfigurationProvider {

	static func configuration() throws -> TranslationConfiguration {
		let baseURLString = AppDefaults.shared.translationBaseURLString.trimmingCharacters(in: .whitespacesAndNewlines)
		guard let baseURL = URL(string: baseURLString), baseURL.scheme != nil, baseURL.host != nil else {
			throw ArticleTranslationConfigurationError.invalidBaseURL(baseURLString)
		}

		guard let apiKey = try TranslationAPIKeyStore.retrieveAPIKey()?.trimmingCharacters(in: .whitespacesAndNewlines), !apiKey.isEmpty else {
			throw ArticleTranslationConfigurationError.missingAPIKey
		}

		let model = AppDefaults.shared.translationModel.trimmingCharacters(in: .whitespacesAndNewlines)
		return TranslationConfiguration(
			baseURL: baseURL,
			model: model.isEmpty ? TranslationConfiguration.deepSeekDefaultModel : model,
			apiKey: apiKey
		)
	}
}
