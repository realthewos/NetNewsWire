//
//  ArticleTranslationButton.swift
//  NetNewsWire
//
//  Created by OpenAI on 4/30/26.
//  Copyright © 2026 Ranchero Software. All rights reserved.
//

import AppKit

enum ArticleTranslationButtonState {
	case error
	case processing
	case on
	case off
}

final class ArticleTranslationButton: NSButton {

	private let progressIndicator: NSProgressIndicator = {
		let indicator = NSProgressIndicator()
		indicator.style = .spinning
		indicator.controlSize = .small
		indicator.isDisplayedWhenStopped = false
		indicator.translatesAutoresizingMaskIntoConstraints = false
		return indicator
	}()

	var buttonState: ArticleTranslationButtonState = .off {
		didSet {
			if buttonState != oldValue {
				switch buttonState {
				case .error:
					progressIndicator.stopAnimation(nil)
					isEnabled = true
					image = Assets.Images.translateError
				case .processing:
					image = nil
					progressIndicator.startAnimation(nil)
					isEnabled = false
				case .on:
					progressIndicator.stopAnimation(nil)
					isEnabled = true
					image = Assets.Images.translateSelected
				case .off:
					progressIndicator.stopAnimation(nil)
					isEnabled = true
					image = Assets.Images.translate
				}
			}
		}
	}

	override func accessibilityLabel() -> String? {
		switch buttonState {
		case .error:
			return NSLocalizedString("Error - Translation", comment: "Error - Translation")
		case .processing:
			return NSLocalizedString("Processing - Translation", comment: "Processing - Translation")
		case .on:
			return NSLocalizedString("Selected - Translation", comment: "Selected - Translation")
		case .off:
			return NSLocalizedString("Translate Article", comment: "Translate Article")
		}
	}

	override init(frame frameRect: NSRect) {
		super.init(frame: frameRect)
		commonInit()
	}

	required init?(coder: NSCoder) {
		super.init(coder: coder)
		commonInit()
	}

	private func commonInit() {
		wantsLayer = true
		bezelStyle = .texturedRounded
		image = Assets.Images.translate
		imageScaling = .scaleProportionallyDown
		widthAnchor.constraint(equalTo: heightAnchor).isActive = true

		addSubview(progressIndicator)
		NSLayoutConstraint.activate([
			progressIndicator.centerXAnchor.constraint(equalTo: centerXAnchor),
			progressIndicator.centerYAnchor.constraint(equalTo: centerYAnchor)
		])
	}
}
