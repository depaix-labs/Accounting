import AccountingV2
import AccountingV2Fixtures
import Foundation
import TestFlows

private func reattributionDate(_ value: String) throws -> Date {
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withFullDate]
    guard let date = formatter.date(from: value) else {
        throw V2ClosingFixture.SampleError.invalidDate(value)
    }
    return date
}

private struct ReattributionFixture {
    let projection: Equity.Projection.Result
    let first: Entity.Reference
    let second: Entity.Reference
    let pool: Entity.Reference
    let ledger: Ledger
}

private func reattributionFixture(
    loss: Bool = false, boundaryPosting: Bool = false
) throws -> ReattributionFixture {
    let fixture = try V2ClosingFixture()
    let pool = try Entity.Reference(
        class: "person", family: "owner", alias: Entity.Alias(name: "synthetic-pool")
    )
    let entities = try Entities([
        Entity(.init(reference: fixture.owner)),
        Entity(.init(reference: fixture.secondOwner)),
        Entity(.init(reference: pool))
    ])

    func entry(
        _ id: Int,
        _ date: String,
        owner: Entity.Reference,
        debit: Account.Reference,
        credit: Account.Reference,
        amount: Decimal
    ) throws -> Entry {
        let lines = try [
            Entry.Line(.init(
                account: debit, entity: owner, direction: .debit,
                amount: amount, chart: fixture.chart, entities: entities
            )),
            Entry.Line(.init(
                account: credit, entity: owner, direction: .credit,
                amount: amount, chart: fixture.chart, entities: entities
            ))
        ]
        return try Entry(.init(
            id: Entry.ID(id), date: reattributionDate(date), lines: lines
        ))
    }

    var entries = try [
        entry(1, "2025-12-02", owner: pool,
              debit: fixture.bank, credit: fixture.equity, amount: 99),
        entry(2, "2025-12-10", owner: fixture.owner,
              debit: fixture.bank, credit: fixture.revenue, amount: 40),
        entry(3, "2026-04-15", owner: fixture.owner,
              debit: loss ? fixture.expenses : fixture.bank,
              credit: loss ? fixture.bank : fixture.revenue, amount: 100)
    ]
    if boundaryPosting {
        entries.append(try entry(
            4, "2026-07-01", owner: fixture.owner,
            debit: fixture.bank, credit: fixture.revenue, amount: 100
        ))
    }
    let ledger = try Ledger(.init(journal: Journal(.init(
        entries: entries, chart: fixture.chart, entities: entities
    ))))
    let prior = try Period(.init(
        ledger: ledger,
        start: reattributionDate("2025-01-01"),
        end: reattributionDate("2026-01-01")
    ))
    let closing = try Closing().evaluate(.init(
        period: prior, equityAccount: fixture.equity
    ))
    let compilation = try Compilation(.init(
        composition: Composition(.init(selection: .accept_closing(closing))),
        opening: .recorded
    ))
    let position = try PositionState(
        compilation: compilation,
        provenance: Provenance(
            result: Provenance.Identifier("synthetic.reattribution.anchor"),
            inputs: []
        )
    )
    let anchor = try Equity.Anchor(position: position, account: fixture.equity)

    let inception = try reattributionDate("2025-01-01")
    let current = try reattributionDate("2026-01-01")
    let switchDate = try reattributionDate("2026-07-01")
    func state(_ date: Date, _ percent: Decimal) throws -> Ownership.State {
        try Ownership.State(effectiveFrom: date, share: Ownership.Share(percent: percent))
    }
    let first = try Ownership.History(
        owner: fixture.owner,
        initial: state(inception, 80),
        changes: [Ownership.Change(state: state(current, 60))]
    )
    let second = try Ownership.History(
        owner: fixture.secondOwner,
        initial: state(inception, 20)
    )
    let pooled = try Ownership.History(
        owner: pool,
        initial: state(inception, 0),
        changes: [
            Ownership.Change(
                state: state(current, 20),
                divisions: [Ownership.Division(
                    recipient: fixture.owner, share: Ownership.Share(percent: 100)
                )]
            ),
            Ownership.Change(
                state: state(switchDate, 20),
                divisions: [Ownership.Division(
                    recipient: fixture.secondOwner, share: Ownership.Share(percent: 100)
                )]
            )
        ]
    )
    let structure = try Ownership.Structure(
        portfolio: Ownership.Portfolio(
            entities: entities, histories: [first, second, pooled]
        ),
        collapsing: [pool]
    )
    let period = try Period(.init(
        ledger: ledger,
        start: current,
        end: reattributionDate("2027-01-01")
    ))
    let allocation = try Ownership.Allocation().evaluate(.init(
        period: period, ownership: structure,
        policy: .init(basis: .timeline, attribution: .effective)
    ))
    let rollforward = try Equity.Rollforward().evaluate(.init(
        anchor: anchor, allocation: allocation
    ))
    let projection = try Equity.Projection().evaluate(.init(rollforward: rollforward))
    return ReattributionFixture(
        projection: projection, first: fixture.owner,
        second: fixture.secondOwner, pool: pool, ledger: ledger
    )
}

