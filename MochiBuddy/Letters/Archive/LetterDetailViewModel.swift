//
//  LetterDetailViewModel.swift
//  MochiBuddy
//

import Foundation

final class LetterDetailViewModel: StateViewModel<
    LetterDetailBehavior.UIState,
    LetterDetailBehavior.ViewAction
> {

    let letter: Letter
    private let source: LetterOpenSource
    private let letterService: LetterCompositionService
    private let adoptedOn: String?

    init(
        letter: Letter,
        source: LetterOpenSource,
        letterService: LetterCompositionService,
        adoptedOn: String?
    ) {
        self.letter = letter
        self.source = source
        self.letterService = letterService
        self.adoptedOn = adoptedOn
        super.init(initialState: LetterDetailBehavior.UIState())
    }

    override func triggerAsync(_ action: LetterDetailBehavior.ViewAction) async {
        switch action {
        case .load:
            state.weekTitle = "Week of \(LetterArchiveViewModel.weekLabel(for: letter))"
            state.dateRangeText = Self.dateRange(for: letter)
            // The reader always sees the full variant - privacy applies to
            // what leaves the device, not to the author's own copy.
            state.bodyText = letter.fullRenderedText
            state.petName = letter.petNameSnapshot
            state.adoptionLine = adoptedOn
                .flatMap(Self.adoptionMonth(from:))
                .map { "With \(letter.petNameSnapshot) since \($0)" } ?? ""
            state.offersFullShare = letter.offersFullShareVariant
            await letterService.markOpened(letter, source: source)

        case .sharedTapped(let variant):
            letterService.logShared(variant: variant)
        }
    }

    /// "July 14 to July 20", in the letter's own zone.
    static func dateRange(for letter: Letter) -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: letter.timeZoneId) ?? .current
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.dateFormat = "MMMM d"
        let start = formatter.string(from: letter.periodStart)
        // The cutoff is exclusive; the covered span ends that day.
        let end = formatter.string(from: letter.periodEndExclusive)
        return "\(start) to \(end)"
    }

    /// "March 2026" from the date-only adoption stamp - rendered verbatim
    /// in UTC like every adoptedOn surface, no zone math ever.
    static func adoptionMonth(from adoptedOn: String) -> String? {
        guard let day = CivilDay(adoptedOn) else { return nil }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC") ?? .current
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.dateFormat = "MMMM yyyy"
        let anchor = Date(timeIntervalSince1970: TimeInterval(day.dayNumber) * 86_400 + 43_200)
        return formatter.string(from: anchor)
    }
}
