//
//  MomentWriter.swift
//  MochiBuddy
//
//  The thin producer funnel for Journal moments (Feature 6). Resolves the
//  ambient context (uid, pet name, list names, locale) so producers stay
//  one-liners; all payload derivation lives in the pure MomentFactory.
//
//  Lapse gate: nothing composes during lapse - every writer here no-ops
//  while lapsed (the adoption moment doesn't route through this class; it
//  rides the onboarding/migration batch with `adoptedOn`).
//

import Foundation

@MainActor
final class MomentWriter {

    private let authRepository: AuthRepository
    private let momentRepository: MomentRepository
    private let petIdentityStore: PetIdentityStore
    private let listRepository: ListRepository
    private let membershipSession: MembershipSession
    private let calendar: Calendar

    init(
        authRepository: AuthRepository,
        momentRepository: MomentRepository,
        petIdentityStore: PetIdentityStore,
        listRepository: ListRepository,
        membershipSession: MembershipSession,
        calendar: Calendar = .current
    ) {
        self.authRepository = authRepository
        self.momentRepository = momentRepository
        self.petIdentityStore = petIdentityStore
        self.listRepository = listRepository
        self.membershipSession = membershipSession
        self.calendar = calendar
    }

    private var userId: String? {
        guard !membershipSession.isLapsed else { return nil }
        return authRepository.currentAccount?.uid
    }

    /// Streak milestone at its crossing edge (TaskCompletionStore's
    /// onMilestone hook). Date currency matches bestStreakAchievedOn:
    /// the device-local civil day the completion landed.
    func streakMilestone(count: Int, now: Date = .now) async {
        guard let userId else { return }
        let moment = MomentFactory.streakMilestone(
            count: count,
            day: AdoptedOnDate.string(from: now, in: calendar.timeZone),
            petName: petIdentityStore.name,
            locale: .current,
            now: now
        )
        await momentRepository.ensureMoment(moment, userId: userId)
    }

    /// Day-of anniversary. Written on detection regardless of banner
    /// suppression (a streak milestone may own the banner; the day still
    /// happened and the record keeps it).
    func anniversary(_ milestone: AnniversaryMilestone, now: Date = .now) async {
        guard let userId else { return }
        let moment = MomentFactory.anniversary(milestone, locale: .current, now: now)
        await momentRepository.ensureMoment(moment, userId: userId)
    }

    /// Vacation re-entry: the return moment (keyed by the synced interval
    /// start) plus the deferrable anniversaries the trip covered, each on
    /// its TRUE date. The re-entry day itself is excluded - a mark landing
    /// today surfaces normally, not as a memory.
    func vacationEnded(
        intervalStart: Date, end: Date, adoptedOn: String?, now: Date = .now
    ) async {
        guard let userId else { return }
        let endDay = AdoptedOnDate.string(from: end, in: calendar.timeZone)
        await momentRepository.ensureMoment(
            MomentFactory.vacationReturn(
                intervalStart: intervalStart,
                endDay: endDay,
                petName: petIdentityStore.name,
                locale: .current,
                now: now
            ),
            userId: userId
        )
        let startDay = CivilDay(of: intervalStart, in: calendar)
        let lastCoveredDay = CivilDay(of: end, in: calendar).advanced(by: -1)
        for milestone in AnniversaryCalendar.milestones(
            adoptedOn: adoptedOn, from: startDay, through: lastCoveredDay
        ) where milestone.tier.deferrable {
            await momentRepository.ensureMoment(
                MomentFactory.anniversary(milestone, locale: .current, now: now),
                userId: userId
            )
        }
    }

    /// A qualified Feature 4 list-return event. Once-per-event is the
    /// natural key itself; the list's name is resolved and frozen here,
    /// as of the event.
    func listReturn(_ observation: QualifiedObservation, now: Date = .now) async {
        guard let userId,
              case .listReturn(let listId) = observation.conclusion,
              let list = try? await listRepository.fetchLists(userId: userId)
                  .first(where: { $0.id == listId })
        else { return }
        let moment = MomentFactory.listReturn(
            listId: listId,
            firedOn: observation.stableSince,
            listName: list.name,
            locale: .current,
            now: now
        )
        await momentRepository.ensureMoment(moment, userId: userId)
    }

    /// Synthesis repair (spec edge 2): the Journal found `adoptedOn` with
    /// no adoption document - enqueue the idempotent, legacy-safe write.
    /// Deliberately allowed while lapsed: this repairs an existing fact's
    /// record, it composes nothing new.
    func ensureAdoptionMoment(adoptedOn: String, now: Date = .now) async {
        guard let userId = authRepository.currentAccount?.uid else { return }
        let moment = MomentFactory.adoption(
            adoptedOn: adoptedOn, petName: nil, locale: .current, now: now
        )
        await momentRepository.ensureMoment(moment, userId: userId)
    }
}
