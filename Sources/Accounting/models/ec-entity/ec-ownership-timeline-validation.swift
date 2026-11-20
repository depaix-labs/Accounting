import Foundation
import Primitives

public enum OwnershipTimelineValidationError: LocalizedError, Sendable {
    case invalidPercentage(entity: String, date: Date, actual: Decimal, timeZone: TimeZone)
    case changeNotAfterInitial(entity: String, date: Date, initial: Date, timeZone: TimeZone)
    case duplicateChangeDate(entity: String, date: Date, timeZone: TimeZone)
    case invalidTotal(date: Date, actual: Decimal, timeZone: TimeZone)

    public var errorDescription: String? {
        switch self {
        case .invalidPercentage(let entity, let date, let actual, let timeZone):
            return "Ownership percentage for \(entity) at \(localDateString(date, timeZone: timeZone)) is \(actual); expected 0...100."
        case .changeNotAfterInitial(let entity, let date, let initial, let timeZone):
            return "Ownership change for \(entity) at \(localDateString(date, timeZone: timeZone)) is not after initial date \(localDateString(initial, timeZone: timeZone))."
        case .duplicateChangeDate(let entity, let date, let timeZone):
            return "Duplicate ownership change for \(entity) at \(localDateString(date, timeZone: timeZone))."
        case .invalidTotal(let date, let actual, let timeZone):
            return "Total ownership at \(localDateString(date, timeZone: timeZone)) is \(actual)%; expected exactly 100.00%."
        }
    }
}

public extension EntityStore {
    /// Validates each interval boundary. Between effective dates, ownership is constant.
    /// A store with no ownership histories has no global ownership allocation to validate.
    func validateOwnershipTimeline(timeZone: TimeZone) throws {
        let histories: [(name: String, equity: OwnerEquity)] = byFull.values.compactMap { def in
            guard let equity = def.ownerEquity else { return nil }
            return (def.key.identifier(displaying: .fullchain), equity)
        }.sorted { $0.name < $1.name }

        guard !histories.isEmpty else { return }

        var dates = Set<Date>()
        for (name, equity) in histories {
            dates.insert(equity.initial.date)
            var seenChanges = Set<Date>()
            for change in equity.changes {
                guard change.date > equity.initial.date else {
                    throw OwnershipTimelineValidationError.changeNotAfterInitial(
                        entity: name, date: change.date, initial: equity.initial.date, timeZone: timeZone
                    )
                }
                guard seenChanges.insert(change.date).inserted else {
                    throw OwnershipTimelineValidationError.duplicateChangeDate(
                        entity: name, date: change.date, timeZone: timeZone
                    )
                }
                dates.insert(change.date)
            }
        }

        let totalRule = Invariance<[Decimal]>([
            .allocation.totals_equal(to: 100)
        ])

        for date in dates.sorted() {
            var amounts: [Decimal] = []
            for (name, equity) in histories where equity.initial.date <= date {
                let percentage = equity.percentage(on: date)
                guard !percentage.isNaN, percentage >= 0, percentage <= 100 else {
                    throw OwnershipTimelineValidationError.invalidPercentage(
                        entity: name, date: date, actual: percentage, timeZone: timeZone
                    )
                }
                amounts.append(percentage)
            }

            guard totalRule.violations(for: amounts).isEmpty else {
                throw OwnershipTimelineValidationError.invalidTotal(
                    date: date, actual: amounts.reduce(Decimal.zero, +), timeZone: timeZone
                )
            }
        }
    }
}
