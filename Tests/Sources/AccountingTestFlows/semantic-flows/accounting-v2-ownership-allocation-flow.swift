import AccountingV2
import AccountingV2Fixtures
import Foundation
import TestFlows

private func allocationDate(_ string: String) throws -> Date {
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withFullDate]
    guard let date = formatter.date(from: string) else {
        throw V2ClosingFixture.SampleError.invalidDate(string)
    }
    return date
}

private func allocationOwnership(
    _ fixture: V2ClosingFixture,
    changing: Bool = true,
    firstPercent: Decimal = 60,
    secondPercent: Decimal = 40
) throws -> Ownership.Structure {
    let start = try allocationDate("2025-01-01")
    let changeDate = try allocationDate("2026-07-01")
    let first = try Ownership.History(
        owner: fixture.owner,
        initial: Ownership.State(
            effectiveFrom: start,
            share: Ownership.Share(percent: firstPercent)
        ),
        changes: changing ? [Ownership.Change(state: Ownership.State(
            effectiveFrom: changeDate,
            share: Ownership.Share(percent: 40)
        ))] : []
    )
    let second = try Ownership.History(
        owner: fixture.secondOwner,
        initial: Ownership.State(
            effectiveFrom: start,
            share: Ownership.Share(percent: secondPercent)
        ),
        changes: changing ? [Ownership.Change(state: Ownership.State(
            effectiveFrom: changeDate,
            share: Ownership.Share(percent: 60)
        ))] : []
    )
    let portfolio = try Ownership.Portfolio(
        entities: fixture.entities, histories: [first, second]
    )
    return try Ownership.Structure(portfolio: portfolio)
}

private func allocationPeriod(_ fixture: V2ClosingFixture) throws -> Period {
    try Period(.init(
        ledger: fixture.sampleLedger(),
        start: allocationDate("2026-01-01"),
        end: allocationDate("2027-01-01")
    ))
}

/// Construct a designated profit-allocation account independently of the
/// existing closing fixture so ordinary EQUITY is never treated as AOW.
private func allocationPostedPeriod(
    _ fixture: V2ClosingFixture,
    first: Decimal,
    second: Decimal
) throws -> (period: Period, account: Account.Reference) {
    let rootAccount = try Account(.init(code: "ROOT", postable: false))
    let profitShare = try Account(.init(
        code: "PROFIT_SHARE", category: .equity, postable: true
    ))
    let accounts = try [
        rootAccount,
        Account(.init(code: "BANK", category: .assets, postable: true)),
        Account(.init(code: "REVENUE", category: .revenue, postable: true)),
        Account(.init(code: "EXPENSE", category: .expenses, postable: true)),
        Account(.init(code: "DRAWINGS", category: .dividends, postable: true)),
        Account(.init(code: "EQUITY", category: .equity, postable: true)),
        profitShare
    ]
    let root = rootAccount.reference
    let chart = try Chart(.init(
        accounts: accounts,
        roots: [root],
        parents: Dictionary(uniqueKeysWithValues: accounts.dropFirst().map {
            ($0.reference, root)
        }),
        behavior: .init(carryforward: .identity)
    ))
    let destination = profitShare.reference

    func entry(id: Int, owner: Entity.Reference, amount: Decimal) throws -> Entry {
        let debit = try Entry.Line(.init(
            account: fixture.equity,
            entity: owner,
            direction: .debit,
            amount: amount,
            chart: chart,
            entities: fixture.entities
        ))
        let credit = try Entry.Line(.init(
            account: destination,
            entity: owner,
            direction: .credit,
            amount: amount,
            chart: chart,
            entities: fixture.entities
        ))
        return try Entry(.init(
            id: Entry.ID(id),
            date: allocationDate("2026-11-01"),
            lines: [debit, credit]
        ))
    }

    let journal = try Journal(.init(
        entries: fixture.sampleLedger().journal.entries + [
            entry(id: 7, owner: fixture.owner, amount: first),
            entry(id: 8, owner: fixture.secondOwner, amount: second)
        ],
        chart: chart,
        entities: fixture.entities
    ))
    return (try Period(.init(
        ledger: Ledger(.init(journal: journal)),
        start: allocationDate("2026-01-01"),
        end: allocationDate("2027-01-01")
    )), destination)
}

