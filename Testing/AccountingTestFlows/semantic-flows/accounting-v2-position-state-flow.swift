import Foundation
import AccountingV2
import AccountingV2Fixtures
import TestFlows

private func v2StateProvenance(_ name: String) throws -> Provenance {
    Provenance(
        result: try Provenance.Identifier(name),
        inputs: []
    )
}

extension AccountingTestFlowsSuite {
    static var accountingV2PositionStateFlow: TestFlow {
        TestFlow("accounting-v2-position-state", tags: ["accounting", "v2", "state"]) {
            Step("materializes selected closing without retaining cumulative ledger") {
                let fixture = try V2ClosingFixture()
                let sale = try fixture.entry(
                    id: 1, debit: fixture.bank,
                    credit: fixture.revenue, amount: 200
                )
                let cost = try fixture.entry(
                    id: 2, debit: fixture.expenses,
                    credit: fixture.bank, amount: 75
                )
                let period = try fixture.period([sale, cost])
                let audit = try Closing().evaluate(.init(
                    period: period, equityAccount: fixture.equity
                ))
                let composition = try Composition(.init(
                    selection: .accept_closing(audit)
                ))
                let compilation = try Compilation(.init(
                    composition: composition, opening: .recorded
                ))
                let provenance = try v2StateProvenance("closing-2025")
                let state = try PositionState(
                    compilation: compilation,
                    provenance: provenance
                )

                try Expect.equal(state.boundary, period.end, "closing boundary")
                try Expect.equal(state.provenance.result, provenance.result, "declared lineage")
                try Expect.equal(
                    state.amount(for: fixture.bank)?.posted ?? -1,
                    125,
                    "bank position"
                )
                try Expect.equal(
                    state.amount(for: fixture.revenue)?.posted ?? -1,
                    0,
                    "accepted revenue clearing"
                )
                try Expect.equal(
                    state.amount(for: fixture.expenses)?.posted ?? -1,
                    0,
                    "accepted expense clearing"
                )
                try Expect.equal(
                    state.amount(for: fixture.equity)?.posted ?? 1,
                    -125,
                    "equity receives signed result"
                )
                try Expect.equal(
                    state.amount(for: fixture.heading)?.total ?? -1,
                    0,
                    "balanced account hierarchy"
                )
                try Expect.equal(
                    state.amount(for: fixture.bank)?.total ?? -1,
                    compilation.amount(for: fixture.bank)?.total ?? -2,
                    "state agrees with compiled result"
                )
                try Expect.equal(
                    state.cells.contains { $0.account == fixture.revenue && $0.amount == 0 },
                    true,
                    "zero-net contribution remains identifiable as a cell"
                )
            }

            Step("preserves unclosed historical contributions in the selected result") {
                let fixture = try V2ClosingFixture()
                let earlier = try fixture.entry(
                    id: 1, time: 50, debit: fixture.bank,
                    credit: fixture.revenue, amount: 40
                )
                let current = try fixture.entry(
                    id: 2, debit: fixture.bank,
                    credit: fixture.revenue, amount: 100
                )
                let period = try fixture.period([earlier, current])
                let audit = try Closing().evaluate(.init(
                    period: period, equityAccount: fixture.equity
                ))
                let composition = try Composition(.init(
                    selection: .accept_closing(audit)
                ))
                let compilation = try Compilation(.init(
                    composition: composition, opening: .recorded
                ))
                let state = try PositionState(
                    compilation: compilation,
                    provenance: v2StateProvenance("historical-unclosed")
                )

                try Expect.equal(
                    state.amount(for: fixture.revenue)?.posted ?? 1,
                    -40,
                    "prior temporary activity not silently closed"
                )
                try Expect.equal(
                    state.amount(for: fixture.bank)?.posted ?? -1,
                    140,
                    "recorded positions preserved"
                )
                try Expect.equal(
                    state.amount(for: fixture.equity)?.posted ?? 1,
                    -100,
                    "only current movements transferred"
                )
            }

            Step("carryforward merges parent and child direct balances once") {
                let root = try Account(.init(code: "ROOT", postable: false))
                let group = try Account(.init(code: "GROUP", category: .assets, postable: true))
                let child = try Account(.init(code: "CHILD", category: .assets, postable: true))
                let cash = try Account(.init(code: "CASH", category: .assets, postable: true))
                let opening = try Account(.init(code: "OPEN", category: .assets, postable: false))
                let owner = try Entity.Reference(
                    class: "person", family: "owner", alias: Entity.Alias(name: "owner")
                )
                let entities = try Entities([Entity(.init(reference: owner))])
                let chart = try Chart(.init(
                    accounts: [root, group, child, cash, opening],
                    roots: [root.reference],
                    parents: [
                        group.reference: root.reference,
                        child.reference: group.reference,
                        cash.reference: root.reference,
                        opening.reference: root.reference
                    ],
                    behavior: .init(
                        carryforward: .mapped(
                            rules: [
                                .init(
                                    source: .subtree(root: group.reference, excluding: []),
                                    destination: .role(.equity_opening)
                                )
                            ],
                            otherwise: .identity
                        ),
                        roles: [.equity_opening: opening.reference]
                    )
                ))
                let original = try PositionState(.init(
                    chart: chart,
                    entities: entities,
                    boundary: Date(timeIntervalSince1970: 200),
                    cells: [
                        .init(account: group.reference, entity: owner, amount: 100),
                        .init(account: child.reference, entity: owner, amount: 50),
                        .init(account: cash.reference, entity: owner, amount: -150)
                    ],
                    provenance: v2StateProvenance("before-carryforward")
                ))
                let carried = try original.carryforward(
                    provenance: v2StateProvenance("after-carryforward")
                )

                try Expect.equal(
                    original.amount(for: group.reference)?.total ?? -1,
                    150,
                    "original hierarchy intact"
                )
                try Expect.equal(
                    carried.amount(for: group.reference)?.total ?? -1,
                    0,
                    "historical source branch cleared by reattribution"
                )
                try Expect.equal(
                    carried.amount(for: opening.reference)?.posted ?? -1,
                    150,
                    "parent and child merge at nonpostable opening destination"
                )
                try Expect.equal(
                    carried.amount(for: cash.reference)?.posted ?? 1,
                    -150,
                    "unmapped cash remains at same account"
                )
                try Expect.equal(
                    carried.amount(for: root.reference)?.total ?? -1,
                    0,
                    "result remains balanced"
                )
                try Expect.equal(carried.cells.count, 2, "compressed many-to-one position")
                try Expect.equal(carried.boundary, original.boundary, "boundary unchanged")
                try Expect.equal(
                    original.cells.count,
                    3,
                    "source state not mutated"
                )
            }

            Step("rejects duplicate, unknown, unbalanced and unmapped states") {
                let fixture = try V2ClosingFixture()
                let unknown = try Account.Reference("UNKNOWN")
                let provenance = try v2StateProvenance("invalid-state-test")
                let date = Date(timeIntervalSince1970: 200)

                try Expect.throwsError("duplicate cell") {
                    _ = try PositionState(.init(
                        chart: fixture.chart,
                        entities: fixture.entities,
                        boundary: date,
                        cells: [
                            .init(account: fixture.bank, entity: fixture.owner, amount: 100),
                            .init(account: fixture.bank, entity: fixture.owner, amount: -100)
                        ],
                        provenance: provenance
                    ))
                }
                try Expect.throwsError("unknown account") {
                    _ = try PositionState(.init(
                        chart: fixture.chart,
                        entities: fixture.entities,
                        boundary: date,
                        cells: [.init(account: unknown, entity: fixture.owner, amount: 0)],
                        provenance: provenance
                    ))
                }
                try Expect.throwsError("unbalanced state") {
                    _ = try PositionState(.init(
                        chart: fixture.chart,
                        entities: fixture.entities,
                        boundary: date,
                        cells: [.init(account: fixture.bank, entity: fixture.owner, amount: 100)],
                        provenance: provenance
                    ))
                }

                let empty = try PositionState(.init(
                    chart: fixture.chart,
                    entities: fixture.entities,
                    boundary: date,
                    cells: [],
                    provenance: provenance
                ))
                try Expect.equal(
                    empty.amount(for: fixture.bank)?.posted ?? -1,
                    0,
                    "known inactive account is zero"
                )
                try Expect.equal(
                    empty.amount(for: unknown) == nil,
                    true,
                    "unknown account is not zero"
                )
            }
        }
    }
}
