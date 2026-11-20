import AccountingV2
import AccountingV2Fixtures
import Foundation
import TestFlows

private func equityDate(_ value: String) throws -> Date {
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withFullDate]
    guard let date = formatter.date(from: value) else {
        throw V2ClosingFixture.SampleError.invalidDate(value)
    }
    return date
}

private func equityPrior(
    _ fixture: V2ClosingFixture,
    ledger: Ledger
) throws -> Equity.Anchor {
    let period = try Period(.init(
        ledger: ledger,
        start: equityDate("2025-01-01"),
        end: equityDate("2026-01-01")
    ))
    let closing = try Closing().evaluate(.init(
        period: period, equityAccount: fixture.equity
    ))
    let composition = try Composition(.init(selection: .accept_closing(closing)))
    let compilation = try Compilation(.init(
        composition: composition, opening: .recorded
    ))
    let state = try PositionState(
        compilation: compilation,
        provenance: Provenance(
            result: Provenance.Identifier("synthetic.equity.prior"),
            inputs: []
        )
    )
    return try Equity.Anchor(position: state, account: fixture.equity)
}

private func equityOwnership(_ fixture: V2ClosingFixture) throws -> Ownership.Structure {
    let inception = try equityDate("2025-01-01")
    let transition = try equityDate("2026-07-01")
    let first = try Ownership.History(
        owner: fixture.owner,
        initial: Ownership.State(
            effectiveFrom: inception, share: Ownership.Share(percent: 60)
        ),
        changes: [Ownership.Change(state: Ownership.State(
            effectiveFrom: transition, share: Ownership.Share(percent: 40)
        ))]
    )
    let second = try Ownership.History(
        owner: fixture.secondOwner,
        initial: Ownership.State(
            effectiveFrom: inception, share: Ownership.Share(percent: 40)
        ),
        changes: [Ownership.Change(state: Ownership.State(
            effectiveFrom: transition, share: Ownership.Share(percent: 60)
        ))]
    )
    return try Ownership.Structure(portfolio: Ownership.Portfolio(
        entities: fixture.entities, histories: [first, second]
    ))
}

private func equityCurrent(_ ledger: Ledger) throws -> Period {
    try Period(.init(
        ledger: ledger,
        start: equityDate("2026-01-01"),
        end: equityDate("2027-01-01")
    ))
}

private func equityProfit(
    _ fixture: V2ClosingFixture,
    period: Period
) throws -> Ownership.Allocation.Result {
    try Ownership.Allocation().evaluate(.init(
        period: period,
        ownership: equityOwnership(fixture),
        policy: .init(basis: .timeline)
    ))
}

extension AccountingTestFlowsSuite {
    static var accountingV2EquityRollforwardFlow: TestFlow {
        TestFlow("accounting-v2-equity-rollforward", tags: ["accounting", "v2", "equity"]) {
            Step("accepted prior equity and allocated profit conserve owner capital") {
                let fixture = try V2ClosingFixture()
                let ledger = try fixture.sampleLedger()
                let anchor = try equityPrior(fixture, ledger: ledger)
                let allocation = try equityProfit(fixture, period: equityCurrent(ledger))
                let result = try Equity.Rollforward().evaluate(.init(
                    anchor: anchor,
                    allocation: allocation,
                    drawings: [fixture.dividends]
                ))
                try Expect.equal(anchor.total, 40, "accepted opening")
                try Expect.equal(result.opening, 40, "opening capital")
                try Expect.equal(result.profit, 205, "allocated income")
                try Expect.equal(result.drawings, 10, "owner withdrawals")
                try Expect.equal(result.contributions, 0, "no contributions")
                try Expect.equal(result.closing, 235, "total capital conserved")
                try Expect.equal(result.positions[fixture.owner]?.closing, 137, "owner A")
                try Expect.equal(result.positions[fixture.secondOwner]?.closing, 98, "owner B")
                try Expect.equal(result.movements.map(\.source.entryID.value), [4], "original drawing source")
                try Expect.equal(result.allocation.segments.count, 2, "time-based profit retained")
                try Expect.equal(ledger.postings.count, 12, "recorded source unchanged")
            }

            Step("recorded contribution is included once and remains traceable") {
                let fixture = try V2ClosingFixture()
                let original = try fixture.sampleLedger()
                let investment = try fixture.entry(
                    id: 7,
                    time: equityDate("2026-08-01").timeIntervalSince1970,
                    entity: fixture.secondOwner,
                    debit: fixture.bank,
                    credit: fixture.equity,
                    amount: 50
                )
                let journal = try Journal(.init(
                    entries: original.journal.entries + [investment],
                    chart: fixture.chart,
                    entities: fixture.entities
                ))
                let ledger = try Ledger(.init(journal: journal))
                let anchor = try equityPrior(fixture, ledger: ledger)
                let allocation = try equityProfit(fixture, period: equityCurrent(ledger))
                let result = try Equity.Rollforward().evaluate(.init(
                    anchor: anchor,
                    allocation: allocation,
                    contributions: [fixture.equity],
                    drawings: [fixture.dividends]
                ))
                try Expect.equal(result.contributions, 50, "recorded owner B contribution")
                try Expect.equal(result.profit, 205, "capital posting not income")
                try Expect.equal(result.closing, 285, "opening + contribution - drawing + profit")
                try Expect.equal(result.positions[fixture.secondOwner]?.closing, 148, "B own recorded capital")
                try Expect.equal(result.movements.map(\.source.entryID.value), [4, 7], "source order")
                try Expect.equal(result.movements.map(\.amount), [10, 50], "signed movement convention")
            }

            Step("invalid anchors, classifications and boundaries reject") {
                let fixture = try V2ClosingFixture()
                let ledger = try fixture.sampleLedger()
                let anchor = try equityPrior(fixture, ledger: ledger)
                let allocation = try equityProfit(fixture, period: equityCurrent(ledger))
                try Expect.throwsError("asset account is not an owner capital anchor") {
                    _ = try Equity.Anchor(position: anchor.position, account: fixture.bank)
                }
                try Expect.throwsError("bank cannot be a contribution account") {
                    _ = try Equity.Rollforward().evaluate(.init(
                        anchor: anchor,
                        allocation: allocation,
                        contributions: [fixture.bank]
                    ))
                }
                try Expect.throwsError("revenue cannot be a drawing account") {
                    _ = try Equity.Rollforward().evaluate(.init(
                        anchor: anchor,
                        allocation: allocation,
                        drawings: [fixture.revenue]
                    ))
                }
                let shifted = try Period(.init(
                    ledger: ledger,
                    start: equityDate("2026-02-01"),
                    end: equityDate("2027-01-01")
                ))
                let shiftedAllocation = try equityProfit(fixture, period: shifted)
                try Expect.throwsError("different boundary cannot use this accepted opening") {
                    _ = try Equity.Rollforward().evaluate(.init(
                        anchor: anchor,
                        allocation: shiftedAllocation
                    ))
                }
            }
        }
    }
}
