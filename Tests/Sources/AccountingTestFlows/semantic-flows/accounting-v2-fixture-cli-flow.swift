import Foundation
import AccountingV2
import AccountingV2Fixtures
import TestFlows

extension AccountingTestFlowsSuite {
    static var accountingV2FixtureCLIFlow: TestFlow {
        TestFlow("accounting-v2-fixture-cli", tags: ["accounting", "v2", "fixture", "cli"]) {
            Step("shared CLI fixture compiles the selected year and excludes future sources") {
                let fixture = try V2ClosingFixture()
                let ledger = try fixture.sampleLedger()
                let formatter = ISO8601DateFormatter()
                formatter.formatOptions = [.withFullDate]
                guard let start = formatter.date(from: "2026-01-01"),
                      let end = formatter.date(from: "2027-01-01")
                else {
                    throw V2ClosingFixture.SampleError.invalidDate("fixture-range")
                }

                let period = try Period(.init(
                    ledger: ledger,
                    start: start,
                    end: end
                ))
                try Expect.equal(ledger.postings.count, 12, "all fixture postings")
                try Expect.equal(period.opening.postings.count, 2, "one historical entry")
                try Expect.equal(period.movements.postings.count, 8, "four current entries")
                try Expect.equal(period.position.postings.count, 10, "future entry excluded")

                let audit = try Closing().evaluate(.init(
                    period: period,
                    equityAccount: fixture.equity
                ))
                try Expect.equal(audit.effects.count, 6, "two entity closing groups")
                try Expect.equal(audit.effectBalance, 0, "balanced selected calculations")

                let composition = try Composition(.init(
                    selection: .accept_closing(audit)
                ))
                let compilation = try Compilation(.init(
                    composition: composition,
                    opening: .carryforward
                ))
                let state = try PositionState(
                    compilation: compilation,
                    provenance: Provenance(
                        result: try Provenance.Identifier("fixture-cli-smoke"),
                        inputs: []
                    )
                )

                try Expect.equal(
                    state.amount(for: fixture.bank)?.posted ?? -1,
                    235,
                    "bank reflects historical and current entries"
                )
                try Expect.equal(
                    state.amount(for: fixture.revenue)?.posted ?? 1,
                    -40,
                    "historical revenue remains visible"
                )
                try Expect.equal(
                    state.amount(for: fixture.equity)?.posted ?? 1,
                    -195,
                    "selected closing effects transferred once"
                )
                try Expect.equal(
                    state.amount(for: fixture.heading)?.total ?? -1,
                    0,
                    "compiled root remains balanced"
                )
                try Expect.equal(
                    state.amount(for: fixture.equity, entity: fixture.secondOwner)?.posted ?? 1,
                    -80,
                    "second owner preserved"
                )
            }
        }
    }
}
