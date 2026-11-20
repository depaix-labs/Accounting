import Foundation
import AccountingV2
import AccountingV2Fixtures
import TestFlows

private struct V2CompilationFixture {
    let root: Account
    let group: Account
    let child: Account
    let cash: Account
    let opening: Account
    let owner: Entity.Reference
    let entities: Entities

    init() throws {
        root = try Account(.init(code: "ROOT", postable: false))
        group = try Account(.init(code: "GROUP", category: .assets, postable: true))
        child = try Account(.init(code: "CHILD", category: .assets, postable: true))
        cash = try Account(.init(code: "CASH", category: .assets, postable: true))
        opening = try Account(.init(code: "OPEN", category: .assets, postable: false))
        owner = try Entity.Reference(
            class: "person", family: "owner", alias: Entity.Alias(name: "owner")
        )
        entities = try Entities([Entity(.init(reference: owner))])
    }

    func chart(behavior: Chart.Behavior) throws -> Chart {
        try Chart(.init(
            accounts: [root, group, child, cash, opening],
            roots: [root.reference],
            parents: [
                group.reference: root.reference,
                child.reference: group.reference,
                cash.reference: root.reference,
                opening.reference: root.reference
            ],
            behavior: behavior
        ))
    }

    func entry(
        id: Int,
        time: TimeInterval,
        debit: Account.Reference,
        credit: Account.Reference,
        amount: Decimal,
        chart: Chart
    ) throws -> Entry {
        let debitLine = try Entry.Line(.init(
            account: debit,
            entity: owner,
            direction: .debit,
            amount: amount,
            chart: chart,
            entities: entities
        ))
        let creditLine = try Entry.Line(.init(
            account: credit,
            entity: owner,
            direction: .credit,
            amount: amount,
            chart: chart,
            entities: entities
        ))
        return try Entry(.init(
            id: Entry.ID(id),
            date: Date(timeIntervalSince1970: time),
            lines: [debitLine, creditLine]
        ))
    }

    func period(chart: Chart, entries: [Entry]) throws -> Period {
        let journal = try Journal(.init(
            entries: entries,
            chart: chart,
            entities: entities
        ))
        let ledger = try Ledger(.init(journal: journal))
        return try Period(.init(
            ledger: ledger,
            start: Date(timeIntervalSince1970: 100),
            end: Date(timeIntervalSince1970: 200)
        ))
    }
}

