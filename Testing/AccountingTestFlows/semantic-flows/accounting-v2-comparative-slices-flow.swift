import Foundation
import AccountingV2
import AccountingV2Fixtures
import TestFlows

private func comparativeDate(_ value: String) throws -> Date {
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withFullDate]
    guard let date = formatter.date(from: value) else {
        throw V2ClosingFixture.SampleError.invalidDate(value)
    }
    return date
}

private func comparativeSelection(
    previousStart: String,
    previousEnd: String,
    currentStart: String,
    currentEnd: String
) throws -> MovementSelection {
    try MovementSelection(.init(source: .explicit([
        .init(
            role: .previous,
            start: comparativeDate(previousStart),
            end: comparativeDate(previousEnd)
        ),
        .init(
            role: .current,
            start: comparativeDate(currentStart),
            end: comparativeDate(currentEnd)
        )
    ])))
}

extension AccountingTestFlowsSuite {
    static var accountingV2ComparativeSlicesFlow: TestFlow {
        TestFlow("accounting-v2-comparative-slices", tags: ["accounting", "v2", "comparison"]) {
            Step("historical overlap does not double-count previous year") {
                let fixture = try V2ClosingFixture()
                let ledger = try fixture.sampleLedger()
                let selection = try comparativeSelection(
                    previousStart: "2025-01-01",
                    previousEnd: "2026-01-01",
                    currentStart: "2026-01-01",
                    currentEnd: "2027-01-01"
                )
                let slices = try ComparativeSlices(.init(
                    ledger: ledger, selection: selection
                ))

                try Expect.equal(slices.historical_before_previous.postings.count, 0, "no earlier fixture records")
                try Expect.equal(slices.previous.movements.postings.count, 2, "2025 source postings")
                try Expect.equal(slices.historical_before_current.postings.count, 2, "2025 is part of 2026 opening")
                try Expect.equal(slices.current.movements.postings.count, 8, "2026 movements")
                try Expect.equal(slices.current.recorded_position.postings.count, 10, "2025 and 2026 exactly once")
                try Expect.equal(slices.between.postings.count, 0, "contiguous years")
                try Expect.equal(ledger.postings.count, 12, "source retains future entry")

                try Expect.equal(slices.previous.movements.amount(for: fixture.bank)?.posted ?? -1, 40, "previous bank")
                try Expect.equal(slices.current.recorded_opening.amount(for: fixture.bank)?.posted ?? -1, 40, "current opening bank")
                try Expect.equal(slices.current.movements.amount(for: fixture.bank)?.posted ?? -1, 195, "current bank movements")
                try Expect.equal(slices.current.recorded_position.amount(for: fixture.bank)?.posted ?? -1, 235, "current cumulative bank")
                try Expect.equal(slices.current.recorded_position.amount(for: fixture.revenue)?.posted ?? 1, -320, "recorded revenue remains unclosed")
                try Expect.equal(slices.current.movements.amount(for: fixture.bank, entity: fixture.secondOwner)?.posted ?? -1, 80, "current owner-specific attribution")
                try Expect.equal(slices.previous.movements.amount(for: fixture.bank, entity: fixture.secondOwner)?.posted ?? -1, 0, "previous owner-specific attribution")

                try Expect.equal(
                    slices.previous.movements.postings.map { $0.source.entryID.value },
                    slices.historical_before_current.postings.map { $0.source.entryID.value },
                    "same source entry in two distinct reporting views"
                )
                try Expect.equal(
                    slices.current.recorded_position.postings.map { $0.source.entryID.value },
                    [1, 1, 2, 2, 3, 3, 4, 4, 5, 5],
                    "cumulative source order without duplicated membership"
                )
            }

            Step("both comparative views match independent Period calculations") {
                let fixture = try V2ClosingFixture()
                let ledger = try fixture.sampleLedger()
                let selection = try comparativeSelection(
                    previousStart: "2025-01-01",
                    previousEnd: "2026-01-01",
                    currentStart: "2026-01-01",
                    currentEnd: "2027-01-01"
                )
                let slices = try ComparativeSlices(.init(
                    ledger: ledger, selection: selection
                ))
                let comparisons: [(ComparativeSlices.View, Period)] = [
                    (slices.previous, try Period(.init(
                        ledger: ledger,
                        start: comparativeDate("2025-01-01"),
                        end: comparativeDate("2026-01-01")
                    ))),
                    (slices.current, try Period(.init(
                        ledger: ledger,
                        start: comparativeDate("2026-01-01"),
                        end: comparativeDate("2027-01-01")
                    )))
                ]

                for (view, period) in comparisons {
                    for account in fixture.accountOrder {
                        for entity: Entity.Reference? in [nil, fixture.owner, fixture.secondOwner] {
                            let pairs: [(Balances, Balances)] = [
                                (view.recorded_opening, period.opening),
                                (view.movements, period.movements),
                                (view.recorded_position, period.position)
                            ]
                            for (actual, expected) in pairs {
                                try Expect.equal(
                                    actual.amount(for: account, entity: entity)?.posted,
                                    expected.amount(for: account, entity: entity)?.posted,
                                    "direct account/entity parity"
                                )
                                try Expect.equal(
                                    actual.amount(for: account, entity: entity)?.total,
                                    expected.amount(for: account, entity: entity)?.total,
                                    "hierarchical account/entity parity"
                                )
                                try Expect.equal(
                                    actual.postings.map { $0.source.entryID },
                                    expected.postings.map { $0.source.entryID },
                                    "identical original posting membership"
                                )
                            }
                        }
                    }
                }
            }

            Step("earlier years are retained in both opening histories") {
                let fixture = try V2ClosingFixture()
                let original = try fixture.sampleLedger()
                let older = try fixture.entry(
                    id: 7,
                    time: comparativeDate("2024-04-10").timeIntervalSince1970,
                    debit: fixture.bank,
                    credit: fixture.revenue,
                    amount: 30
                )
                let journal = try Journal(.init(
                    entries: original.journal.entries + [older],
                    chart: fixture.chart,
                    entities: fixture.entities
                ))
                let ledger = try Ledger(.init(journal: journal))
                let selection = try comparativeSelection(
                    previousStart: "2025-01-01",
                    previousEnd: "2026-01-01",
                    currentStart: "2026-01-01",
                    currentEnd: "2027-01-01"
                )
                let slices = try ComparativeSlices(.init(
                    ledger: ledger, selection: selection
                ))

                try Expect.equal(slices.historical_before_previous.postings.count, 2, "2024 source history")
                try Expect.equal(slices.historical_before_current.postings.count, 4, "2024 and 2025 history")
                try Expect.equal(slices.historical_before_previous.amount(for: fixture.bank)?.posted ?? -1, 30, "previous opening")
                try Expect.equal(slices.previous.recorded_position.amount(for: fixture.bank)?.posted ?? -1, 70, "previous ending")
                try Expect.equal(slices.current.recorded_opening.amount(for: fixture.bank)?.posted ?? -1, 70, "current opening")
                try Expect.equal(slices.current.recorded_position.amount(for: fixture.bank)?.posted ?? -1, 265, "2024 through 2026 without replay")
                try Expect.equal(slices.current.recorded_position.postings.count, 12, "2027 excluded")
            }

            Step("noncontiguous comparisons retain intervening movements") {
                let fixture = try V2ClosingFixture()
                let original = try fixture.sampleLedger()
                let august = try fixture.entry(
                    id: 7,
                    time: comparativeDate("2026-08-01").timeIntervalSince1970,
                    debit: fixture.bank,
                    credit: fixture.revenue,
                    amount: 11
                )
                let journal = try Journal(.init(
                    entries: original.journal.entries + [august],
                    chart: fixture.chart,
                    entities: fixture.entities
                ))
                let ledger = try Ledger(.init(journal: journal))
                let selection = try comparativeSelection(
                    previousStart: "2026-07-01",
                    previousEnd: "2026-08-01",
                    currentStart: "2026-09-01",
                    currentEnd: "2026-10-01"
                )
                let slices = try ComparativeSlices(.init(
                    ledger: ledger, selection: selection
                ))

                try Expect.equal(slices.previous.movements.postings.count, 0, "empty July")
                try Expect.equal(slices.between.postings.count, 2, "August retained separately")
                try Expect.equal(slices.between.amount(for: fixture.bank)?.posted ?? -1, 11, "August movement")
                try Expect.equal(slices.previous.recorded_position.amount(for: fixture.bank)?.posted ?? -1, 165, "July ending")
                try Expect.equal(slices.current.recorded_opening.amount(for: fixture.bank)?.posted ?? -1, 176, "August included once")
                try Expect.equal(slices.current.movements.amount(for: fixture.bank)?.posted ?? -1, 80, "September only")
                try Expect.equal(slices.current.recorded_position.amount(for: fixture.bank)?.posted ?? -1, 256, "September cumulative")
                try Expect.equal(slices.current.movements.postings.map { $0.source.entryID.value }, [5, 5], "September boundary and identity")
                try Expect.equal(slices.between.postings.map { $0.source.entryID.value }, [7, 7], "August boundary and identity")
            }

            Step("comparison requires exactly two correctly ordered reporting roles") {
                let fixture = try V2ClosingFixture()
                let ledger = try fixture.sampleLedger()
                var calendar = Calendar(identifier: .gregorian)
                calendar.timeZone = TimeZone(identifier: "UTC") ?? .current
                let three = try MovementSelection(
                    anchor: comparativeDate("2026-10-15"),
                    unit: .month,
                    count: 3,
                    calendar: calendar
                )
                try Expect.throwsError("unsupported window count") {
                    _ = try ComparativeSlices(.init(
                        ledger: ledger, selection: three
                    ))
                }
                let unnamed = try MovementSelection(.init(source: .explicit([
                    .init(role: .named("earlier"),
                          start: comparativeDate("2025-01-01"),
                          end: comparativeDate("2026-01-01")),
                    .init(role: .current,
                          start: comparativeDate("2026-01-01"),
                          end: comparativeDate("2027-01-01"))
                ])))
                try Expect.throwsError("previous role required") {
                    _ = try ComparativeSlices(.init(
                        ledger: ledger, selection: unnamed
                    ))
                }
                let reversed = try MovementSelection(.init(source: .explicit([
                    .init(role: .current,
                          start: comparativeDate("2025-01-01"),
                          end: comparativeDate("2026-01-01")),
                    .init(role: .previous,
                          start: comparativeDate("2026-01-01"),
                          end: comparativeDate("2027-01-01"))
                ])))
                try Expect.throwsError("previous cannot follow current") {
                    _ = try ComparativeSlices(.init(
                        ledger: ledger, selection: reversed
                    ))
                }
            }
        }
    }
}
