import Foundation
import AccountingV2
import AccountingV2Fixtures
import TestFlows

private func positionWindowDate(_ value: String) throws -> Date {
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withFullDate]
    guard let result = formatter.date(from: value) else {
        throw V2ClosingFixture.SampleError.invalidDate(value)
    }
    return result
}

private func positionWindowCalendar() -> Calendar {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "UTC") ?? .current
    return calendar
}

private func fixtureCheckpoint(
    fixture: V2ClosingFixture,
    ledger: Ledger,
    at boundary: Date
) throws -> PositionState {
    let first = try positionWindowDate("2025-01-01")
    let yearStart = try positionWindowDate("2026-01-01")
    let previous = try Period(.init(ledger: ledger, start: first, end: yearStart))
    let audit = try Closing().evaluate(.init(
        period: previous,
        equityAccount: fixture.equity
    ))
    let composition = try Composition(.init(selection: .accept_closing(audit)))
    let compilation = try Compilation(.init(composition: composition, opening: .recorded))
    let prior = try PositionState(
        compilation: compilation,
        provenance: Provenance(
            result: try Provenance.Identifier("fixture.2025.accepted"),
            inputs: []
        )
    )
    if boundary == yearStart {
        return prior
    }
    let prefix = try Period(.init(ledger: ledger, start: yearStart, end: boundary))
    let prefixComposition = try Composition(.init(selection: .recorded(prefix)))
    let checkpoint = try Continuity(.init(
        prior_state: prior,
        composition: prefixComposition,
        opening: .as_is,
        provenance: Provenance(
            result: try Provenance.Identifier("fixture.checkpoint"),
            inputs: [.calculation(prior.provenance.result)]
        )
    ))
    return checkpoint.result
}

private func fixtureLineages(
    for selection: MovementSelection,
    checkpoint: PositionState,
    source: Provenance.Identifier
) throws -> [Provenance] {
    let identifiers = try selection.windows.indices.map {
        try Provenance.Identifier("fixture.window.\($0)")
    }
    return selection.windows.indices.map { index in
        let prior = index == 0 ? checkpoint.provenance.result : identifiers[index - 1]
        return Provenance(
            result: identifiers[index],
            inputs: [.calculation(prior), .source(source)]
        )
    }
}