extension AccountingTestFlowsSuite {
    static var accountingV2EquityContinuityFlow: TestFlow {
        TestFlow("accounting-v2-equity-continuity", tags: ["accounting", "v2", "equity"]) {
            Step("route switch reattributes existing capital without journal movement") {
                let fixture = try reattributionFixture()
                let result = fixture.projection
                try Expect.equal(result.segments.count, 2, "two ownership windows")
                let before = result.segments[0]
                let after = result.segments[1]
                try Expect.equal(before.directClosing[fixture.pool], 99, "pool retains recorded capital")
                try Expect.equal(after.directClosing[fixture.pool], 99, "recorded capital stays unchanged")
                try Expect.equal(before.effectiveClosing[fixture.first], 219, "initial recipient")
                try Expect.equal(before.effectiveClosing[fixture.second], 20, "other owner's profit")
                try Expect.equal(after.effectiveOpening[fixture.first], 120, "capital leaves first recipient")
                try Expect.equal(after.effectiveOpening[fixture.second], 119, "capital reaches second recipient")
                try Expect.equal(after.transitionAdjustments[fixture.first], -99, "outgoing reattribution")
                try Expect.equal(after.transitionAdjustments[fixture.second], 99, "incoming reattribution")
                try Expect.equal(after.transitionAdjustments.values.reduce(Decimal.zero, +), 0, "zero-sum boundary")
                try Expect.equal(after.movements.isEmpty, true, "no journal movement at switch")
                try Expect.equal(after.profit.values.reduce(Decimal.zero, +), 0, "no new income at switch")
                try Expect.equal(result.directTotal, 239, "recorded plus earned profit")
                try Expect.equal(result.effectiveTotal, 239, "effective conservation")
                try Expect.equal(result.adjustmentTotal, 0, "closing adjustments conserve")
                try Expect.equal(fixture.ledger.postings.count, 6, "original six source lines only")
            }

            Step("postings on the transition date use the new beneficiary route") {
                let fixture = try reattributionFixture(boundaryPosting: true)
                let result = fixture.projection
                let before = result.segments[0]
                let after = result.segments[1]
                try Expect.equal(before.profit[fixture.first], 80, "earlier profit uses old route")
                try Expect.equal(before.profit[fixture.second], 20, "earlier second owner share")
                try Expect.equal(after.profit[fixture.first], 60, "boundary profit uses new route")
                try Expect.equal(after.profit[fixture.second], 40, "boundary pool routes to B")
                try Expect.equal(after.profitSources.count, 1, "boundary income source assigned once")
                try Expect.equal(after.transitionAdjustments[fixture.first], -99, "boundary adjustment excludes profit")
                try Expect.equal(after.transitionAdjustments[fixture.second], 99, "capital-only switch")
                try Expect.equal(after.effectiveClosing[fixture.first], 180, "old profit stays with A")
                try Expect.equal(after.effectiveClosing[fixture.second], 159, "new profit and capital reach B")
                try Expect.equal(result.directTotal, 339, "both profit events included")
                try Expect.equal(result.effectiveTotal, 339, "both regimes conserve")
                try Expect.equal(fixture.ledger.postings.count, 8, "four source entries only")
            }

            Step("negative prior profit remains with its earned beneficiaries") {
                let fixture = try reattributionFixture(loss: true)
                let result = fixture.projection
                let before = result.segments[0]
                let after = result.segments[1]
                try Expect.equal(before.profit[fixture.first], -80, "signed loss allocated first")
                try Expect.equal(before.profit[fixture.second], -20, "signed loss allocated second")
                try Expect.equal(after.directClosing[fixture.pool], 99, "recorded pool unaffected")
                try Expect.equal(after.transitionAdjustments[fixture.first], -99, "capital switches, not loss")
                try Expect.equal(after.transitionAdjustments[fixture.second], 99, "capital switches, not loss")
                try Expect.equal(after.profit.values.reduce(Decimal.zero, +), 0, "loss not allocated again")
                try Expect.equal(after.effectiveClosing[fixture.first], -40, "first retains its loss")
                try Expect.equal(after.effectiveClosing[fixture.second], 79, "second receives capital and retains loss")
                try Expect.equal(result.directTotal, 39, "loss reduces total")
                try Expect.equal(result.effectiveTotal, 39, "negative amount conserves")
                try Expect.equal(result.adjustmentTotal, 0, "closing differences sum to zero")
            }
        }
    }
}
