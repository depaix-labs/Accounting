import Foundation
import AccountingV2
import AccountingV2Fixtures
import TestFlows

extension AccountingTestFlowsSuite {
    static var accountingV2CompositionFlow: TestFlow {
        TestFlow("accounting-v2-composition", tags: ["accounting", "v2", "composition"]) {
            Step("recorded selection excludes unaccepted closing proposals") {
                let fixture = try V2ClosingFixture()
                let sale = try fixture.entry(
                    id: 1, debit: fixture.bank,
                    credit: fixture.revenue, amount: 200
                )
                let period = try fixture.period([sale])
                let audit = try Closing().evaluate(.init(
                    period: period, equityAccount: fixture.equity
                ))
                let composition = try Composition(.init(selection: .recorded(period)))

                try Expect.equal(audit.effects.count, 2, "proposal exists independently")
                try Expect.equal(composition.effects.count, 0, "proposal not selected")
                try Expect.equal(
                    composition.breakdown(for: fixture.revenue)?.recorded.posted ?? 1,
                    -200,
                    "recorded revenue"
                )
                try Expect.equal(
                    composition.breakdown(for: fixture.revenue)?.calculated.posted ?? 1,
                    0,
                    "no calculated revenue effect"
                )
                try Expect.equal(
                    composition.amount(for: fixture.revenue)?.posted ?? 1,
                    -200,
                    "recorded-only result"
                )
                try Expect.equal(
                    composition.effects(at: fixture.revenue)?.count ?? -1,
                    0,
                    "no accepted effect"
                )
            }

            Step("accepted closing effects produce traceable adjusted amounts") {
                let fixture = try V2ClosingFixture()
                let sale = try fixture.entry(
                    id: 1, debit: fixture.bank,
                    credit: fixture.revenue, amount: 200
                )
                let cost = try fixture.entry(
                    id: 2, debit: fixture.expenses,
                    credit: fixture.bank, amount: 75
                )
                let drawing = try fixture.entry(
                    id: 3, debit: fixture.dividends,
                    credit: fixture.bank, amount: 10
                )
                let period = try fixture.period([sale, cost, drawing])
                let audit = try Closing().evaluate(.init(
                    period: period, equityAccount: fixture.equity
                ))
                let composition = try Composition(.init(
                    selection: .accept_closing(audit)
                ))

                try Expect.equal(composition.effects.count, 4, "each effect once")
                try Expect.equal(
                    composition.breakdown(for: fixture.revenue)?.recorded.posted ?? 1,
                    -200,
                    "recorded revenue"
                )
                try Expect.equal(
                    composition.breakdown(for: fixture.revenue)?.calculated.posted ?? -1,
                    200,
                    "derived revenue clearing"
                )
                try Expect.equal(
                    composition.amount(for: fixture.revenue)?.posted ?? -1,
                    0,
                    "revenue cleared in derived result"
                )
                try Expect.equal(
                    composition.amount(for: fixture.expenses)?.posted ?? -1,
                    0,
                    "expenses cleared"
                )
                try Expect.equal(
                    composition.amount(for: fixture.dividends)?.posted ?? -1,
                    0,
                    "drawings cleared"
                )
                try Expect.equal(
                    composition.breakdown(for: fixture.equity)?.calculated.posted ?? 1,
                    -115,
                    "signed equity transfer"
                )
                try Expect.equal(
                    composition.amount(for: fixture.equity)?.posted ?? 1,
                    -115,
                    "equity adjusted without journal mutation"
                )
                try Expect.equal(
                    composition.amount(for: fixture.bank)?.posted ?? -1,
                    115,
                    "bank source position unchanged"
                )
                try Expect.equal(
                    composition.amount(for: fixture.heading)?.total ?? -1,
                    0,
                    "account tree stays balanced"
                )
                try Expect.equal(
                    composition.contributingEffects(to: fixture.heading)?.count ?? -1,
                    4,
                    "parent can inspect every calculated effect"
                )
                try Expect.equal(
                    composition.effects(at: fixture.revenue)?.first?.sources.map(\.entryID.value) ?? [],
                    [1],
                    "calculated contribution retains original source"
                )
                try Expect.equal(
                    composition.period.ledger.postings.count,
                    6,
                    "original posting count unaffected"
                )
                try Expect.equal(
                    period.position.amount(for: fixture.revenue)?.posted ?? 1,
                    -200,
                    "original period remains unchanged"
                )
            }

            Step("closing affects the selected period, not historical recorded activity") {
                let fixture = try V2ClosingFixture()
                let earlier = try fixture.entry(
                    id: 1, time: 50, debit: fixture.bank,
                    credit: fixture.revenue, amount: 900
                )
                let current = try fixture.entry(
                    id: 2, debit: fixture.bank,
                    credit: fixture.revenue, amount: 200
                )
                let period = try fixture.period([earlier, current])
                let audit = try Closing().evaluate(.init(
                    period: period, equityAccount: fixture.equity
                ))
                let composition = try Composition(.init(
                    selection: .accept_closing(audit)
                ))

                try Expect.equal(
                    composition.breakdown(for: fixture.revenue)?.recorded.posted ?? 1,
                    -1100,
                    "recorded position includes earlier period"
                )
                try Expect.equal(
                    composition.breakdown(for: fixture.revenue)?.calculated.posted ?? -1,
                    200,
                    "only current movements close"
                )
                try Expect.equal(
                    composition.amount(for: fixture.revenue)?.posted ?? 1,
                    -900,
                    "historical temporary activity is not silently reset"
                )
                try Expect.equal(
                    composition.effects(at: fixture.revenue)?.first?.sources.map(\.entryID.value) ?? [],
                    [2],
                    "prior-period posting excluded from closing sources"
                )
            }

            Step("calculation effects remain independently balanced per entity") {
                let fixture = try V2ClosingFixture()
                let first = try fixture.entry(
                    id: 1, entity: fixture.owner,
                    debit: fixture.bank, credit: fixture.revenue, amount: 50
                )
                let second = try fixture.entry(
                    id: 2, entity: fixture.secondOwner,
                    debit: fixture.bank, credit: fixture.revenue, amount: 80
                )
                let period = try fixture.period([first, second])
                let audit = try Closing().evaluate(.init(
                    period: period, equityAccount: fixture.equity
                ))
                let composition = try Composition(.init(
                    selection: .accept_closing(audit)
                ))

                try Expect.equal(
                    composition.amount(for: fixture.equity, entity: fixture.owner)?.posted ?? 1,
                    -50,
                    "first entity equity transfer"
                )
                try Expect.equal(
                    composition.amount(for: fixture.equity, entity: fixture.secondOwner)?.posted ?? 1,
                    -80,
                    "second entity equity transfer"
                )
                try Expect.equal(
                    composition.amount(for: fixture.equity)?.posted ?? 1,
                    -130,
                    "combined equity transfer"
                )
                try Expect.equal(
                    composition.effects(at: fixture.equity, entity: fixture.owner)?.count ?? -1,
                    1,
                    "entity-specific effect provenance"
                )
                try Expect.equal(
                    composition.amount(for: fixture.heading, entity: fixture.owner)?.total ?? -1,
                    0,
                    "first entity remains balanced"
                )
                try Expect.equal(
                    composition.amount(for: fixture.heading, entity: fixture.secondOwner)?.total ?? -1,
                    0,
                    "second entity remains balanced"
                )
            }

            Step("zero-net history and unknown references remain distinguishable") {
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
                let composition = try Composition(.init(
                    selection: .accept_closing(audit)
                ))
                let unknown = try Account.Reference("UNKNOWN")

                try Expect.equal(composition.effects.count, 0, "zero-net needs no effects")
                try Expect.equal(
                    composition.amount(for: fixture.revenue)?.posted ?? -1,
                    0,
                    "zero-net result"
                )
                try Expect.equal(
                    composition.period.position.postings(at: fixture.revenue)?.count ?? -1,
                    2,
                    "recorded history survives zero net"
                )
                try Expect.equal(
                    composition.breakdown(for: unknown) == nil,
                    true,
                    "unknown account is not a zero account"
                )
                try Expect.equal(
                    composition.effects(at: unknown) == nil,
                    true,
                    "unknown account cannot receive effects"
                )
            }
        }
    }
}
