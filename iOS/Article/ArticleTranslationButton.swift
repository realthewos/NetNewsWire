//
//  ArticleTranslationButton.swift
//  NetNewsWire-iOS
//
//  Created by OpenAI on 4/30/26.
//  Copyright © 2026 Ranchero Software. All rights reserved.
//

import UIKit

enum ArticleTranslationButtonState {
	case error
	case processing
	case on
	case off
}

final class ArticleTranslationButton: UIButton {

	private let activityIndicator: UIActivityIndicatorView = {
		let indicator = UIActivityIndicatorView(style: .medium)
		indicator.hidesWhenStopped = true
		indicator.translatesAutoresizingMaskIntoConstraints = false
		return indicator
	}()

	var buttonState: ArticleTranslationButtonState = .off {
		didSet {
			if buttonState != oldValue {
				switch buttonState {
				case .error:
					activityIndicator.stopAnimating()
					isUserInteractionEnabled = true
					setImage(Assets.Images.translateError, for: .normal)
				case .processing:
					setImage(nil, for: .normal)
					activityIndicator.startAnimating()
					isUserInteractionEnabled = false
				case .on:
					activityIndicator.stopAnimating()
					isUserInteractionEnabled = true
					setImage(Assets.Images.translateSelected, for: .normal)
				case .off:
					activityIndicator.stopAnimating()
					isUserInteractionEnabled = true
					setImage(Assets.Images.translate, for: .normal)
				}
			}
		}
	}

	override var accessibilityLabel: String? {
		get {
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
		set {
			super.accessibilityLabel = newValue
		}
	}

	override init(frame: CGRect) {
		super.init(frame: frame)
		commonInit()
	}

	required init?(coder: NSCoder) {
		super.init(coder: coder)
		commonInit()
	}

	override func point(inside point: CGPoint, with event: UIEvent?) -> Bool {
		let expandedBounds = bounds.insetBy(dx: -20, dy: -20)
		return expandedBounds.contains(point)
	}

	private func commonInit() {
		setImage(Assets.Images.translate, for: .normal)

		addSubview(activityIndicator)
		NSLayoutConstraint.activate([
			widthAnchor.constraint(equalToConstant: 44.0),
			heightAnchor.constraint(equalToConstant: 44.0),
			activityIndicator.centerXAnchor.constraint(equalTo: centerXAnchor),
			activityIndicator.centerYAnchor.constraint(equalTo: centerYAnchor)
		])
	}
}
