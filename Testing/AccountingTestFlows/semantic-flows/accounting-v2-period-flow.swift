import Foundation
import AccountingV2
import TestFlows

private func makeV2DatedEntry(
    fixture: V2JournalFixture,
    id: Int,
    time: TimeInterval,
    amount: Decimal,
    reversing: Bool = false
) throws -> Entry {
    let debit = try fixture.line(
        account: fixture.bank,
        direction: reversing ? .credit : .debit,
        amount: amount
    )
    let credit = try fixture.line(
        account: fixture.revenue,
        direction: reversing ? .debit : .credit,
        amount: amount
    )
    return try Entry(.init(
        id: Entry.ID(id),
        date: Date(timeIntervalSince1970: time),
        lines: [debit, credit]
    ))
}

extension AccountingTestFlowsSuite {
    static var accountingV2PeriodFlow: TestFlow {
        TestFlow("accounting-v2-period", tags: ["accounting", "v2", "period"]) {
            Step("period construction enforces finite ordered boundaries") {
                let fixture = try V2JournalFixture()
                let journal = try Journal(.init(
                    entries: [],
                    chart: fixture.chart,
                    entities: fixture.entities
                ))
                let ledger = try Ledger(.init(journal: journal))
                let start = Date(timeIntervalSince1970: 100)
                let end = Date(timeIntervalSince1970: 200)

                try Expect.throwsError("equal boundaries") {
                    _ = try Period(.init(ledger: ledger, start: start, end: start))
                }
                try Expect.throwsError("reversed boundaries") {
                    _ = try Period(.init(ledger: ledger, start: end, end: start))
                }
                try Expect.throwsError("non-finite start") {
                    _ = try Period(.init(
                        ledger: ledger,
                        start: Date(timeIntervalSince1970: .infinity),
                        end: end
                    ))
                }
                try Expect.throwsError("non-finite end") {
                    _ = try Period(.init(
                        ledger: ledger,
                        start: start,
                        end: Date(timeIntervalSince1970: .infinity)
                    ))
                }

                let period = try Period(.init(ledger: ledger, start: start, end: end))
                try Expect.equal(period.opening.postings.count, 0, "empty opening")
                try Expect.equal(period.movements.postings.count, 0, "empty movements")
                try Expect.equal(period.position.postings.count, 0, "empty position")
            }

            Step("half-open boundaries classify original postings correctly") {
                let fixture = try V2JournalFixture()
                let after = try makeV2DatedEntry(
                    fixture: fixture, id: 5, time: 250, amount: 50
                )
                let middle = try makeV2DatedEntry(
                    fixture: fixture, id: 3, time: 150, amount: 30
                )
                let before = try makeV2DatedEntry(
                    fixture: fixture, id: 1, time: 50, amount: 10
                )
                let atEnd = try makeV2DatedEntry(
                    fixture: fixture, id: 4, time: 200, amount: 40
                )
                let atStart = try makeV2DatedEntry(
                    fixture: fixture, id: 2, time: 100, amount: 20
                )
                let journal = try Journal(.init(
                    entries: [after, middle, before, atEnd, atStart],
                    chart: fixture.chart,
                    entities: fixture.entities
                ))
                let ledger = try Ledger(.init(journal: journal))
                let period = try Period(.init(
                    ledger: ledger,
                    start: Date(timeIntervalSince1970: 100),
                    end: Date(timeIntervalSince1970: 200)
                ))

                try Expect.equal(period.ledger.postings.count, 10, "source unchanged")
                try Expect.equal(period.opening.postings.count, 2, "before-start entries")
                try Expect.equal(period.movements.postings.count, 4, "within-window entries")
                try Expect.equal(period.position.postings.count, 6, "before-end entries")
                try Expect.equal(
                    period.opening.postings.map(\.source.entryID.value),
                    [1, 1],
                    "opening retains source identities"
                )
                try Expect.equal(
                    period.movements.postings.map(\.source.entryID.value),
                    [3, 3, 2, 2],
                    "movements retain journal order, not chronological sorting"
                )
                try Expect.equal(
                    period.position.postings.map(\.source.entryIndex),
                    [1, 1, 2, 2, 4, 4],
                    "position retains original entry offsets"
                )

                let bankOpening = period.opening.amount(for: fixture.bank)
                let bankMovement = period.movements.amount(for: fixture.bank)
                let bankPosition = period.position.amount(for: fixture.bank)
                try Expect.equal(bankOpening?.posted ?? -1, 10, "opening amount")
                try Expect.equal(bankMovement?.posted ?? -1, 50, "movement amount")
                try Expect.equal(bankPosition?.posted ?? -1, 60, "ending amount")
                try Expect.equal(
                    (bankOpening?.posted ?? -1) + (bankMovement?.posted ?? -1),
                    bankPosition?.posted ?? -1,
                    "opening plus movements equals position"
                )
                try Expect.equal(
                    period.opening.amount(for: fixture.revenue)?.posted ?? 1,
                    -10,
                    "credit-side opening remains signed"
                )
                try Expect.equal(
                    period.movements.amount(for: fixture.revenue)?.posted ?? 1,
                    -50,
                    "credit-side movements remain signed"
                )
                try Expect.equal(
                    period.position.amount(for: fixture.revenue)?.posted ?? 1,
                    -60,
                    "credit-side position remains signed"
                )
            }

            Step("account ancestry and entity filtering respect the selection") {
                let fixture = try V2JournalFixture()
                let before = try makeV2DatedEntry(
                    fixture: fixture, id: 1, time: 50, amount: 25
                )
                let during = try makeV2DatedEntry(
                    fixture: fixture, id: 2, time: 125, amount: 75
                )
                let journal = try Journal(.init(
                    entries: [before, during],
                    chart: fixture.chart,
                    entities: fixture.entities
                ))
                let period = try Period(.init(
                    ledger: Ledger(.init(journal: journal)),
                    start: Date(timeIntervalSince1970: 100),
                    end: Date(timeIntervalSince1970: 200)
                ))
                let root = try Account.Reference("B")

                try Expect.equal(
                    period.movements.amount(for: root)?.posted ?? -1,
                    0,
                    "ancestor has no original postings"
                )
                try Expect.equal(
                    period.movements.amount(for: root)?.descendants ?? -1,
                    75,
                    "descendant contributions are period-limited"
                )
                try Expect.equal(
                    period.position.amount(for: root, entity: fixture.owner)?.total ?? -1,
                    100,
                    "entity-specific ending position"
                )
                try Expect.equal(
                    period.movements.postings(at: root)?.count ?? -1,
                    0,
                    "exact-account postings remain distinct"
                )
                try Expect.equal(
                    period.movements.contributingPostings(to: root)?.count ?? -1,
                    1,
                    "rollup returns only in-period original postings"
                )
                try Expect.equal(
                    period.movements.postings(at: fixture.bank)?.count ?? -1,
                    1,
                    "period-specific direct posting membership"
                )
                let unknown = try Account.Reference("unknown")
                try Expect.equal(
                    period.position.amount(for: unknown) == nil,
                    true,
                    "unknown accounts remain distinguishable from zero"
                )
            }

            Step("zero-net movement preserves both reversing source postings") {
                let fixture = try V2JournalFixture()
                let before = try makeV2DatedEntry(
                    fixture: fixture, id: 1, time: 50, amount: 40
                )
                let forward = try makeV2DatedEntry(
                    fixture: fixture, id: 2, time: 120, amount: 100
                )
                let reverse = try makeV2DatedEntry(
                    fixture: fixture, id: 3, time: 150, amount: 100, reversing: true
                )
                let journal = try Journal(.init(
                    entries: [before, forward, reverse],
                    chart: fixture.chart,
                    entities: fixture.entities
                ))
                let period = try Period(.init(
                    ledger: Ledger(.init(journal: journal)),
                    start: Date(timeIntervalSince1970: 100),
                    end: Date(timeIntervalSince1970: 200)
                ))

                try Expect.equal(
                    period.movements.amount(for: fixture.bank)?.posted ?? -1,
                    0,
                    "opposing period postings cancel"
                )
                try Expect.equal(
                    period.position.amount(for: fixture.bank)?.posted ?? -1,
                    40,
                    "earlier opening position is preserved"
                )
                try Expect.equal(
                    period.movements.postings(at: fixture.bank)?.count ?? -1,
                    2,
                    "zero movement still has two original postings"
                )
                try Expect.equal(
                    period.movements.postings(at: fixture.bank)?.map(\.source.entryID.value) ?? [],
                    [2, 3],
                    "reversing source provenance is preserved"
                )
                try Expect.equal(
                    period.ledger.postings(for: fixture.bank).count,
                    3,
                    "full ledger remains authoritative"
                )
            }
        }
    }
}
