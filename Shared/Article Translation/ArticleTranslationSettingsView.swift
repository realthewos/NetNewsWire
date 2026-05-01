//
//  ArticleTranslationSettingsView.swift
//  NetNewsWire
//
//  Created by OpenAI on 4/30/26.
//  Copyright © 2026 Ranchero Software. All rights reserved.
//

import SwiftUI
import ArticleTranslation
import Secrets

struct ArticleTranslationSettingsView: View {

	@State private var baseURLString = AppDefaults.shared.translationBaseURLString
	@State private var model = AppDefaults.shared.translationModel
	@State private var apiKey = ""
	@State private var hasStoredAPIKey = false
	@State private var statusMessage = ""

	var body: some View {
		Form {
			Section {
				TextField("Provider URL", text: $baseURLString)
				TextField("Model", text: $model)
				SecureField(apiKeyPrompt, text: $apiKey)
			}

			Section {
				VStack(alignment: .leading) {
					Button("Save") {
						save()
					}
					Button("Reset DeepSeek Defaults") {
						resetDeepSeekDefaults()
					}
					if hasStoredAPIKey {
						Button("Clear API Key", role: .destructive) {
							clearAPIKey()
						}
					}
				}
				if !statusMessage.isEmpty {
					Text(statusMessage)
						.font(.footnote)
						.foregroundStyle(.secondary)
				}
			}
		}
		.formStyle(.grouped)
		.navigationTitle(Text("Translation"))
		.padding()
		.onAppear {
			loadStoredAPIKeyState()
		}
	}
}

private extension ArticleTranslationSettingsView {

	var apiKeyPrompt: String {
		hasStoredAPIKey ? NSLocalizedString("API Key (leave blank to keep current key)", comment: "Translation API key placeholder") : NSLocalizedString("API Key", comment: "Translation API key placeholder")
	}

	func save() {
		let trimmedBaseURLString = baseURLString.trimmingCharacters(in: .whitespacesAndNewlines)
		guard let baseURL = URL(string: trimmedBaseURLString), baseURL.scheme != nil, baseURL.host != nil else {
			statusMessage = NSLocalizedString("Provider URL is invalid.", comment: "Translation settings error")
			return
		}

		AppDefaults.shared.translationBaseURLString = trimmedBaseURLString

		let trimmedModel = model.trimmingCharacters(in: .whitespacesAndNewlines)
		AppDefaults.shared.translationModel = trimmedModel.isEmpty ? TranslationConfiguration.deepSeekDefaultModel : trimmedModel
		model = AppDefaults.shared.translationModel

		let trimmedAPIKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
		if !trimmedAPIKey.isEmpty {
			do {
				try TranslationAPIKeyStore.storeAPIKey(trimmedAPIKey)
				apiKey = ""
			} catch {
				statusMessage = error.localizedDescription
				return
			}
		}

		loadStoredAPIKeyState()
		statusMessage = NSLocalizedString("Saved.", comment: "Translation settings saved")
	}

	func resetDeepSeekDefaults() {
		baseURLString = TranslationConfiguration.deepSeekDefaultBaseURL.absoluteString
		model = TranslationConfiguration.deepSeekDefaultModel
		statusMessage = ""
	}

	func clearAPIKey() {
		do {
			try TranslationAPIKeyStore.removeAPIKey()
			apiKey = ""
			loadStoredAPIKeyState()
			statusMessage = NSLocalizedString("API key cleared.", comment: "Translation API key cleared")
		} catch {
			statusMessage = error.localizedDescription
		}
	}

	func loadStoredAPIKeyState() {
		do {
			hasStoredAPIKey = try TranslationAPIKeyStore.retrieveAPIKey()?.isEmpty == false
		} catch {
			hasStoredAPIKey = false
			statusMessage = error.localizedDescription
		}
	}
}
