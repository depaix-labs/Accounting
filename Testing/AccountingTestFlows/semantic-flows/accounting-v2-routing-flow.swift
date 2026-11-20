import Foundation
import AccountingV2
import TestFlows

private struct V2RoutingFixture {
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
        opening = try Account(.init(code: "OPEN", category: .equity, postable: true))
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
        debit: Account.Reference,
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
            account: cash.reference,
            entity: owner,
            direction: .credit,
            amount: amount,
            chart: chart,
            entities: entities
        ))
        return try Entry(.init(
            id: Entry.ID(id),
            date: Date(timeIntervalSince1970: 150),
            lines: [debitLine, creditLine]
        ))
    }

    func balances(chart: Chart) throws -> Balances {
        let first = try entry(
            id: 1, debit: group.reference, amount: 100, chart: chart
        )
        let second = try entry(
            id: 2, debit: child.reference, amount: 50, chart: chart
        )
        let journal = try Journal(.init(
            entries: [first, second],
            chart: chart,
            entities: entities
        ))
        return Balances(.init(ledger: try Ledger(.init(journal: journal))))
    }
}

extension AccountingTestFlowsSuite {
    static var accountingV2RoutingFlow: TestFlow {
        TestFlow("accounting-v2-routing", tags: ["accounting", "v2", "routing"]) {
            Step("identity carryforward preserves original account attribution") {
                let fixture = try V2RoutingFixture()
                let chart = try fixture.chart(behavior: .init(carryforward: .identity))
                let balances = try fixture.balances(chart: chart)
                let routing = try Routing(.init(balances: balances))

                try Expect.equal(routing.contributions.count, 4, "all original postings")
                try Expect.equal(
                    routing.contributions.map(\.destination),
                    [fixture.group.reference, fixture.cash.reference,
                     fixture.child.reference, fixture.cash.reference],
                    "identity routes"
                )
                try Expect.equal(
                    routing.amount(for: fixture.group.reference)?.posted ?? -1,
                    100,
                    "direct group posting"
                )
                try Expect.equal(
                    routing.amount(for: fixture.group.reference)?.total ?? -1,
                    150,
                    "group rollup includes child"
                )
                try Expect.equal(
                    routing.amount(for: fixture.group.reference)?.descendants ?? -1,
                    50,
                    "distinct descendant activity"
                )
                try Expect.equal(
                    routing.contributions.map(\.source.entryID.value),
                    [1, 1, 2, 2],
                    "source identities unchanged"
                )
            }

            Step("sibling mapping merges direct parent and child postings once") {
                let fixture = try V2RoutingFixture()
                let behavior = Chart.Behavior(
                    carryforward: .mapped(
                        rules: [
                            .init(
                                source: .subtree(root: fixture.group.reference, excluding: []),
                                destination: .role(.equity_opening)
                            ),
                            .init(
                                source: .account(fixture.cash.reference),
                                destination: .same_account
                            )
                        ],
                        otherwise: .reject
                    ),
                    roles: [.equity_opening: fixture.opening.reference]
                )
                let chart = try fixture.chart(behavior: behavior)
                let balances = try fixture.balances(chart: chart)
                let routing = try Routing(.init(balances: balances))

                try Expect.equal(
                    chart.carryforwardDestination(for: fixture.child.reference),
                    fixture.opening.reference,
                    "compiled child route"
                )
                try Expect.equal(
                    routing.contributions.map(\.destination),
                    [fixture.opening.reference, fixture.cash.reference,
                     fixture.opening.reference, fixture.cash.reference],
                    "sibling destinations in source order"
                )
                try Expect.equal(
                    routing.amount(for: fixture.opening.reference)?.posted ?? -1,
                    150,
                    "only two direct original postings are merged"
                )
                try Expect.equal(
                    routing.amount(for: fixture.group.reference)?.total ?? -1,
                    0,
                    "old source branch receives no routed contributions"
                )
                try Expect.equal(
                    routing.contributions(to: fixture.opening.reference)?.count ?? -1,
                    2,
                    "both original sources inspectable"
                )
                try Expect.equal(
                    routing.contributions(to: fixture.opening.reference)?.map(\.originalAccount) ?? [],
                    [fixture.group.reference, fixture.child.reference],
                    "exact original identities retained"
                )
                try Expect.equal(
                    routing.amount(for: fixture.root.reference)?.total ?? -1,
                    0,
                    "balanced total after destination rollup"
                )
                try Expect.equal(
                    balances.amount(for: fixture.group.reference)?.total ?? -1,
                    150,
                    "unrouted balances remain unchanged"
                )
            }

            Step("subtree exclusions permit explicit same-account exceptions") {
                let fixture = try V2RoutingFixture()
                let chart = try fixture.chart(behavior: .init(
                    carryforward: .mapped(
                        rules: [
                            .init(
                                source: .subtree(
                                    root: fixture.group.reference,
                                    excluding: [fixture.child.reference]
                                ),
                                destination: .account(fixture.opening.reference)
                            ),
                            .init(
                                source: .account(fixture.child.reference),
                                destination: .same_account
                            ),
                            .init(
                                source: .account(fixture.cash.reference),
                                destination: .same_account
                            )
                        ],
                        otherwise: .reject
                    )
                ))
                let routing = try Routing(.init(balances: fixture.balances(chart: chart)))

                try Expect.equal(
                    routing.amount(for: fixture.opening.reference)?.posted ?? -1,
                    100,
                    "parent direct contribution routed"
                )
                try Expect.equal(
                    routing.amount(for: fixture.child.reference)?.posted ?? -1,
                    50,
                    "excluded descendant retains own identity"
                )
                try Expect.equal(
                    routing.amount(for: fixture.group.reference)?.total ?? -1,
                    50,
                    "descendant amount not double counted"
                )
            }

            Step("invalid routes reject during chart construction") {
                let fixture = try V2RoutingFixture()
                let unknown = try Account.Reference("UNKNOWN")

                try Expect.throwsError("unknown destination") {
                    _ = try fixture.chart(behavior: .init(carryforward: .mapped(
                        rules: [
                            .init(source: .account(fixture.group.reference),
                                  destination: .account(unknown))
                        ],
                        otherwise: .identity
                    )))
                }
                try Expect.throwsError("unbound semantic role") {
                    _ = try fixture.chart(behavior: .init(carryforward: .mapped(
                        rules: [
                            .init(source: .account(fixture.group.reference),
                                  destination: .role(.equity_opening))
                        ],
                        otherwise: .identity
                    )))
                }
                try Expect.throwsError("overlapping parent and child rules") {
                    _ = try fixture.chart(behavior: .init(carryforward: .mapped(
                        rules: [
                            .init(source: .subtree(root: fixture.group.reference, excluding: []),
                                  destination: .account(fixture.opening.reference)),
                            .init(source: .account(fixture.child.reference),
                                  destination: .same_account)
                        ],
                        otherwise: .identity
                    )))
                }
                try Expect.throwsError("invalid exclusion outside subtree") {
                    _ = try fixture.chart(behavior: .init(carryforward: .mapped(
                        rules: [
                            .init(source: .subtree(
                                root: fixture.group.reference,
                                excluding: [fixture.cash.reference]
                            ), destination: .account(fixture.opening.reference))
                        ],
                        otherwise: .identity
                    )))
                }
                try Expect.throwsError("empty named role") {
                    _ = try fixture.chart(behavior: .init(
                        carryforward: .identity,
                        roles: [.named(" "): fixture.opening.reference]
                    ))
                }
            }

            Step("reject fallback refuses unmatched activity without partial result") {
                let fixture = try V2RoutingFixture()
                let chart = try fixture.chart(behavior: .init(carryforward: .mapped(
                    rules: [
                        .init(source: .account(fixture.group.reference),
                              destination: .account(fixture.opening.reference)),
                        .init(source: .account(fixture.child.reference),
                              destination: .account(fixture.opening.reference))
                    ],
                    otherwise: .reject
                )))
                let balances = try fixture.balances(chart: chart)

                try Expect.throwsError("unmapped cash posting") {
                    _ = try Routing(.init(balances: balances))
                }
                try Expect.equal(
                    balances.postings.count,
                    4,
                    "rejected projection does not modify the original ledger"
                )
            }
        }
    }
}
