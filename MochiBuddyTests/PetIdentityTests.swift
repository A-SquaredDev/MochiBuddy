//
//  PetIdentityTests.swift
//  MochiBuddyTests
//
//  Personal Layer, Feature 1: name + adoption date. Covers the required
//  test list from the requirements doc - sanitization table, IME policy,
//  migration/backstop, the PetIdentityDidChange no-op rule, adoption-date
//  timezone stability, compact-surface fallbacks, and the widget contract.
//  (The adoptedOn write-once server rule needs the rules emulator and is
//  tracked separately.)
//

import Foundation
import Testing
@testable import MochiBuddy

@Suite("PetNameSanitizer")
struct PetNameSanitizerTests {

    @Test("sanitization table: classification per the spec", arguments: [
        // (raw, expected)
        ("Nori", "Nori"),                          // custom
        ("Mochi", "Mochi"),                        // default typed out
        ("", "Mochi"),                             // empty -> default
        ("   \n\t ", "Mochi"),                     // whitespace-only -> default
        ("  Nori  ", "Nori"),                      // trimmed
        ("No\u{0000}ri", "Nori"),                  // C0 control stripped
        ("No\u{202E}ri", "Nori"),                  // bidi override stripped
        ("No\u{2066}ri\u{2069}", "Nori"),          // bidi isolates stripped
        ("Nori\nBell", "Nori Bell"),               // line break -> collapsed space
        ("Nori    Bell", "Nori Bell"),             // internal runs collapse
        ("👩‍👩‍👧‍👦", "👩‍👩‍👧‍👦"),                 // ZWJ family survives intact
        ("👍🏽", "👍🏽"),                             // skin tone survives
        ("🇯🇵", "🇯🇵"),                             // flag survives
        ("é", "é"),                                // combining marks survive
        ("もちもち", "もちもち"),                     // CJK survives
        ("שלום", "שלום"),                          // RTL survives (minus controls)
    ])
    func sanitizationTable(raw: String, expected: String) {
        #expect(PetNameSanitizer.canonicalName(from: raw) == expected)
    }

    @Test("wrong-type (nil) falls back to the default")
    func nilFallsBack() {
        #expect(PetNameSanitizer.canonicalName(from: nil) == "Mochi")
    }

    @Test("overlong-valid input caps at 16 graphemes on grapheme boundaries")
    func overlongCaps() {
        let capped = PetNameSanitizer.canonicalName(from: String(repeating: "a", count: 40))
        #expect(capped.count == 16)

        // Emoji sequences count as ONE grapheme each and are never split.
        let emoji = String(repeating: "👩‍👩‍👧‍👦", count: 20)
        let cappedEmoji = PetNameSanitizer.canonicalName(from: emoji)
        #expect(cappedEmoji.count == 16)
        #expect(cappedEmoji == String(repeating: "👩‍👩‍👧‍👦", count: 16), "no corrupted tail sequence")
    }

    @Test("IME policy: marked text is never blocked; the cap applies to committed graphemes")
    func imePolicy() {
        let overCap = String(repeating: "も", count: 20)
        #expect(PetNameFieldPolicy.acceptsChange(proposed: overCap, hasMarkedText: true),
                "composition in flight must never be blocked")
        #expect(!PetNameFieldPolicy.acceptsChange(proposed: overCap, hasMarkedText: false))
        let atCap = String(repeating: "も", count: 16)
        #expect(PetNameFieldPolicy.acceptsChange(proposed: atCap, hasMarkedText: false))
    }
}

@Suite("AdoptedOnDate")
struct AdoptedOnDateTests {

    @Test("stamps the calendar date as seen in the given timezone")
    func stampPerZone() {
        // 2026-07-08 01:00 UTC is still 2026-07-07 in Los Angeles.
        var utc = Calendar(identifier: .gregorian)
        utc.timeZone = TimeZone(identifier: "UTC")!
        let instant = utc.date(from: DateComponents(year: 2026, month: 7, day: 8, hour: 1))!
        #expect(AdoptedOnDate.string(from: instant, in: TimeZone(identifier: "UTC")!) == "2026-07-08")
        #expect(AdoptedOnDate.string(from: instant, in: TimeZone(identifier: "America/Los_Angeles")!) == "2026-07-07")
    }

    @Test("validity: rolled-over and malformed dates are rejected")
    func validity() {
        #expect(AdoptedOnDate.isValid("2026-07-08"))
        #expect(!AdoptedOnDate.isValid("2026-02-30"), "Feb 30 must not roll to March")
        #expect(!AdoptedOnDate.isValid("2026-13-01"))
        #expect(!AdoptedOnDate.isValid("July 8, 2026"))
        #expect(!AdoptedOnDate.isValid("2026-7-8"))
        #expect(!AdoptedOnDate.isValid(""))
    }

    @Test("display renders the stored value verbatim - a timezone change never shifts it")
    func displayIsZoneStable() {
        let display = AdoptedOnDate.displayString("2026-07-08", locale: Locale(identifier: "en_US"))
        #expect(display == "July 8, 2026")
        // The function takes no timezone at all - stability by construction.
        // A malformed stored value renders as nothing, never broken copy.
        #expect(AdoptedOnDate.displayString("2026-02-30") == nil)
    }
}

