import AccountingV2
import AccountingV2Fixtures
import Foundation
import TestFlows

private func correctionDate(_ value: String) throws -> Date {
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withFullDate]
    guard let date = formatter.date(from: value) else {
        throw V2ClosingFixture.SampleError.invalidDate(value)
    }
    return date
}

private func correctionChart(
    _ fixture: V2ClosingFixture,
    additional: [Account],
    parents: [Account.Reference: Account.Reference]
) throws -> Chart {
    var edges: [Account.Reference: Account.Reference] = [:]
    for account in fixture.accountOrder where account != fixture.heading {
        edges[account] = fixture.heading
    }
    for (child, parent) in parents {
        edges[child] = parent
    }
    return try Chart(.init(
        accounts: fixture.accountOrder.compactMap { fixture.chart.account($0) } + additional,
        roots: [fixture.heading],
        parents: edges,
        behavior: .init(carryforward: .identity)
    ))
}

private func correctionLine(
    _ fixture: V2ClosingFixture,
    chart: Chart,
    account: Account.Reference,
    owner: Entity.Reference,
    direction: AccountingV2.Direction,
    amount: Decimal
) throws -> Entry.Line {
    try Entry.Line(.init(
        account: account, entity: owner, direction: direction, amount: amount,
        chart: chart, entities: fixture.entities
    ))
}

private func correctionLedger(
    _ fixture: V2ClosingFixture,
    chart: Chart,
    entry: Entry
) throws -> Ledger {
    let original = try fixture.sampleLedger()
    let journal = try Journal(.init(
        entries: original.journal.entries + [entry],
        chart: chart,
        entities: fixture.entities
    ))
    return try Ledger(.init(journal: journal))
}

private func correctionAnchor(
    _ fixture: V2ClosingFixture,
    ledger: Ledger
) throws -> Equity.Anchor {
    let prior = try Period(.init(
        ledger: ledger,
        start: correctionDate("2025-01-01"),
        end: correctionDate("2026-01-01")
    ))
    let closing = try Closing().evaluate(.init(
        period: prior, equityAccount: fixture.equity
    ))
    let composition = try Composition(.init(selection: .accept_closing(closing)))
    let compilation = try Compilation(.init(
        composition: composition, opening: .recorded
    ))
    let position = try PositionState(
        compilation: compilation,
        provenance: Provenance(
            result: Provenance.Identifier("synthetic.equity.correctness"),
            inputs: []
        )
    )
    return try Equity.Anchor(position: position, account: fixture.equity)
}

private func correctionProfit(
    _ fixture: V2ClosingFixture,
    ledger: Ledger,
    posted: Ownership.Allocation.PostedPolicy = .ignore
) throws -> Ownership.Allocation.Result {
    let inception = try correctionDate("2025-01-01")
    let first = try Ownership.History(
        owner: fixture.owner,
        initial: Ownership.State(
            effectiveFrom: inception, share: Ownership.Share(percent: 60)
        )
    )
    let second = try Ownership.History(
        owner: fixture.secondOwner,
        initial: Ownership.State(
            effectiveFrom: inception, share: Ownership.Share(percent: 40)
        )
    )
    let ownership = try Ownership.Structure(portfolio: Ownership.Portfolio(
        entities: fixture.entities, histories: [first, second]
    ))
    let period = try Period(.init(
        ledger: ledger,
        start: correctionDate("2026-01-01"),
        end: correctionDate("2027-01-01")
    ))
    return try Ownership.Allocation().evaluate(.init(
        period: period,
        ownership: ownership,
        policy: .init(basis: .timeline, posted: posted)
    ))
}

