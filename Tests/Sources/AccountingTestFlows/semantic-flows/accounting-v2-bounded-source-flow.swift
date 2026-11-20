import Foundation
import AccountingV2
import AccountingV2Fixtures
import TestFlows

private func boundedDate(_ value: String) throws -> Date {
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withFullDate]
    guard let result = formatter.date(from: value) else {
        throw V2ClosingFixture.SampleError.invalidDate(value)
    }
    return result
}

private func boundedCalendar() -> Calendar {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "UTC") ?? .current
    return calendar
}

private func boundedCheckpoint(
    fixture: V2ClosingFixture,
    ledger: Ledger,
    boundary: Date,
    source: Provenance.Identifier,
    revision: Provenance.Identifier
) throws -> PositionState {
    let previous = try Period(.init(
        ledger: ledger,
        start: boundedDate("2025-01-01"),
        end: boundedDate("2026-01-01")
    ))
    let audit = try Closing().evaluate(.init(
        period: previous,
        equityAccount: fixture.equity
    ))
    let composition = try Composition(.init(selection: .accept_closing(audit)))
    let compilation = try Compilation(.init(
        composition: composition,
        opening: .recorded
    ))
    let historical = try PositionState(
        compilation: compilation,
        provenance: Provenance(
            result: try Provenance.Identifier("n19.2025.closed"),
            inputs: [.sourceRevision(source: source, revision: revision)]
        )
    )
    let prefix = try Period(.init(
        ledger: ledger,
        start: boundedDate("2026-01-01"),
        end: boundary
    ))
    let prefixComposition = try Composition(.init(selection: .recorded(prefix)))
    return try Continuity(.init(
        prior_state: historical,
        composition: prefixComposition,
        opening: .as_is,
        provenance: Provenance(
            result: try Provenance.Identifier("n19.prefix.\(boundary.timeIntervalSince1970)"),
            inputs: [
                .calculation(historical.provenance.result),
                .sourceRevision(source: source, revision: revision)
            ]
        )
    )).result
}

private func boundedLineages(
    selection: MovementSelection,
    checkpoint: PositionState,
    source: Provenance.Identifier,
    revision: Provenance.Identifier
) throws -> [Provenance] {
    let ids = try selection.windows.indices.map {
        try Provenance.Identifier("n19.window.\($0)")
    }
    return selection.windows.indices.map { index in
        Provenance(
            result: ids[index],
            inputs: [
                .calculation(index == 0 ? checkpoint.provenance.result : ids[index - 1]),
                .source(source),
                .sourceRevision(source: source, revision: revision)
            ]
        )
    }
}