extension AccountingTestFlowsSuite {
    static var accountingV2MovementPositionsFlow: TestFlow {
        TestFlow("accounting-v2-movement-positions", tags: ["accounting", "v2", "positions"]) {
            Step("two windows advance accepted history without replay or closing") {
                let fixture = try V2ClosingFixture()
                let ledger = try fixture.sampleLedger()
                let selection = try MovementSelection(
                    anchor: positionWindowDate("2026-10-15"),
                    unit: .month,
                    calendar: positionWindowCalendar()
                )
                let slices = MovementSlices(.init(ledger: ledger, selection: selection))
                let checkpoint = try fixtureCheckpoint(
                    fixture: fixture, ledger: ledger, at: selection.windows[0].start
                )
                let source = try Provenance.Identifier("fixture.journal.1")
                let positions = try MovementPositions(.init(
                    checkpoint: checkpoint,
                    slices: slices,
                    source: source,
                    lineages: fixtureLineages(
                        for: selection, checkpoint: checkpoint, source: source
                    )
                ))
                let previous = positions.window(for: .previous)
                let current = positions.window(for: .current)

                try Expect.equal(checkpoint.amount(for: fixture.bank)?.posted ?? -1, 165, "opening bank")
                try Expect.equal(checkpoint.amount(for: fixture.equity)?.posted ?? 1, -40, "accepted 2025 closing")
                try Expect.equal(slices.recorded_before.postings.count, 6, "historical postings not replayed")
                try Expect.equal(previous?.opening.boundary, selection.previous?.start, "previous opening")
                try Expect.equal(previous?.result.boundary, selection.previous?.end, "previous closing")
                try Expect.equal(previous?.result.amount(for: fixture.bank)?.posted ?? -1, 245, "September bank")
                try Expect.equal(previous?.result.amount(for: fixture.revenue)?.posted ?? 1, -280, "unclosed 2026 revenue")
                try Expect.equal(current?.opening.amount(for: fixture.bank)?.posted ?? -1, 245, "October inherits September")
                try Expect.equal(current?.movements.amount(for: fixture.bank)?.posted ?? 1, -10, "October movements")
                try Expect.equal(current?.result.amount(for: fixture.bank)?.posted ?? -1, 235, "October bank")
                try Expect.equal(current?.result.amount(for: fixture.dividends)?.posted ?? -1, 10, "drawings retained")
                try Expect.equal(current?.result.amount(for: fixture.equity)?.posted ?? 1, -40, "no invented monthly closing")
                try Expect.equal(current?.result.amount(for: fixture.heading)?.total ?? -1, 0, "balanced result")
                try Expect.equal(current?.result.amount(for: fixture.bank, entity: fixture.secondOwner)?.posted ?? -1, 80, "entity retained")
                try Expect.equal(current?.movements.postings.map { $0.source.entryID.value } ?? [], [4, 4], "original October posting coordinates")
                try Expect.equal(positions.result.boundary, selection.current?.end, "terminal boundary")
                try Expect.equal(ledger.postings.count, 12, "journal unchanged")
            }

            Step("four windows preserve empty months and cumulative positions") {
                let fixture = try V2ClosingFixture()
                let ledger = try fixture.sampleLedger()
                let selection = try MovementSelection(
                    anchor: positionWindowDate("2026-10-15"),
                    unit: .month,
                    count: 4,
                    calendar: positionWindowCalendar()
                )
                let slices = MovementSlices(.init(ledger: ledger, selection: selection))
                let checkpoint = try fixtureCheckpoint(
                    fixture: fixture, ledger: ledger, at: selection.windows[0].start
                )
                let source = try Provenance.Identifier("fixture.journal.1")
                let positions = try MovementPositions(.init(
                    checkpoint: checkpoint,
                    slices: slices,
                    source: source,
                    lineages: fixtureLineages(
                        for: selection, checkpoint: checkpoint, source: source
                    )
                ))

                try Expect.equal(
                    positions.windows.map { $0.result.amount(for: fixture.bank)?.posted ?? -1 },
                    [165, 165, 245, 235],
                    "empty July and August, then September and October"
                )
                try Expect.equal(
                    positions.windows.map { $0.movements.postings.count },
                    [0, 0, 2, 2],
                    "empty windows are real positions"
                )
                try Expect.equal(
                    positions.windows.map { $0.result.boundary },
                    selection.windows.map(\.end),
                    "each snapshot ends at its own window"
                )
            }

            Step("rejects gaps, incorrect boundaries, incompatible entities, and false lineage") {
                let fixture = try V2ClosingFixture()
                let ledger = try fixture.sampleLedger()
                let selection = try MovementSelection(
                    anchor: positionWindowDate("2026-10-15"),
                    unit: .month,
                    calendar: positionWindowCalendar()
                )
                let slices = MovementSlices(.init(ledger: ledger, selection: selection))
                let source = try Provenance.Identifier("fixture.journal.1")
                let checkpoint = try fixtureCheckpoint(
                    fixture: fixture, ledger: ledger, at: selection.windows[0].start
                )
                let lineages = try fixtureLineages(
                    for: selection, checkpoint: checkpoint, source: source
                )

                try Expect.throwsError("missing source provenance") {
                    let invalid = lineages.enumerated().map { index, value in
                        index == 0 ? Provenance(
                            result: value.result,
                            inputs: [.calculation(checkpoint.provenance.result)]
                        ) : value
                    }
                    _ = try MovementPositions(.init(
                        checkpoint: checkpoint, slices: slices,
                        source: source, lineages: invalid
                    ))
                }
                try Expect.throwsError("window must link to immediate preceding result") {
                    let invalid = [
                        lineages[0],
                        Provenance(
                            result: lineages[1].result,
                            inputs: [
                                .calculation(checkpoint.provenance.result),
                                .source(source)
                            ]
                        )
                    ]
                    _ = try MovementPositions(.init(
                        checkpoint: checkpoint, slices: slices,
                        source: source, lineages: invalid
                    ))
                }
                try Expect.throwsError("result identities cannot repeat") {
                    let invalid = [
                        lineages[0],
                        Provenance(
                            result: lineages[0].result,
                            inputs: [
                                .calculation(lineages[0].result),
                                .source(source)
                            ]
                        )
                    ]
                    _ = try MovementPositions(.init(
                        checkpoint: checkpoint, slices: slices,
                        source: source, lineages: invalid
                    ))
                }
                try Expect.throwsError("lineage count must match selected windows") {
                    _ = try MovementPositions(.init(
                        checkpoint: checkpoint, slices: slices,
                        source: source, lineages: [lineages[0]]
                    ))
                }
                try Expect.throwsError("wrong checkpoint boundary") {
                    let wrong = try PositionState(.init(
                        chart: fixture.chart, entities: fixture.entities,
                        boundary: positionWindowDate("2026-08-01"),
                        cells: checkpoint.cells,
                        provenance: checkpoint.provenance
                    ))
                    _ = try MovementPositions(.init(
                        checkpoint: wrong, slices: slices,
                        source: source, lineages: lineages
                    ))
                }
                try Expect.throwsError("entity registry must match") {
                    let subset = try Entities([Entity(.init(reference: fixture.owner))])
                    let incompatible = try PositionState(.init(
                        chart: fixture.chart, entities: subset,
                        boundary: checkpoint.boundary,
                        cells: [], provenance: checkpoint.provenance
                    ))
                    _ = try MovementPositions(.init(
                        checkpoint: incompatible, slices: slices,
                        source: source, lineages: lineages
                    ))
                }

                let gaps = try MovementSelection(.init(source: .explicit([
                    .init(role: .previous,
                          start: positionWindowDate("2026-09-01"),
                          end: positionWindowDate("2026-10-01")),
                    .init(role: .current,
                          start: positionWindowDate("2026-11-01"),
                          end: positionWindowDate("2026-12-01"))
                ])))
                let gapSlices = MovementSlices(.init(ledger: ledger, selection: gaps))
                try Expect.throwsError("gap cannot silently omit intervening movements") {
                    _ = try MovementPositions(.init(
                        checkpoint: checkpoint, slices: gapSlices,
                        source: source, lineages: lineages
                    ))
                }
            }
        }
    }
}