@Suite("NotificationActionTitles")
struct NotificationActionTitlesTests {

    @Test("short names ride along; wide names fall back to verb-only")
    func compactBudget() {
        #expect(NotificationActionTitles.pet(petName: "Nori") == "Pet Nori")
        #expect(NotificationActionTitles.shh(petName: "Nori", hours: 24) == "Nori, shh · 24h")

        // 16 wide CJK graphemes blow the ~12-char budget.
        let wide = String(repeating: "も", count: 16)
        #expect(NotificationActionTitles.pet(petName: wide) == "Pet")
        #expect(NotificationActionTitles.shh(petName: wide, hours: 24) == "Shh · 24h")

        // Emoji sequences weigh double too.
        let emoji = String(repeating: "👩‍👩‍👧‍👦", count: 8)
        #expect(NotificationActionTitles.pet(petName: emoji) == "Pet")
    }

    @Test("the shh label always carries the tuned duration")
    func shhDuration() {
        #expect(NotificationActionTitles.shh(petName: "Nori", hours: 12) == "Nori, shh · 12h")
        let wide = String(repeating: "字", count: 16)
        #expect(NotificationActionTitles.shh(petName: wide, hours: 12) == "Shh · 12h")
    }
}

@Suite("UserProfile pet-identity decode")
struct PetIdentityDecodeTests {

    @Test("mapper classification: missing, wrong-type, overlong, malformed date")
    func mapperClassification() {
        let missing = UserProfileMapper.map(UserProfileDTO(id: "u", data: [:]))
        #expect(missing.mochiName == "Mochi")
        #expect(missing.adoptedOn == nil)

        let wrongType = UserProfileMapper.map(UserProfileDTO(id: "u", data: [
            "mochiName": 42, "adoptedOn": 42,
        ]))
        #expect(wrongType.mochiName == "Mochi")
        #expect(wrongType.adoptedOn == nil)

        let overlong = UserProfileMapper.map(UserProfileDTO(id: "u", data: [
            "mochiName": String(repeating: "z", count: 99),
            "adoptedOn": "2026-02-30",
        ]))
        #expect(overlong.mochiName.count == 16, "valid-but-overlong sanitizes and caps")
        #expect(overlong.adoptedOn == nil, "a malformed date never reaches the domain")

        let good = UserProfileMapper.map(UserProfileDTO(id: "u", data: [
            "mochiName": "Nori", "adoptedOn": "2026-07-08",
        ]))
        #expect(good.mochiName == "Nori")
        #expect(good.adoptedOn == "2026-07-08")
    }
}

@Suite("PetIdentityStore")
@MainActor
struct PetIdentityStoreTests {

    private final class RecordingPetTelemetry: PetIdentityTelemetry {
        private(set) var events: [PetIdentityTelemetryEvent] = []
        func log(_ event: PetIdentityTelemetryEvent) { events.append(event) }
    }

    private func makeStore(
        profileRepository: StubProfileRepository = StubProfileRepository(),
        telemetry: RecordingPetTelemetry? = nil
    ) -> (PetIdentityStore, StubProfileRepository, UserDefaults) {
        let defaults = UserDefaults(suiteName: "petIdentityTests-\(UUID().uuidString)")!
        let store = PetIdentityStore(
            profileRepository: profileRepository, telemetry: telemetry, defaults: defaults
        )
        return (store, profileRepository, defaults)
    }

    @Test("legacy migration: both fields persisted exactly once; second run is a no-op")
    func migrationRunsOnce() async {
        let repo = StubProfileRepository()
        repo.profile = makeProfile(createdAt: Dates.now)
        let (store, _, _) = makeStore(profileRepository: repo)

        await store.load(profile: repo.profile!, now: Dates.now)
        #expect(repo.savedMochiNames == ["Mochi"], "missing name backfilled and persisted")
        #expect(repo.stampedAdoptedOns.count == 1)
        #expect(repo.stampedAdoptedOns.first == AdoptedOnDate.string(from: Dates.now, in: .current),
                "adoptedOn backfills from createdAt in the current zone")