/// Synthetic case: a nonterminal owner enters mid-period, and its entire
/// declared entitlement is redirected through an explicit collapse rule.
private func allocationCollapsingOwnership(
    _ fixture: V2ClosingFixture
) throws -> Ownership.Structure {
    let start = try allocationDate("2025-01-01")
    let change = try allocationDate("2026-07-01")
    let first = try Ownership.History(
        owner: fixture.owner,
        initial: Ownership.State(
            effectiveFrom: start, share: Ownership.Share(percent: 100)
        ),
        changes: [Ownership.Change(state: Ownership.State(
            effectiveFrom: change, share: Ownership.Share(percent: 60)
        ))]
    )
    let second = try Ownership.History(
        owner: fixture.secondOwner,
        initial: Ownership.State(
            effectiveFrom: start, share: Ownership.Share(percent: 0)
        ),
        changes: [Ownership.Change(
            state: Ownership.State(
                effectiveFrom: change, share: Ownership.Share(percent: 40)
            ),
            divisions: [Ownership.Division(
                recipient: fixture.owner, share: Ownership.Share(percent: 100)
            )]
        )]
    )
    let portfolio = try Ownership.Portfolio(
        entities: fixture.entities, histories: [first, second]
    )
    return try Ownership.Structure(
        portfolio: portfolio, collapsing: [fixture.secondOwner]
    )
}