extension AccountingTestFlowsSuite {
    static var accountingV2CompilationFlow: TestFlow {
        TestFlow("accounting-v2-compilation", tags: ["accounting", "v2", "compilation"]) {
            Step("recorded opening equals existing composed position") {
                let fixture = try V2ClosingFixture()
                let earlier = try fixture.entry(
                    id: 1, time: 50, debit: fixture.bank,
                    credit: fixture.revenue, amount: 40
                )
                let sale = try fixture.entry(
                    id: 2, debit: fixture.bank,
                    credit: fixture.revenue, amount: 100
                )
                let cost = try fixture.entry(
                    id: 3, debit: fixture.expenses,
                    credit: fixture.bank, amount: 25
                )
                let period = try fixture.period([earlier, sale, cost])
                let composition = try Composition(.init(selection: .recorded(period)))
                let compilation = try Compilation(.init(
                    composition: composition,
                    opening: .recorded
                ))
                let bank = compilation.breakdown(for: fixture.bank)

                try Expect.equal(bank?.recorded_opening.posted ?? -1, 40, "earlier activity")
                try Expect.equal(bank?.opening.posted ?? -1, 40, "unrouted opening")
                try Expect.equal(bank?.movements.posted ?? -1, 75, "current movements")
                try Expect.equal(bank?.calculated.posted ?? -1, 0, "no selected effects")
                try Expect.equal(bank?.recorded.posted ?? -1, 115, "original position")
                try Expect.equal(bank?.routing_delta.posted ?? -1, 0, "no reclassification")
                try Expect.equal(bank?.result.posted ?? -1, 115, "compiled position")
                try Expect.equal(
                    compilation.amount(for: fixture.bank)?.posted ?? -1,
                    composition.amount(for: fixture.bank)?.posted ?? -2,
                    "recorded compilation and composition agree"
                )
                try Expect.equal(compilation.routing == nil, true, "routing not selected")
            }

            Step("accepted closing is added once after recorded opening and movements") {
                let fixture = try V2ClosingFixture()
                let earlier = try fixture.entry(
                    id: 1, time: 50, debit: fixture.bank,
                    credit: fixture.revenue, amount: 40
                )
                let sale = try fixture.entry(
                    id: 2, debit: fixture.bank,
                    credit: fixture.revenue, amount: 100
                )
                let cost = try fixture.entry(
                    id: 3, debit: fixture.expenses,
                    credit: fixture.bank, amount: 25
                )
                let period = try fixture.period([earlier, sale, cost])
                let audit = try Closing().evaluate(.init(
                    period: period,
                    equityAccount: fixture.equity
                ))
                let composition = try Composition(.init(selection: .accept_closing(audit)))
                let compilation = try Compilation(.init(
                    composition: composition,
                    opening: .carryforward
                ))

                try Expect.equal(
                    compilation.breakdown(for: fixture.revenue)?.recorded_opening.posted ?? 1,
                    -40,
                    "historical revenue remains a source fact"
                )
                try Expect.equal(
                    compilation.breakdown(for: fixture.revenue)?.movements.posted ?? 1,
                    -100,
                    "current revenue movement"
                )
                try Expect.equal(
                    compilation.breakdown(for: fixture.revenue)?.calculated.posted ?? -1,
                    100,
                    "only current revenue is cleared"
                )
                try Expect.equal(
                    compilation.amount(for: fixture.revenue)?.posted ?? 1,
                    -40,
                    "historical revenue not silently closed"
                )
                try Expect.equal(
                    compilation.amount(for: fixture.expenses)?.posted ?? -1,
                    0,
                    "expenses cleared by selected effect"
                )
                try Expect.equal(
                    compilation.amount(for: fixture.equity)?.posted ?? 1,
                    -75,
                    "current profit transferred exactly once"
                )
                try Expect.equal(
                    compilation.amount(for: fixture.bank)?.posted ?? -1,
                    115,
                    "source cash balance intact"
                )
                try Expect.equal(
                    compilation.amount(for: fixture.heading)?.total ?? -1,
                    0,
                    "signed result balances"
                )
                try Expect.equal(compilation.routing != nil, true, "identity routing explicit")
                try Expect.equal(composition.effects.count, 3, "no duplicated effects")
            }

            Step("carryforward routes only historical direct contributions") {
                let fixture = try V2CompilationFixture()
                let chart = try fixture.chart(behavior: .init(
                    carryforward: .mapped(
                        rules: [
                            .init(
                                source: .subtree(root: fixture.group.reference, excluding: []),
                                destination: .account(fixture.opening.reference)
                            ),
                            .init(
                                source: .account(fixture.cash.reference),
                                destination: .same_account
                            )
                        ],
                        otherwise: .identity
                    )
                ))
                let group = try fixture.entry(
                    id: 1, time: 50,
                    debit: fixture.group.reference,
                    credit: fixture.cash.reference, amount: 100, chart: chart
                )
                let child = try fixture.entry(
                    id: 2, time: 60,
                    debit: fixture.child.reference,
                    credit: fixture.cash.reference, amount: 50, chart: chart
                )
                let current = try fixture.entry(
                    id: 3, time: 150,
                    debit: fixture.child.reference,
                    credit: fixture.cash.reference, amount: 20, chart: chart
                )
                let period = try fixture.period(chart: chart, entries: [group, child, current])
                let composition = try Composition(.init(selection: .recorded(period)))
                let compilation = try Compilation(.init(
                    composition: composition,
                    opening: .carryforward
                ))

                try Expect.equal(
                    compilation.breakdown(for: fixture.group.reference)?.recorded_opening.total ?? -1,
                    150,
                    "parent and child history originally roll together"
                )
                try Expect.equal(
                    compilation.breakdown(for: fixture.group.reference)?.opening.total ?? -1,
                    0,
                    "historical contributions moved out of source branch"
                )
                try Expect.equal(
                    compilation.breakdown(for: fixture.group.reference)?.movements.total ?? -1,
                    20,
                    "current child movement remains in source branch"
                )
                try Expect.equal(
                    compilation.amount(for: fixture.group.reference)?.total ?? -1,
                    20,
                    "historical accounts not counted twice"
                )
                try Expect.equal(
                    compilation.amount(for: fixture.child.reference)?.posted ?? -1,
                    20,
                    "current child keeps its original account"
                )
                try Expect.equal(
                    compilation.amount(for: fixture.opening.reference)?.posted ?? -1,
                    150,
                    "historical parent and child merge into nonpostable destination"
                )
                try Expect.equal(
                    compilation.breakdown(for: fixture.opening.reference)?.routing_delta.posted ?? -1,
                    150,
                    "reclassification separately inspectable"
                )
                try Expect.equal(
                    compilation.amount(for: fixture.cash.reference)?.posted ?? 1,
                    -170,
                    "cash retains original credit contributions"
                )
                try Expect.equal(
                    compilation.amount(for: fixture.root.reference)?.total ?? -1,
                    0,
                    "complete reattributed position remains balanced"
                )
                try Expect.equal(
                    compilation.routing?.contributions(to: fixture.opening.reference)?.map(\.originalAccount) ?? [],
                    [fixture.group.reference, fixture.child.reference],
                    "original account identities retained"
                )
                try Expect.equal(
                    compilation.routing?.contributions(to: fixture.opening.reference)?.map(\.source.entryID.value) ?? [],
                    [1, 2],
                    "only pre-period sources are routed"
                )
                try Expect.equal(
                    composition.amount(for: fixture.group.reference)?.total ?? -1,
                    170,
                    "recorded composition remains unchanged"
                )
            }

            Step("unmapped historical activity rejects only selected carryforward") {
                let fixture = try V2CompilationFixture()
                let chart = try fixture.chart(behavior: .init(carryforward: .mapped(
                    rules: [
                        .init(
                            source: .subtree(root: fixture.group.reference, excluding: []),
                            destination: .account(fixture.opening.reference)
                        )
                    ],
                    otherwise: .reject
                )))
                let earlier = try fixture.entry(
                    id: 1, time: 50,
                    debit: fixture.group.reference,
                    credit: fixture.cash.reference, amount: 100, chart: chart
                )
                let period = try fixture.period(chart: chart, entries: [earlier])
                let composition = try Composition(.init(selection: .recorded(period)))
                let recorded = try Compilation(.init(
                    composition: composition,
                    opening: .recorded
                ))

                try Expect.equal(
                    recorded.amount(for: fixture.group.reference)?.posted ?? -1,
                    100,
                    "recorded projection does not require routing"
                )
                try Expect.throwsError("cash has no permitted carryforward destination") {
                    _ = try Compilation(.init(
                        composition: composition,
                        opening: .carryforward
                    ))
                }
                try Expect.equal(
                    period.opening.postings.count,
                    2,
                    "original history remains intact after rejected routing"
                )
            }

            Step("zero-net historical activity retains individual routed sources") {
                let fixture = try V2CompilationFixture()
                let chart = try fixture.chart(behavior: .init(carryforward: .mapped(
                    rules: [
                        .init(
                            source: .subtree(root: fixture.group.reference, excluding: []),
                            destination: .account(fixture.opening.reference)
                        )
                    ],
                    otherwise: .identity
                )))
                let original = try fixture.entry(
                    id: 1, time: 50,
                    debit: fixture.group.reference,
                    credit: fixture.cash.reference, amount: 100, chart: chart
                )
                let reversal = try fixture.entry(
                    id: 2, time: 60,
                    debit: fixture.cash.reference,
                    credit: fixture.group.reference, amount: 100, chart: chart
                )
                let period = try fixture.period(chart: chart, entries: [original, reversal])
                let composition = try Composition(.init(selection: .recorded(period)))
                let compilation = try Compilation(.init(
                    composition: composition,
                    opening: .carryforward
                ))

                try Expect.equal(
                    compilation.amount(for: fixture.opening.reference)?.posted ?? -1,
                    0,
                    "reversed contributions cancel mathematically"
                )
                try Expect.equal(
                    compilation.routing?.contributions(to: fixture.opening.reference)?.count ?? -1,
                    2,
                    "zero net does not erase contributing postings"
                )
                try Expect.equal(
                    compilation.routing?.contributions(to: fixture.opening.reference)?.map(\.signedAmount) ?? [],
                    [100, -100],
                    "positive and negative contributions preserved"
                )
                try Expect.equal(
                    compilation.amount(for: fixture.root.reference)?.total ?? -1,
                    0,
                    "net zero remains balanced"
                )
            }
        }
    }
}
