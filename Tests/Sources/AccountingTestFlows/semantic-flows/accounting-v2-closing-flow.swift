import Foundation
import AccountingV2
import AccountingV2Fixtures
import TestFlows

extension AccountingTestFlowsSuite {
    static var accountingV2ClosingFlow: TestFlow {
        TestFlow("accounting-v2-closing", tags: ["accounting", "v2", "closing"]) {
            Step("assesses profit and dividends separately with balanced effects") {
                let fixture = try V2ClosingFixture()
                let earlier = try fixture.entry(
                    id: 1, time: 50, debit: fixture.bank,
                    credit: fixture.revenue, amount: 900
                )
                let sale = try fixture.entry(
                    id: 2, debit: fixture.bank,
                    credit: fixture.revenue, amount: 200
                )
                let cost = try fixture.entry(
                    id: 3, debit: fixture.expenses,
                    credit: fixture.bank, amount: 75
                )
                let drawing = try fixture.entry(
                    id: 4, debit: fixture.dividends,
                    credit: fixture.bank, amount: 10
                )
                let later = try fixture.entry(
                    id: 5, time: 250, debit: fixture.bank,
                    credit: fixture.revenue, amount: 300
                )
                let period = try fixture.period([earlier, sale, cost, drawing, later])
                let audit = try Closing().evaluate(.init(
                    period: period,
                    equityAccount: fixture.equity
                ))

                try Expect.equal(audit.assessment.revenue, -200, "signed revenue")
                try Expect.equal(audit.assessment.expenses, 75, "signed expenses")
                try Expect.equal(audit.assessment.dividends, 10, "signed drawings")
                try Expect.equal(audit.assessment.netIncome, 125, "profit excludes drawings")
                try Expect.equal(audit.assessment.equityContribution, -115, "credit to equity")
                try Expect.equal(audit.decision, .proposed, "proposal only")
                try Expect.equal(audit.effects.count, 4, "three clearings and equity")
                try Expect.equal(
                    audit.effects.map(\.kind),
                    [.clearTemporary, .clearTemporary, .clearTemporary, .transferToEquity],
                    "distinct derived effect kinds"
                )
                try Expect.equal(
                    audit.effects.map(\.signedAmount),
                    [200, -75, -10, -115],
                    "signed effects conserve value"
                )
                try Expect.equal(audit.effectBalance, 0, "proposed effects balance")
                try Expect.equal(
                    audit.effects[0].sources.map(\.entryID.value),
                    [2],
                    "clearing points to original sale"
                )
                try Expect.equal(
                    audit.effects[3].sources.map(\.entryID.value),
                    [2, 3, 4],
                    "equity proposal points to all relevant temporary activity"
                )
                try Expect.equal(period.movements.postings.count, 6, "period source unaffected")
                try Expect.equal(period.ledger.postings.count, 10, "journal remains authoritative")
            }

            Step("a net loss transfers a debit to equity") {
                let fixture = try V2ClosingFixture()
                let sale = try fixture.entry(
                    id: 1, debit: fixture.bank,
                    credit: fixture.revenue, amount: 20
                )
                let cost = try fixture.entry(
                    id: 2, debit: fixture.expenses,
                    credit: fixture.bank, amount: 80
                )
                let audit = try Closing().evaluate(.init(
                    period: fixture.period([sale, cost]),
                    equityAccount: fixture.equity
                ))

                try Expect.equal(audit.assessment.netIncome, -60, "net loss")
                try Expect.equal(audit.assessment.equityContribution, 60, "debit equity")
                try Expect.equal(audit.effects.last?.signedAmount ?? -1, 60, "loss transfer")
                try Expect.equal(audit.effectBalance, 0, "loss effects balance")
            }

            Step("equity targets must be known, postable and categorized") {
                let fixture = try V2ClosingFixture()
                let period = try fixture.period([])
                let closing = Closing()
                let unknown = try Account.Reference("UNKNOWN")

                try Expect.throwsError("unknown equity destination") {
                    _ = try closing.evaluate(.init(
                        period: period, equityAccount: unknown
                    ))
                }
                try Expect.throwsError("heading is not a posting destination") {
                    _ = try closing.evaluate(.init(
                        period: period, equityAccount: fixture.heading
                    ))
                }
                try Expect.throwsError("revenue is not an equity destination") {
                    _ = try closing.evaluate(.init(
                        period: period, equityAccount: fixture.revenue
                    ))
                }
            }

            Step("zero-net temporary activity does not invent closing effects") {
                let fixture = try V2ClosingFixture()
                let sale = try fixture.entry(
                    id: 1, debit: fixture.bank,
                    credit: fixture.revenue, amount: 100
                )
                let reversal = try fixture.entry(
                    id: 2, debit: fixture.revenue,
                    credit: fixture.bank, amount: 100
                )
                let period = try fixture.period([sale, reversal])
                let audit = try Closing().evaluate(.init(
                    period: period, equityAccount: fixture.equity
                ))

                try Expect.equal(audit.assessment.revenue, 0, "signed reversal cancels")
                try Expect.equal(audit.decision, .notNeeded, "nothing to propose")
                try Expect.equal(audit.effects.count, 0, "no fabricated effects")
                try Expect.equal(period.movements.postings.count, 4, "history not erased")
            }

            Step("separate entities receive balanced closing proposals") {
                let fixture = try V2ClosingFixture()
                let first = try fixture.entry(
                    id: 1, entity: fixture.owner,
                    debit: fixture.bank, credit: fixture.revenue, amount: 50
                )
                let second = try fixture.entry(
                    id: 2, entity: fixture.secondOwner,
                    debit: fixture.bank, credit: fixture.revenue, amount: 80
                )
                let audit = try Closing().evaluate(.init(
                    period: fixture.period([first, second]),
                    equityAccount: fixture.equity
                ))
                let transfers = audit.effects.filter { $0.kind == .transferToEquity }

                try Expect.equal(transfers.count, 2, "separate entity transfers")
                try Expect.equal(transfers.map(\.entity), [fixture.owner, fixture.secondOwner], "entity identity")
                try Expect.equal(transfers.map(\.signedAmount), [-50, -80], "entity amounts")
                try Expect.equal(audit.assessment.netIncome, 130, "combined profit")
                try Expect.equal(audit.effectBalance, 0, "combined effects balance")

                for entity in [fixture.owner, fixture.secondOwner] {
                    let entityBalance = audit.effects
                        .filter { $0.entity == entity }
                        .reduce(Decimal.zero) { $0 + $1.signedAmount }
                    try Expect.equal(entityBalance, 0, "each entity balances independently")
                }
            }
        }
    }
}
