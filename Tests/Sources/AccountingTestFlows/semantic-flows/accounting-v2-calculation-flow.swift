import AccountingV2
import TestFlows

private struct IncrementCalculation: Calculation {
    func evaluate(_ input: Int) throws -> Int {
        input + 1
    }
}

private struct RecordedCalculationResult: ProvenanceProviding {
    let value: Int
    let provenance: Provenance
}

extension AccountingTestFlowsSuite {
    static var accountingV2CalculationFlow: TestFlow {
        TestFlow("accounting-v2-calculation", tags: ["accounting", "v2", "calculation"]) {
            Step("evaluates strongly typed calculations") {
                let calculation = IncrementCalculation()
                let result = try calculation.evaluate(41)
                try Expect.equal(result, 42, "typed calculation output")
            }

            Step("rejects empty provenance identifiers") {
                try Expect.throwsError("empty identifier") {
                    _ = try Provenance.Identifier("")
                }
                try Expect.throwsError("whitespace identifier") {
                    _ = try Provenance.Identifier("  ")
                }
            }

            Step("retains source and derived dependencies independently") {
                let result = try Provenance.Identifier("closing-2026")
                let source = try Provenance.Identifier("journal-snapshot")
                let previous = try Provenance.Identifier("period-facts-2026")
                let policyID = try Provenance.Identifier("closing-policy")
                let revision = try Provenance.Identifier("revision-1")

                let provenance = Provenance(
                    result: result,
                    inputs: [
                        .source(source),
                        .calculation(previous)
                    ],
                    policy: .init(identifier: policyID, revision: revision)
                )

                try Expect.equal(provenance.result, result, "result identity")
                try Expect.equal(provenance.inputs.count, 2, "dependency count")
                try Expect.equal(provenance.inputs[0], .source(source), "authoritative source")
                try Expect.equal(provenance.inputs[1], .calculation(previous), "derived dependency")
                try Expect.equal(provenance.policy?.identifier, policyID, "policy identity")
                try Expect.equal(provenance.policy?.revision, revision, "policy revision")

                let retained = RecordedCalculationResult(value: 42, provenance: provenance)
                try Expect.equal(retained.provenance, provenance, "retained lineage")
            }

            Step("preserves policy-free result lineage") {
                let result = try Provenance.Identifier("ledger-snapshot")
                let source = try Provenance.Identifier("journal-source")
                let provenance = Provenance(
                    result: result,
                    inputs: [.source(source)]
                )

                try Expect.equal(provenance.policy == nil, true, "no artificial policy")
                try Expect.equal(provenance.inputs, [.source(source)], "source identity preserved")
            }
        }
    }
}
