//
//  MochiLinks.swift
//  MochiBuddy
//
//  External destinations the You tab links out to. Privacy/support live on
//  GitHub Pages (repo docs/) until the mochibuddy.app domain exists; the
//  EULA uses Apple's standard agreement (valid for subscription apps)
//  until we write our own.
//

import Foundation
import UIKit

enum MochiLinks {
    static let privacyPolicy = URL(string: "https://a-squareddev.github.io/MochiBuddy/privacy/")!
    static let termsOfUse = URL(string: "https://www.apple.com/legal/internet-services/itunes/dev/stdeula/")!
    static let support = URL(string: "mailto:asquared.dev@gmail.com")!
    static let manageSubscriptions = URL(string: "https://apps.apple.com/account/subscriptions")!
    /// Deep link into the app's own page in Settings (notification toggles).
    static let systemSettings = URL(string: UIApplication.openSettingsURLString)!
}