extension AccountingTestFlowsSuite {
    static var accountingV2OwnershipAllocationFlow: TestFlow {
        TestFlow("accounting-v2-ownership-allocation", tags: ["accounting", "v2", "ownership"]) {
            Step("snapshot and timeline allocate using different ownership states") {
                let fixture = try V2ClosingFixture()
                let period = try allocationPeriod(fixture)
                let owners = try allocationOwnership(fixture)
                let closing = try Closing().evaluate(.init(
                    period: period, equityAccount: fixture.equity
                ))
                let calculation = Ownership.Allocation()

                let snapshot = try calculation.evaluate(.init(
                    period: period, ownership: owners,
                    policy: .init(basis: .snapshot(try allocationDate("2026-12-31")))
                ))
                let timeline = try calculation.evaluate(.init(
                    period: period, ownership: owners,
                    policy: .init(basis: .timeline)
                ))

                try Expect.equal(closing.assessment.netIncome, 205, "closing NI excludes drawings")
                try Expect.equal(snapshot.netIncome, 205, "same source NI")
                try Expect.equal(timeline.netIncome, 205, "same NI across segments")
                try Expect.equal(snapshot.amounts[fixture.owner], 82, "year-end share A")
                try Expect.equal(snapshot.amounts[fixture.secondOwner], 123, "year-end share B")
                try Expect.equal(timeline.amounts[fixture.owner], 107, "segmented A")
                try Expect.equal(timeline.amounts[fixture.secondOwner], 98, "segmented B")
                try Expect.equal(timeline.segments.count, 2, "two ownership intervals")
                try Expect.equal(timeline.segments.map(\.netIncome), [125, 80], "income allocated at actual changes")
                try Expect.equal(timeline.segments.map(\.sources.count), [2, 1], "source lines retained")
                try Expect.equal(timeline.segments[0].sources.map(\.entryID.value), [2, 3], "first segment sources")
                try Expect.equal(timeline.segments[1].sources.map(\.entryID.value), [5], "second segment sources")
                try Expect.equal(snapshot.remainder, 0, "snapshot conserves NI")
                try Expect.equal(timeline.remainder, 0, "timeline conserves NI")
                try Expect.equal(timeline.posted.count, 0, "no invented posted allocations")
                try Expect.equal(period.ledger.postings.count, 12, "journal unchanged")
            }

            Step("reconciled posted owner amounts take precedence") {
                let fixture = try V2ClosingFixture()
                let (period, account) = try allocationPostedPeriod(
                    fixture, first: 107, second: 98
                )
                let result = try Ownership.Allocation().evaluate(.init(
                    period: period,
                    ownership: allocationOwnership(fixture),
                    policy: .init(
                        basis: .snapshot(try allocationDate("2026-12-31")),
                        posted: .prefer(account: account, mismatch: .reject)
                    )
                ))

                try Expect.equal(result.decision, .posted, "posted decision")
                try Expect.equal(result.netIncome, 205, "NI unaffected by capital entries")
                try Expect.equal(result.amounts[fixture.owner], 107, "posted A wins")
                try Expect.equal(result.amounts[fixture.secondOwner], 98, "posted B wins")
                try Expect.equal(result.postedDifference, 0, "posted reconciliation")
                try Expect.equal(result.posted.map(\.source.entryID.value), [7, 8], "source postings")
                try Expect.equal(result.posted.map(\.amount), [107, 98], "credit is positive profit")
                try Expect.equal(result.segments.count, 0, "no competing derived allocation")
            }

            Step("mismatched posted amounts are never silently accepted") {
                let fixture = try V2ClosingFixture()
                let (period, account) = try allocationPostedPeriod(
                    fixture, first: 106, second: 98
                )
                let ownership = try allocationOwnership(fixture)
                let reject = Ownership.Allocation.Policy(
                    basis: .snapshot(try allocationDate("2026-12-31")),
                    posted: .prefer(account: account, mismatch: .reject)
                )
                try Expect.throwsError("strict posting reconciliation") {
                    _ = try Ownership.Allocation().evaluate(.init(
                        period: period, ownership: ownership, policy: reject
                    ))
                }

                let fallback = try Ownership.Allocation().evaluate(.init(
                    period: period,
                    ownership: ownership,
                    policy: .init(
                        basis: .snapshot(try allocationDate("2026-12-31")),
                        posted: .prefer(account: account, mismatch: .fallback)
                    )
                ))
                try Expect.equal(fallback.postedDifference, 1, "explicit discrepancy retained")
                try Expect.equal(fallback.posted.count, 2, "rejected postings still inspectable")
                try Expect.equal(fallback.amounts[fixture.owner], 82, "declared fallback A")
                try Expect.equal(fallback.amounts[fixture.secondOwner], 123, "declared fallback B")
                try Expect.equal(fallback.remainder, 0, "fallback conserves income")
            }

            Step("losses and strict ownership validation") {
                let fixture = try V2ClosingFixture()
                let sale = try fixture.entry(
                    id: 1, debit: fixture.bank, credit: fixture.revenue, amount: 20
                )
                let expense = try fixture.entry(
                    id: 2, debit: fixture.expenses, credit: fixture.bank, amount: 80
                )
                let period = try fixture.period([sale, expense])
                let referenceDate = try allocationDate("2026-05-01")
                let ownership = try allocationOwnership(fixture, changing: false)
                let loss = try Ownership.Allocation().evaluate(.init(
                    period: period,
                    ownership: ownership,
                    policy: .init(basis: .snapshot(referenceDate))
                ))
                try Expect.equal(loss.netIncome, -60, "negative NI")
                try Expect.equal(loss.amounts[fixture.owner], -36, "owner A loss")
                try Expect.equal(loss.amounts[fixture.secondOwner], -24, "owner B loss")
                try Expect.equal(loss.remainder, 0, "negative result reconciles")

                try Expect.throwsError("incomplete ownership rejected before allocation") {
                    _ = try allocationOwnership(
                        fixture, changing: false, firstPercent: 30, secondPercent: 20
                    )
                }
            }

            Step("derived profit distinguishes declared and effective collapse") {
                let fixture = try V2ClosingFixture()
                let period = try allocationPeriod(fixture)
                let ownership = try allocationCollapsingOwnership(fixture)
                let calculation = Ownership.Allocation()
                let declared = try calculation.evaluate(.init(
                    period: period, ownership: ownership,
                    policy: .init(basis: .timeline, attribution: .declared)
                ))
                let effective = try calculation.evaluate(.init(
                    period: period, ownership: ownership,
                    policy: .init(basis: .timeline, attribution: .effective)
                ))
                try Expect.equal(declared.segments.count, 2, "two synthetic regimes")
                try Expect.equal(effective.segments.count, 2, "two effective regimes")
                try Expect.equal(declared.amounts[fixture.owner], 173, "declared owner A")
                try Expect.equal(declared.amounts[fixture.secondOwner], 32, "declared owner B")
                try Expect.equal(effective.amounts[fixture.owner], 205, "collapsed owner B redirects its share")
                try Expect.equal(effective.amounts[fixture.secondOwner] == nil, true, "no unassigned collapsed portion")
                try Expect.equal(effective.segments[1].declared[fixture.secondOwner], Decimal(2) / 5, "declared preserved")
                try Expect.equal(effective.segments[1].effective[fixture.owner], 1, "effective view retained")
                try Expect.equal(declared.remainder, 0, "declared conserves income")
                try Expect.equal(effective.remainder, 0, "effective conserves income")
                try Expect.equal(period.ledger.postings.count, 12, "source ledger is unchanged")
            }

            Step("effective dates do not follow reporting boundaries") {
                let fixture = try V2ClosingFixture()
                let period = try allocationPeriod(fixture)
                let ownership = try allocationOwnership(fixture)
                let output = try Ownership.Allocation().evaluate(.init(
                    period: period,
                    ownership: ownership,
                    policy: .init(basis: .timeline)
                ))
                try Expect.equal(output.segments.count, 2, "two effective-date segments")
                try Expect.equal(output.segments[0].start, period.start, "calendar start retained")
                try Expect.equal(output.segments[0].end, allocationDate("2026-07-01"), "actual ownership boundary")
                try Expect.equal(output.segments[1].start, allocationDate("2026-07-01"), "change inclusive")
                try Expect.equal(output.segments[1].end, period.end, "calendar end retained")
                try Expect.equal(output.segments[0].shares[fixture.owner], Decimal(6) / 10, "prior shares")
                try Expect.equal(output.segments[1].shares[fixture.owner], Decimal(4) / 10, "new shares")
            }
        }
    }
}
