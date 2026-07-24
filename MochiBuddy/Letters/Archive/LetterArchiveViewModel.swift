//
//  LetterArchiveViewModel.swift
//  MochiBuddy
//

import Foundation

final class LetterArchiveViewModel: ObservableStateViewModel<
    LetterArchiveBehavior.UIState,
    LetterArchiveBehavior.ViewAction,
    LetterArchiveBehavior.NavigationEvent
> {

    private let authRepository: AuthRepository
    private let letterRepository: LetterRepository
    private let petIdentityStore: PetIdentityStore

    private var letters: [Letter] = []

    init(
        authRepository: AuthRepository,
        letterRepository: LetterRepository,
        petIdentityStore: PetIdentityStore
    ) {
        self.authRepository = authRepository
        self.letterRepository = letterRepository
        self.petIdentityStore = petIdentityStore
        super.init(initialState: LetterArchiveBehavior.UIState())
    }

    override func triggerAsync(_ action: LetterArchiveBehavior.ViewAction) async {
        switch action {
        case .load:
            defer { state.isLoading = false }
            guard let userId = authRepository.currentAccount?.uid else { return }
            letters = (try? await letterRepository.letters(userId: userId)) ?? []
            state.petName = petIdentityStore.name
            state.rows = letters.map(Self.row(for:))
            state.showEmptyState = letters.isEmpty

        case .letterTapped(let id):
            guard let letter = letters.first(where: { $0.id == id }) else { return }
            setNavigationEvent(.openLetter(letter))
        }
    }

    static func row(for letter: Letter) -> LetterArchiveBehavior.LetterRow {
        LetterArchiveBehavior.LetterRow(
            id: letter.id,
            title: "Week of \(Self.weekLabel(for: letter))",
            snippet: letter.privateRenderedText
                .split(separator: "\n", omittingEmptySubsequences: true)
                .first.map(String.init) ?? "",
            isUnread: letter.isUnread
        )
    }

    /// The period's Monday, rendered in the zone the letter was composed
    /// in - a postcard's date never shifts with the reader's travels.
    static func weekLabel(for letter: Letter) -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: letter.timeZoneId) ?? .current
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.dateFormat = "MMMM d"
        return formatter.string(from: letter.periodStart)
    }
}