        await store.load(profile: repo.profile!, now: Dates.hours(24))
        #expect(repo.savedMochiNames.count == 1, "second run must not write again")
        #expect(repo.stampedAdoptedOns.count == 1)
    }

    @Test("interrupted onboarding backstop: adoptedOn stamped on arrival even after the flag is set")
    func adoptionBackstop() async {
        let repo = StubProfileRepository()
        repo.profile = makeProfile(createdAt: nil)
        let (store, _, defaults) = makeStore(profileRepository: repo)
        // Simulate a naming-beat-skipping build that set the flag but a
        // profile that somehow still lacks the date.
        defaults.set(true, forKey: "mochi.petIdentity.migrated.user1")

        await store.load(profile: repo.profile!, now: Dates.now)
        #expect(repo.stampedAdoptedOns.count == 1, "the field must always exist once home is reached")
        #expect(repo.savedMochiNames.isEmpty, "the flag still suppresses the name write")
    }

    @Test("naming beat: sanitize + persist, stamp adoptedOn, log the custom dimension only")
    func namingBeat() async {
        let telemetry = RecordingPetTelemetry()
        let repo = StubProfileRepository()
        repo.profile = makeProfile()
        let (store, _, _) = makeStore(profileRepository: repo, telemetry: telemetry)

        await store.completeNamingBeat(rawName: "  Nori  ", userId: "user1", now: Dates.now)
        #expect(store.name == "Nori")
        #expect(repo.savedMochiNames == ["Nori"])
        #expect(repo.stampedAdoptedOns == [AdoptedOnDate.string(from: Dates.now, in: .current)])
        guard case .petNamed(let custom)? = telemetry.events.first else {
            Issue.record("expected pet_named"); return
        }
        #expect(custom)
    }

    @Test("naming the pet Mochi logs custom=false - the metric keys off the value, not the button")
    func namingDefaultByTyping() async {
        let telemetry = RecordingPetTelemetry()
        let repo = StubProfileRepository()
        repo.profile = makeProfile()
        let (store, _, _) = makeStore(profileRepository: repo, telemetry: telemetry)

        await store.completeNamingBeat(rawName: "Mochi", userId: "user1", now: Dates.now)
        guard case .petNamed(let custom)? = telemetry.events.first else {
            Issue.record("expected pet_named"); return
        }
        #expect(!custom)
    }

    @Test("rename: a real change persists, fires the pipeline, and logs a count-only event")
    func renameFiresPipeline() async {
        let telemetry = RecordingPetTelemetry()
        let repo = StubProfileRepository()
        repo.profile = makeProfile()
        let (store, _, _) = makeStore(profileRepository: repo, telemetry: telemetry)
        await store.load(profile: repo.profile!, now: Dates.now)

        var pipelineNames: [String] = []
        store.onIdentityChanged = { pipelineNames.append($0) }

        let changed = await store.rename(to: "Nori", userId: "user1")
        #expect(changed)
        #expect(store.name == "Nori")
        #expect(repo.savedMochiNames.contains("Nori"))
        #expect(pipelineNames == ["Nori"])
        #expect(telemetry.events.contains { if case .petRenamed = $0 { true } else { false } })
    }

    @Test("no-op rename: same sanitized value writes nothing, propagates nothing, logs nothing")
    func noOpRename() async {
        let telemetry = RecordingPetTelemetry()
        let repo = StubProfileRepository()
        repo.profile = makeProfile(mochiName: "Nori", adoptedOn: "2026-07-01")
        let (store, _, _) = makeStore(profileRepository: repo, telemetry: telemetry)
        await store.load(profile: repo.profile!, now: Dates.now)
        let writesAfterLoad = repo.savedMochiNames.count

        var pipelineFired = false
        store.onIdentityChanged = { _ in pipelineFired = true }

        let changed = await store.rename(to: "  Nori ", userId: "user1")
        #expect(!changed)
        #expect(repo.savedMochiNames.count == writesAfterLoad)
        #expect(!pipelineFired)
        #expect(telemetry.events.isEmpty)
    }

    @Test("an existing adoptedOn is never restamped by load")
    func adoptedOnIsWriteOnceClientSide() async {
        let repo = StubProfileRepository()
        repo.profile = makeProfile(mochiName: "Nori", adoptedOn: "2026-07-01")
        let (store, _, _) = makeStore(profileRepository: repo)
        await store.load(profile: repo.profile!, now: Dates.now)
        #expect(repo.stampedAdoptedOns.isEmpty)
        #expect(store.adoptedOn == "2026-07-01")
    }
}

@Suite("Widget pet-identity contract")
struct WidgetPetIdentityTests {

    @Test("a pre-rename snapshot without mochiName still decodes and falls back to Mochi")
    func staleSnapshotDecodes() throws {
        let legacy = MochiWidgetState(
            displayState: .active, themeId: "sesame", baseline: [],
            hideTaskNames: false, nextTasks: [], vacationEnd: nil, lastComputed: Dates.now
        )
        var json = try JSONSerialization.jsonObject(
            with: JSONEncoder().encode(legacy)
        ) as! [String: Any]
        json.removeValue(forKey: "mochiName")
        let data = try JSONSerialization.data(withJSONObject: json)

        let decoded = try JSONDecoder().decode(MochiWidgetState.self, from: data)
        #expect(decoded.petDisplayName == "Mochi")
    }

    @Test("a named snapshot round-trips the name")
    func namedSnapshotRoundTrips() throws {
        let state = MochiWidgetState(
            displayState: .active, themeId: "sesame", mochiName: "Nori", baseline: [],
            hideTaskNames: false, nextTasks: [], vacationEnd: nil, lastComputed: Dates.now
        )
        let decoded = try JSONDecoder().decode(
            MochiWidgetState.self, from: JSONEncoder().encode(state)
        )
        #expect(decoded.petDisplayName == "Nori")
    }
}
