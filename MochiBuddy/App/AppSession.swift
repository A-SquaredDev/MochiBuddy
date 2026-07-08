//
//  AppSession.swift
//  MochiBuddy
//
//  Which root the app is showing: the onboarding/re-entry flow (which
//  always starts at splash and routes returning users itself) or home.
//

import Observation

@MainActor
@Observable
final class AppSession {
    enum Phase {
        case flow
        case home
    }

    var phase: Phase = .flow
}
