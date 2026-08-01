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

    /// Which screen roots the flow when phase is .flow. Every site that
    /// sets phase = .flow also sets this, so a stale value can never leak
    /// into the next entry.
    enum FlowEntry {
        /// Cold start and re-entries that must re-evaluate the session
        /// (lapse gate, Wake Mochi) - splash runs and may mint.
        case splash
        /// After sign-out or account deletion - land directly on Landing
        /// with no session, so no replacement anonymous account is minted
        /// for someone who is about to sign in or leave.
        case landing
    }

    var phase: Phase = .flow
    var flowEntry: FlowEntry = .splash
}
