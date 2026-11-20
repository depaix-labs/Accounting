import Foundation
import AccountingV2
import AccountingV2Fixtures
import TestFlows

private func continuityDate(_ value: String) throws -> Date {
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withFullDate]
    guard let result = formatter.date(from: value) else {
        throw V2ClosingFixture.SampleError.invalidDate(value)
    }
    return result
}

private func continuityProvenance(
    _ id: String,
    from prior: Provenance.Identifier? = nil
) throws -> Provenance {
    Provenance(
        result: try Provenance.Identifier(id),
        inputs: prior.map { [.calculation($0)] } ?? []
    )
}

extension AccountingTestFlowsSuite {
    static var accountingV2ContinuityFlow: TestFlow {
        TestFlow("accounting-v2-continuity", tags: ["accounting", "v2", "continuity"]) {
            Step("accepted 2025 closing is carried once into 2026") {
                let fixture = try V2ClosingFixture()
                let ledger = try fixture.sampleLedger()
                let previousPeriod = try Period(.init(
                    ledger: ledger,
                    start: continuityDate("2025-01-01"),
                    end: continuityDate("2026-01-01")
                ))
                let previousAudit = try Closing().evaluate(.init(
                    period: previousPeriod, equityAccount: fixture.equity
                ))
                let previousComposition = try Composition(.init(
                    selection: .accept_closing(previousAudit)
                ))
                let previousCompilation = try Compilation(.init(
                    composition: previousComposition, opening: .recorded
                ))
                let prior = try PositionState(
                    compilation: previousCompilation,
                    provenance: continuityProvenance("2025-accepted")
                )

                try Expect.equal(prior.amount(for: fixture.bank)?.posted ?? -1, 40, "previous bank")
                try Expect.equal(prior.amount(for: fixture.revenue)?.posted ?? -1, 0, "2025 revenue cleared")
                try Expect.equal(prior.amount(for: fixture.equity)?.posted ?? 1, -40, "2025 equity")

                let currentPeriod = try Period(.init(
                    ledger: ledger,
                    start: continuityDate("2026-01-01"),
                    end: continuityDate("2027-01-01")
                ))
                let currentAudit = try Closing().evaluate(.init(
                    period: currentPeriod, equityAccount: fixture.equity
                ))
                let currentComposition = try Composition(.init(
                    selection: .accept_closing(currentAudit)
                ))
                let continuity = try Continuity(.init(
                    prior_state: prior,
                    composition: currentComposition,
                    opening: .as_is,
                    provenance: continuityProvenance(
                        "2026-accepted", from: prior.provenance.result
                    )
                ))

                try Expect.equal(
                    continuity.amount(for: fixture.bank)?.posted ?? -1,
                    235, "prior bank plus only 2026 movements"
                )
                try Expect.equal(
                    continuity.amount(for: fixture.revenue)?.posted ?? -1,
                    0, "both years closed, not only 2026"
                )
                try Expect.equal(
                    continuity.amount(for: fixture.equity)?.posted ?? 1,
                    -235, "2025 equity -40 plus 2026 transfer -195"
                )
                try Expect.equal(
                    continuity.amount(for: fixture.heading)?.total ?? -1,
                    0, "result balances"
                )
                try Expect.equal(
                    continuity.breakdown(for: fixture.equity)?.prior.posted ?? 1,
                    -40, "prior accepted contribution remains inspectable"
                )
                try Expect.equal(
                    continuity.breakdown(for: fixture.equity)?.calculated.posted ?? 1,
                    -195, "current-year effect remains separate"
                )
                try Expect.equal(
                    continuity.result.boundary, currentPeriod.end,
                    "new state ends exactly at next boundary"
                )
                try Expect.equal(
                    continuity.result.provenance.inputs,
                    [.calculation(prior.provenance.result)],
                    "next state retains explicit prior identity"
                )
                try Expect.equal(
                    ledger.postings.count, 12, "source ledger unchanged"
                )
                try Expect.equal(
                    currentPeriod.opening.postings.count, 2,
                    "historical source postings still exist but are not replayed"
                )
            }

            Step("rejects noncontiguous historical boundaries") {
                let fixture = try V2ClosingFixture()
                let ledger = try fixture.sampleLedger()
                let prior = try PositionState(.init(
                    chart: fixture.chart,
                    entities: fixture.entities,
                    boundary: continuityDate("2026-01-01"),
                    cells: [],
                    provenance: continuityProvenance("prior-gap")
                ))
                let period = try Period(.init(
                    ledger: ledger,
                    start: continuityDate("2026-02-01"),
                    end: continuityDate("2027-01-01")
                ))
                let composition = try Composition(.init(selection: .recorded(period)))
                try Expect.throwsError("gap or overlap rejected") {
                    _ = try Continuity(.init(
                        prior_state: prior,
                        composition: composition,
                        opening: .as_is,
                        provenance: continuityProvenance(
                            "result-gap", from: prior.provenance.result
                        )
                    ))
                }
            }

            Step("requires explicit historical lineage") {
                let fixture = try V2ClosingFixture()
                let ledger = try fixture.sampleLedger()
                let prior = try PositionState(.init(
                    chart: fixture.chart,
                    entities: fixture.entities,
                    boundary: continuityDate("2026-01-01"),
                    cells: [],
                    provenance: continuityProvenance("lineage-prior")
                ))
                let period = try Period(.init(
                    ledger: ledger,
                    start: continuityDate("2026-01-01"),
                    end: continuityDate("2027-01-01")
                ))
                let composition = try Composition(.init(selection: .recorded(period)))
                try Expect.throwsError("missing prior state link") {
                    _ = try Continuity(.init(
                        prior_state: prior,
                        composition: composition,
                        opening: .as_is,
                        provenance: continuityProvenance("lineage-result")
                    ))
                }
            }

            Step("explicit carryforward retains its own provenance node") {
                let fixture = try V2ClosingFixture()
                let ledger = try fixture.sampleLedger()
                let prior = try PositionState(.init(
                    chart: fixture.chart,
                    entities: fixture.entities,
                    boundary: continuityDate("2026-01-01"),
                    cells: [],
                    provenance: continuityProvenance("carry-prior")
                ))
                let period = try Period(.init(
                    ledger: ledger,
                    start: continuityDate("2026-01-01"),
                    end: continuityDate("2027-01-01")
                ))
                let composition = try Composition(.init(selection: .recorded(period)))
                let carried = try continuityProvenance(
                    "carry-opening", from: prior.provenance.result
                )
                let continuity = try Continuity(.init(
                    prior_state: prior,
                    composition: composition,
                    opening: .carryforward(provenance: carried),
                    provenance: continuityProvenance(
                        "carry-result", from: carried.result
                    )
                ))

                try Expect.equal(
                    continuity.opening_state.provenance.result,
                    carried.result, "distinct carryforward lineage"
                )
                try Expect.equal(
                    continuity.result.provenance.inputs,
                    [.calculation(carried.result)],
                    "final state references carried opening"
                )
                try Expect.equal(
                    continuity.amount(for: fixture.bank)?.posted ?? -1,
                    195, "current-only bank activity; no previous replay"
                )
                try Expect.equal(
                    continuity.amount(for: fixture.heading)?.total ?? -1,
                    0, "recorded-only movements balance"
                )
            }

            Step("incompatible entity registries cannot silently continue") {
                let fixture = try V2ClosingFixture()
                let ledger = try fixture.sampleLedger()
                let subset = try Entities([
                    Entity(.init(reference: fixture.owner))
                ])
                let prior = try PositionState(.init(
                    chart: fixture.chart,
                    entities: subset,
                    boundary: continuityDate("2026-01-01"),
                    cells: [],
                    provenance: continuityProvenance("subset-prior")
                ))
                let period = try Period(.init(
                    ledger: ledger,
                    start: continuityDate("2026-01-01"),
                    end: continuityDate("2027-01-01")
                ))
                let composition = try Composition(.init(selection: .recorded(period)))
                try Expect.throwsError("registry mismatch") {
                    _ = try Continuity(.init(
                        prior_state: prior,
                        composition: composition,
                        opening: .as_is,
                        provenance: continuityProvenance(
                            "subset-result", from: prior.provenance.result
                        )
                    ))
                }
            }
        }
    }
}