extension AccountingTestFlowsSuite {
    static var accountingV2BoundedSourceFlow: TestFlow {
        TestFlow("accounting-v2-bounded-source", tags: ["accounting", "v2", "bounded"]) {
            Step("bounded two- and four-window projections match full history") {
                let fixture = try V2ClosingFixture()
                let fullLedger = try fixture.sampleLedger()
                let source = try Provenance.Identifier("n19.source")
                let revision = try Provenance.Identifier("n19.revision.1")

                for count in [2, 4] {
                    let selection = try MovementSelection(
                        anchor: boundedDate("2026-10-15"),
                        unit: .month,
                        count: count,
                        calendar: boundedCalendar()
                    )
                    let start = selection.windows[0].start
                    let end = selection.windows[selection.windows.count - 1].end
                    let checkpoint = try boundedCheckpoint(
                        fixture: fixture,
                        ledger: fullLedger,
                        boundary: start,
                        source: source,
                        revision: revision
                    )
                    let lineages = try boundedLineages(
                        selection: selection,
                        checkpoint: checkpoint,
                        source: source,
                        revision: revision
                    )

                    let full = try MovementPositions(.init(
                        checkpoint: checkpoint,
                        slices: MovementSlices(.init(
                            ledger: fullLedger,
                            selection: selection
                        )),
                        source: source,
                        lineages: lineages
                    ))

                    let entries = fullLedger.journal.entries.filter {
                        $0.date >= start && $0.date < end
                    }
                    let boundedJournal = try Journal(.init(
                        entries: entries,
                        chart: fixture.chart,
                        entities: fixture.entities
                    ))
                    let boundedLedger = try Ledger(.init(journal: boundedJournal))
                    let attested = try MovementSource(.init(
                        ledger: boundedLedger,
                        source: source,
                        revision: revision,
                        start: start,
                        end: end
                    ))
                    let bounded = try MovementPositions(.init(
                        checkpoint: checkpoint,
                        selection: selection,
                        source: attested,
                        lineages: lineages
                    ))

                    try Expect.equal(fullLedger.postings.count, 12, "full source retained")
                    try Expect.equal(boundedLedger.postings.count, 4, "only four bounded postings")
                    try Expect.equal(bounded.windows.count, count, "all windows retained")
                    try Expect.equal(bounded.coverage?.revision, revision, "coverage revision retained")
                    try Expect.equal(full.coverage == nil, true, "legacy full path has no attestation")
                    try Expect.equal(bounded.result.boundary, end, "final boundary")
                    try Expect.equal(
                        bounded.result.amount(for: fixture.bank)?.posted ?? -1,
                        235, "same terminal bank"
                    )

                    for index in selection.windows.indices {
                        let original = full.windows[index]
                        let reduced = bounded.windows[index]
                        try Expect.equal(
                            original.movements.postings.map { $0.source.entryID },
                            reduced.movements.postings.map { $0.source.entryID },
                            "entry IDs agree for window \(index)"
                        )
                        try Expect.equal(
                            original.movements.postings.map { $0.source.lineIndex },
                            reduced.movements.postings.map { $0.source.lineIndex },
                            "line indices agree for window \(index)"
                        )
                        try Expect.equal(
                            original.result.provenance,
                            reduced.result.provenance,
                            "source and calculation lineage agree"
                        )
                        for account in fixture.accountOrder {
                            for entity: Entity.Reference? in [nil, fixture.owner, fixture.secondOwner] {
                                let expected = original.breakdown(for: account, entity: entity)
                                let actual = reduced.breakdown(for: account, entity: entity)
                                try Expect.equal(expected?.opening.posted, actual?.opening.posted, "opening direct")
                                try Expect.equal(expected?.opening.total, actual?.opening.total, "opening hierarchy")
                                try Expect.equal(expected?.movements.posted, actual?.movements.posted, "movement direct")
                                try Expect.equal(expected?.movements.total, actual?.movements.total, "movement hierarchy")
                                try Expect.equal(expected?.result.posted, actual?.result.posted, "result direct")
                                try Expect.equal(expected?.result.total, actual?.result.total, "result hierarchy")
                            }
                        }
                    }
                }
            }

            Step("reject incomplete coverage and entries outside its declaration") {
                let fixture = try V2ClosingFixture()
                let fullLedger = try fixture.sampleLedger()
                let source = try Provenance.Identifier("n19.source")
                let revision = try Provenance.Identifier("n19.revision.1")
                let selection = try MovementSelection(
                    anchor: boundedDate("2026-10-15"),
                    unit: .month,
                    calendar: boundedCalendar()
                )
                let start = selection.windows[0].start
                let end = selection.windows[selection.windows.count - 1].end
                let checkpoint = try boundedCheckpoint(
                    fixture: fixture, ledger: fullLedger, boundary: start,
                    source: source, revision: revision
                )
                let lineages = try boundedLineages(
                    selection: selection, checkpoint: checkpoint,
                    source: source, revision: revision
                )

                try Expect.throwsError("unbounded entries cannot masquerade as bounded") {
                    _ = try MovementSource(.init(
                        ledger: fullLedger, source: source, revision: revision,
                        start: start, end: end
                    ))
                }

                let octoberStart = try boundedDate("2026-10-01")
                let octoberEntries = fullLedger.journal.entries.filter {
                    $0.date >= octoberStart && $0.date < end
                }
                let octoberJournal = try Journal(.init(
                    entries: octoberEntries,
                    chart: fixture.chart,
                    entities: fixture.entities
                ))
                let octoberLedger = try Ledger(.init(journal: octoberJournal))
                let octoberSource = try MovementSource(.init(
                    ledger: octoberLedger,
                    source: source, revision: revision,
                    start: octoberStart, end: end
                ))
                try Expect.throwsError("October-only coverage cannot answer September") {
                    _ = try MovementPositions(.init(
                        checkpoint: checkpoint,
                        selection: selection,
                        source: octoberSource,
                        lineages: lineages
                    ))
                }

                let completeEntries = fullLedger.journal.entries.filter {
                    $0.date >= start && $0.date < end
                }
                let completeJournal = try Journal(.init(
                    entries: completeEntries,
                    chart: fixture.chart,
                    entities: fixture.entities
                ))
                let completeLedger = try Ledger(.init(journal: completeJournal))
                let wrongRevision = try Provenance.Identifier("n19.revision.2")
                let revisedSource = try MovementSource(.init(
                    ledger: completeLedger, source: source,
                    revision: wrongRevision, start: start, end: end
                ))
                try Expect.throwsError("revision mismatch invalidates checkpoint use") {
                    _ = try MovementPositions(.init(
                        checkpoint: checkpoint, selection: selection,
                        source: revisedSource, lineages: lineages
                    ))
                }

                let correctSource = try MovementSource(.init(
                    ledger: completeLedger, source: source,
                    revision: revision, start: start, end: end
                ))
                let missingRevision = lineages.enumerated().map { index, lineage in
                    index == 0 ? Provenance(
                        result: lineage.result,
                        inputs: [
                            .calculation(checkpoint.provenance.result),
                            .source(source)
                        ]
                    ) : lineage
                }
                try Expect.throwsError("each result must retain source revision") {
                    _ = try MovementPositions(.init(
                        checkpoint: checkpoint, selection: selection,
                        source: correctSource, lineages: missingRevision
                    ))
                }
            }
        }
    }
}