extension AccountingTestFlowsSuite {
    static var accountingV2EquityClassificationFlow: TestFlow {
        TestFlow("accounting-v2-equity-classification", tags: ["accounting", "v2", "equity"]) {
            Step("parent selections include descendant capital and drawing postings") {
                let fixture = try V2ClosingFixture()
                let capital = try Account(.init(
                    code: "CAPITAL.CHILD", category: .equity, postable: true
                ))
                let withdrawal = try Account(.init(
                    code: "DRAWING.CHILD", category: .dividends, postable: true
                ))
                let chart = try correctionChart(
                    fixture,
                    additional: [capital, withdrawal],
                    parents: [
                        capital.reference: fixture.equity,
                        withdrawal.reference: fixture.dividends
                    ]
                )
                let entry = try Entry(.init(
                    id: Entry.ID(7),
                    date: correctionDate("2026-11-01"),
                    lines: [
                        correctionLine(fixture, chart: chart, account: fixture.bank,
                            owner: fixture.secondOwner, direction: .debit, amount: 50),
                        correctionLine(fixture, chart: chart, account: capital.reference,
                            owner: fixture.secondOwner, direction: .credit, amount: 50),
                        correctionLine(fixture, chart: chart, account: withdrawal.reference,
                            owner: fixture.owner, direction: .debit, amount: 12),
                        correctionLine(fixture, chart: chart, account: fixture.bank,
                            owner: fixture.owner, direction: .credit, amount: 12)
                    ]
                ))
                let ledger = try correctionLedger(fixture, chart: chart, entry: entry)
                let result = try Equity.Rollforward().evaluate(.init(
                    anchor: correctionAnchor(fixture, ledger: ledger),
                    allocation: correctionProfit(fixture, ledger: ledger),
                    contributions: [fixture.equity],
                    drawings: [fixture.dividends]
                ))
                try Expect.equal(result.contributions, 50, "descendant capital detected")
                try Expect.equal(result.drawings, 22, "original and descendant drawings")
                try Expect.equal(result.profit, 205, "income excludes capital movements")
                try Expect.equal(result.closing, 273, "capital conservation")
                try Expect.equal(result.movements.map(\.account), [
                    fixture.dividends, capital.reference, withdrawal.reference
                ], "original leaf references preserved")
                try Expect.equal(result.movements.map(\.source.entryID.value), [4, 7, 7],
                    "journal line provenance preserved")
            }

            Step("separate lines in one entry are not duplicate profit") {
                let fixture = try V2ClosingFixture()
                let profitShare = try Account(.init(
                    code: "PROFIT.POSTED", category: .equity, postable: true
                ))
                let chart = try correctionChart(
                    fixture,
                    additional: [profitShare],
                    parents: [profitShare.reference: fixture.heading]
                )
                let entry = try Entry(.init(
                    id: Entry.ID(7),
                    date: correctionDate("2026-08-01"),
                    lines: [
                        correctionLine(fixture, chart: chart, account: fixture.bank,
                            owner: fixture.owner, direction: .debit, amount: 255),
                        correctionLine(fixture, chart: chart, account: fixture.equity,
                            owner: fixture.owner, direction: .credit, amount: 50),
                        correctionLine(fixture, chart: chart, account: profitShare.reference,
                            owner: fixture.owner, direction: .credit, amount: 205)
                    ]
                ))
                let ledger = try correctionLedger(fixture, chart: chart, entry: entry)
                let anchor = try correctionAnchor(fixture, ledger: ledger)
                let allocation = try correctionProfit(
                    fixture, ledger: ledger,
                    posted: .prefer(account: profitShare.reference, mismatch: .reject)
                )
                let result = try Equity.Rollforward().evaluate(.init(
                    anchor: anchor,
                    allocation: allocation,
                    contributions: [fixture.equity],
                    drawings: [fixture.dividends]
                ))
                try Expect.equal(result.contributions, 50, "nonprofit line remains contribution")
                try Expect.equal(result.profit, 205, "posted profit reconciles")
                try Expect.equal(result.closing, 285, "same-entry sources counted once")
                try Expect.equal(result.movements.map(\.source.lineIndex), [0, 1],
                    "drawing and contribution use their actual lines")
                try Expect.equal(allocation.posted.map(\.source.lineIndex), [2],
                    "posted profit uses distinct line")
                try Expect.throwsError("actual posted profit line cannot be a contribution") {
                    _ = try Equity.Rollforward().evaluate(.init(
                        anchor: anchor,
                        allocation: allocation,
                        contributions: [profitShare.reference]
                    ))
                }
            }
        }
    }
}
