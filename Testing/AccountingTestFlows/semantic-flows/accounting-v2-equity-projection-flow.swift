import AccountingV2
import AccountingV2Fixtures
import Foundation
import TestFlows

private func projectionDate(_ value: String) throws -> Date {
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withFullDate]
    guard let date = formatter.date(from: value) else {
        throw V2ClosingFixture.SampleError.invalidDate(value)
    }
    return date
}

private func projectionOwnership(
    _ fixture: V2ClosingFixture,
    expires: Bool = false
) throws -> Ownership.Structure {
    let inception = try projectionDate("2025-01-01")
    let transition = try projectionDate("2026-07-01")
    let expiration = try projectionDate("2026-10-01")
    let first = try Ownership.History(
        owner: fixture.owner,
        initial: Ownership.State(
            effectiveFrom: inception, share: Ownership.Share(percent: 100)
        ),
        changes: [
            Ownership.Change(state: Ownership.State(
                effectiveFrom: transition, share: Ownership.Share(percent: 60)
            ))
        ] + (expires ? [Ownership.Change(state: Ownership.State(
            effectiveFrom: expiration, share: Ownership.Share(percent: 100)
        ))] : [])
    )
    let second = try Ownership.History(
        owner: fixture.secondOwner,
        initial: Ownership.State(
            effectiveFrom: inception, share: Ownership.Share(percent: 0)
        ),
        changes: [
            Ownership.Change(
                state: Ownership.State(
                    effectiveFrom: transition, share: Ownership.Share(percent: 40)
                ),
                divisions: [Ownership.Division(
                    recipient: fixture.owner, share: Ownership.Share(percent: 100)
                )]
            )
        ] + (expires ? [Ownership.Change(state: Ownership.State(
            effectiveFrom: expiration, share: Ownership.Share(percent: 0)
        ))] : [])
    )
    return try Ownership.Structure(
        portfolio: Ownership.Portfolio(
            entities: fixture.entities, histories: [first, second]
        ),
        collapsing: [fixture.secondOwner]
    )
}

private func projectionRollforward(
    _ fixture: V2ClosingFixture,
    contributes: Bool = false,
    expires: Bool = false,
    attribution: Ownership.Allocation.Attribution = .effective,
    snapshot: Bool = false
) throws -> Equity.Rollforward.Result {
    let original = try fixture.sampleLedger()
    var entries = original.journal.entries
    if contributes {
        entries.append(try fixture.entry(
            id: 7,
            time: projectionDate("2026-08-01").timeIntervalSince1970,
            entity: fixture.secondOwner,
            debit: fixture.bank,
            credit: fixture.equity,
            amount: 50
        ))
    }
    let ledger = try Ledger(.init(journal: Journal(.init(
        entries: entries,
        chart: fixture.chart,
        entities: fixture.entities
    ))))
    let prior = try Period(.init(
        ledger: ledger,
        start: projectionDate("2025-01-01"),
        end: projectionDate("2026-01-01")
    ))
    let closing = try Closing().evaluate(.init(
        period: prior, equityAccount: fixture.equity
    ))
    let composition = try Composition(.init(selection: .accept_closing(closing)))
    let compilation = try Compilation(.init(
        composition: composition, opening: .recorded
    ))
    let state = try PositionState(
        compilation: compilation,
        provenance: Provenance(
            result: Provenance.Identifier("synthetic.projection.opening"),
            inputs: []
        )
    )
    let period = try Period(.init(
        ledger: ledger,
        start: projectionDate("2026-01-01"),
        end: projectionDate("2027-01-01")
    ))
    let allocation = try Ownership.Allocation().evaluate(.init(
        period: period,
        ownership: projectionOwnership(fixture, expires: expires),
        policy: .init(
            basis: snapshot ? .snapshot(try projectionDate("2026-12-01")) : .timeline,
            attribution: attribution
        )
    ))
    return try Equity.Rollforward().evaluate(.init(
        anchor: Equity.Anchor(position: state, account: fixture.equity),
        allocation: allocation,
        contributions: [fixture.equity],
        drawings: [fixture.dividends]
    ))
}

private func projectionPostedRollforward(
    _ fixture: V2ClosingFixture
) throws -> Equity.Rollforward.Result {
    let profitShare = try Account(.init(
        code: "PROFIT.POSTED", category: .equity, postable: true
    ))
    let accounts = fixture.accountOrder.compactMap { fixture.chart.account($0) }
    let chart = try Chart(.init(
        accounts: accounts + [profitShare],
        roots: [fixture.heading],
        parents: Dictionary(uniqueKeysWithValues: (
            accounts.dropFirst().map(\.reference) + [profitShare.reference]
        ).map { ($0, fixture.heading) }),
        behavior: .init(carryforward: .identity)
    ))
    let recorded = try Entry(.init(
        id: Entry.ID(7),
        date: projectionDate("2026-08-01"),
        lines: [
            Entry.Line(.init(
                account: fixture.equity,
                entity: fixture.secondOwner,
                direction: .debit,
                amount: 205,
                chart: chart,
                entities: fixture.entities
            )),
            Entry.Line(.init(
                account: profitShare.reference,
                entity: fixture.secondOwner,
                direction: .credit,
                amount: 205,
                chart: chart,
                entities: fixture.entities
            ))
        ]
    ))
    let ledger = try Ledger(.init(journal: Journal(.init(
        entries: fixture.sampleLedger().journal.entries + [recorded],
        chart: chart,
        entities: fixture.entities
    ))))
    let prior = try Period(.init(
        ledger: ledger,
        start: projectionDate("2025-01-01"),
        end: projectionDate("2026-01-01")
    ))
    let closing = try Closing().evaluate(.init(
        period: prior, equityAccount: fixture.equity
    ))
    let compilation = try Compilation(.init(
        composition: Composition(.init(selection: .accept_closing(closing))),
        opening: .recorded
    ))
    let state = try PositionState(
        compilation: compilation,
        provenance: Provenance(
            result: Provenance.Identifier("synthetic.projection.posted"),
            inputs: []
        )
    )
    let period = try Period(.init(
        ledger: ledger,
        start: projectionDate("2026-01-01"),
        end: projectionDate("2027-01-01")
    ))
    let allocation = try Ownership.Allocation().evaluate(.init(
        period: period,
        ownership: projectionOwnership(fixture),
        policy: .init(
            basis: .timeline,
            posted: .prefer(account: profitShare.reference, mismatch: .reject)
        )
    ))
    return try Equity.Rollforward().evaluate(.init(
        anchor: Equity.Anchor(position: state, account: fixture.equity),
        allocation: allocation,
        drawings: [fixture.dividends]
    ))
}

private func projectionAdvancementFixture(
    _ fixture: V2ClosingFixture,
    withMovements: Bool = false
) throws -> Equity.Advancement.Result {
    let firstPeriod = try Equity.Projection().evaluate(.init(
        rollforward: projectionRollforward(
            fixture, contributes: true, attribution: .declared
        )
    ))
    var entries = firstPeriod.rollforward.allocation.period.ledger.journal.entries
    if withMovements {
        entries.append(try fixture.entry(
            id: 8,
            time: projectionDate("2027-04-01").timeIntervalSince1970,
            entity: fixture.secondOwner,
            debit: fixture.bank,
            credit: fixture.equity,
            amount: 25
        ))
        entries.append(try fixture.entry(
            id: 9,
            time: projectionDate("2027-09-01").timeIntervalSince1970,
            entity: fixture.owner,
            debit: fixture.dividends,
            credit: fixture.bank,
            amount: 7
        ))
    }
    let ledger = try Ledger(.init(journal: Journal(.init(
        entries: entries,
        chart: fixture.chart,
        entities: fixture.entities
    ))))
    let nextPeriod = try Period(.init(
        ledger: ledger,
        start: projectionDate("2027-01-01"),
        end: projectionDate("2028-01-01")
    ))
    let allocation = try Ownership.Allocation().evaluate(.init(
        period: nextPeriod,
        ownership: firstPeriod.rollforward.allocation.ownership,
        policy: .init(basis: .timeline, attribution: .effective)
    ))
    let opening = try Equity.Continuation().evaluate(.init(
        previous: firstPeriod.closingState,
        allocation: allocation
    ))
    return try Equity.Advancement().evaluate(.init(
        opening: opening,
        contributions: [fixture.equity],
        drawings: [fixture.dividends]
    ))
}

extension AccountingTestFlowsSuite {
    static var accountingV2EquityProjectionFlow: TestFlow {
        TestFlow("accounting-v2-equity-projection", tags: ["accounting", "v2", "equity"]) {
            Step("temporal capital and already-effective profit remain distinct") {
                let fixture = try V2ClosingFixture()
                let original = try projectionRollforward(fixture, contributes: true)
                let result = try Equity.Projection().evaluate(.init(rollforward: original))
                let state = result.closingState
                try Expect.equal(state.boundary, try projectionDate("2027-01-01"), "reporting boundary")
                try Expect.equal(state.periodStart, try projectionDate("2026-01-01"), "originating period")
                try Expect.equal(state.openingStateIdentifier, original.anchor.position.provenance.result, "opening lineage retained")
                try Expect.equal(state.recordedCapital[fixture.owner], 30, "A original capital after drawing")
                try Expect.equal(state.recordedCapital[fixture.secondOwner], 50, "B original contributed capital")
                try Expect.equal(state.allocatedProfit[fixture.owner], 205, "original allocation preserved")
                try Expect.equal(state.effectiveProfit[fixture.owner], 205, "effective profit stored independently")
                try Expect.equal(state.recordedCapitalTotal, 80, "capital total")
                try Expect.equal(state.allocatedProfitTotal, 205, "selected income total")
                try Expect.equal(state.effectiveProfitTotal, 205, "beneficiary income total")
                try Expect.equal(state.directTotal, result.directTotal, "direct reconciliation")
                try Expect.equal(state.effectiveTotal, result.effectiveTotal, "effective reconciliation")
                try Expect.equal(result.segments.count, 2, "two time windows")
                try Expect.equal(result.segments[0].directClosing[fixture.owner], 165, "opening and first profit")
                try Expect.equal(result.segments[1].contributions[fixture.secondOwner], 50, "dated contribution")
                try Expect.equal(result.segments[1].drawings[fixture.owner], 10, "dated withdrawal")
                try Expect.equal(result.segments[1].profit[fixture.owner], 80, "already-effective profit")
                try Expect.equal(result.directClosing[fixture.owner], 235, "direct A")
                try Expect.equal(result.directClosing[fixture.secondOwner], 50, "direct B capital")
                try Expect.equal(result.effectiveClosing[fixture.owner], 285, "B capital distributed exactly once")
                try Expect.equal(result.effectiveClosing[fixture.secondOwner] == nil, true, "collapsed owner absent")
                try Expect.equal(result.adjustments[fixture.owner], 50, "only recorded capital transferred")
                try Expect.equal(result.adjustments[fixture.secondOwner], -50, "zero-sum adjustment")
                try Expect.equal(result.adjustmentTotal, 0, "conservation")
                try Expect.equal(result.segments[1].movements.map(\.source.entryID.value), [4, 7], "movement sources")
                try Expect.equal(result.segments.map(\.profitSources.count), [2, 1], "income source coordinates")
                try Expect.equal(result.rollforward.allocation.period.ledger.postings.count, 14, "immutable ledger")
            }

            Step("declared profit resolves once when earned, not again at closing") {
                let fixture = try V2ClosingFixture()
                let original = try projectionRollforward(
                    fixture, contributes: true, attribution: .declared
                )
                let result = try Equity.Projection().evaluate(.init(rollforward: original))
                let state = result.closingState
                try Expect.equal(state.recordedCapital[fixture.owner], 30, "original A capital")
                try Expect.equal(state.recordedCapital[fixture.secondOwner], 50, "original B capital")
                try Expect.equal(state.allocatedProfit[fixture.owner], 173, "A declared income remains recorded")
                try Expect.equal(state.allocatedProfit[fixture.secondOwner], 32, "B declared income remains recorded")
                try Expect.equal(state.effectiveProfit[fixture.owner], 205, "beneficiary retains earned income")
                try Expect.equal(state.effectiveProfit[fixture.secondOwner] == nil, true, "declared origin is not an effective beneficiary")
                try Expect.equal(state.directTotal, 285, "declared closing conserves")
                try Expect.equal(state.effectiveTotal, 285, "effective closing conserves")
                try Expect.equal(result.segments[1].profit[fixture.owner], 48, "declared owner A")
                try Expect.equal(result.segments[1].profit[fixture.secondOwner], 32, "declared pool B")
                try Expect.equal(result.directClosing[fixture.owner], 203, "direct owner A")
                try Expect.equal(result.directClosing[fixture.secondOwner], 82, "direct B capital plus profit")
                try Expect.equal(result.effectiveClosing[fixture.owner], 285, "declared profit collapses once")
                try Expect.equal(result.adjustments[fixture.secondOwner], -82, "B adjustment includes profit")
                try Expect.equal(result.adjustmentTotal, 0, "conservation")
            }

            Step("expired capital routes reject, earned profit remains attributed") {
                let fixture = try V2ClosingFixture()
                let capital = try projectionRollforward(
                    fixture, contributes: true, expires: true, attribution: .declared
                )
                try Expect.throwsError("recorded capital with expired route rejects") {
                    _ = try Equity.Projection().evaluate(.init(rollforward: capital))
                }
                let onlyProfit = try projectionRollforward(
                    fixture, expires: true, attribution: .declared
                )
                let result = try Equity.Projection().evaluate(.init(rollforward: onlyProfit))
                try Expect.equal(result.segments.count, 3, "ownership discontinuity retained")
                try Expect.equal(result.segments[2].profit.values.reduce(Decimal.zero, +), 0, "no new income")
                try Expect.equal(result.effectiveClosing[fixture.owner], 235, "previous profit stays with beneficiary")
                try Expect.equal(result.directClosing[fixture.secondOwner], 32, "declared origin stays inspectable")
                try Expect.equal(result.adjustmentTotal, 0, "adjustment remains zero sum")
            }

            Step("posted profit uses actual dated source and snapshot basis rejects") {
                let fixture = try V2ClosingFixture()
                let posted = try projectionPostedRollforward(fixture)
                let result = try Equity.Projection().evaluate(.init(rollforward: posted))
                try Expect.equal(result.segments.count, 2, "posted profit follows ownership windows")
                try Expect.equal(result.segments[0].profit.values.reduce(Decimal.zero, +), 0, "no early posted income")
                try Expect.equal(result.segments[1].profit[fixture.secondOwner], 205, "posted owner preserved")
                try Expect.equal(result.effectiveClosing[fixture.owner], 235, "posted pool collapses once")
                try Expect.equal(result.segments[1].profitSources.map(\.entryID.value), [7], "exact posted source")
                let snapshot = try projectionRollforward(fixture, snapshot: true)
                try Expect.throwsError("snapshot-based income has no temporal allocation") {
                    _ = try Equity.Projection().evaluate(.init(rollforward: snapshot))
                }
            }

            Step("next period retains earned profit separately from capital") {
                let fixture = try V2ClosingFixture()
                let previous = try Equity.Projection().evaluate(.init(
                    rollforward: projectionRollforward(
                        fixture, contributes: true, attribution: .declared
                    )
                ))
                let nextPeriod = try Period(.init(
                    ledger: previous.rollforward.allocation.period.ledger,
                    start: projectionDate("2027-01-01"),
                    end: projectionDate("2028-01-01")
                ))
                let nextAllocation = try Ownership.Allocation().evaluate(.init(
                    period: nextPeriod,
                    ownership: previous.rollforward.allocation.ownership,
                    policy: .init(basis: .timeline, attribution: .effective)
                ))
                let result = try Equity.Continuation().evaluate(.init(
                    previous: previous.closingState, allocation: nextAllocation
                ))
                try Expect.equal(result.recordedCapital[fixture.owner], 30, "original A capital")
                try Expect.equal(result.recordedCapital[fixture.secondOwner], 50, "original B capital")
                try Expect.equal(result.allocatedProfit[fixture.owner], 173, "original A profit")
                try Expect.equal(result.allocatedProfit[fixture.secondOwner], 32, "original B profit")
                try Expect.equal(result.effectiveProfit[fixture.owner], 205, "earned effective profit")
                try Expect.equal(result.directOpening[fixture.owner], 203, "direct A opening")
                try Expect.equal(result.directOpening[fixture.secondOwner], 82, "direct B opening")
                try Expect.equal(result.effectiveOpening[fixture.owner], 285, "capital rerouted, profit not rerouted")
                try Expect.equal(result.effectiveOpening[fixture.secondOwner] == nil, true, "B is not an effective beneficiary")
                try Expect.equal(result.openingAdjustments[fixture.owner], 82, "A opening adjustment")
                try Expect.equal(result.openingAdjustments[fixture.secondOwner], -82, "B opening adjustment")
                try Expect.equal(result.directTotal, previous.directTotal, "direct year-to-year conservation")
                try Expect.equal(result.effectiveTotal, previous.effectiveTotal, "effective year-to-year conservation")
                try Expect.equal(result.adjustmentTotal, 0, "no new capital")
                try Expect.equal(nextAllocation.netIncome, 300, "future revenue belongs to next period")
                try Expect.equal(nextAllocation.amounts[fixture.owner], 300, "next-year income allocated independently")
                try Expect.equal(nextAllocation.segments[0].sources.map(\.entryID.value), [6], "future entry source preserved")
                try Expect.equal(result.directTotal, 285, "new income does not enter inherited opening")
            }

            Step("continuation rejects gaps and snapshot profit basis") {
                let fixture = try V2ClosingFixture()
                let previous = try Equity.Projection().evaluate(.init(
                    rollforward: projectionRollforward(fixture, contributes: true)
                ))
                let ledger = previous.rollforward.allocation.period.ledger
                let ownership = previous.rollforward.allocation.ownership
                let gap = try Period(.init(
                    ledger: ledger,
                    start: projectionDate("2027-02-01"),
                    end: projectionDate("2028-01-01")
                ))
                let gapAllocation = try Ownership.Allocation().evaluate(.init(
                    period: gap, ownership: ownership,
                    policy: .init(basis: .timeline)
                ))
                try Expect.throwsError("gap between reporting periods") {
                    _ = try Equity.Continuation().evaluate(.init(
                        previous: previous.closingState, allocation: gapAllocation
                    ))
                }
                let adjacent = try Period(.init(
                    ledger: ledger,
                    start: projectionDate("2027-01-01"),
                    end: projectionDate("2028-01-01")
                ))
                let snapshotAllocation = try Ownership.Allocation().evaluate(.init(
                    period: adjacent, ownership: ownership,
                    policy: .init(basis: .snapshot(try projectionDate("2027-06-01")))
                ))
                try Expect.throwsError("historical continuation needs temporal profit") {
                    _ = try Equity.Continuation().evaluate(.init(
                        previous: previous.closingState, allocation: snapshotAllocation
                    ))
                }
            }

            Step("continuation rejects changed historical journal sources") {
                let fixture = try V2ClosingFixture()
                let previous = try Equity.Projection().evaluate(.init(
                    rollforward: projectionRollforward(
                        fixture, contributes: true, attribution: .declared
                    )
                ))
                let entries = previous.rollforward.allocation.period.ledger.journal.entries
                try Expect.equal(
                    previous.closingState.sourceHistory.entries.map(\.id.value),
                    [1, 2, 3, 4, 5, 7],
                    "closing captures exact pre-boundary entries, not future entry 6"
                )

                func expectHistoricalRejection(_ candidate: [Entry], label: String) throws {
                    let journal = try Journal(.init(
                        entries: candidate,
                        chart: fixture.chart,
                        entities: fixture.entities
                    ))
                    let period = try Period(.init(
                        ledger: Ledger(.init(journal: journal)),
                        start: projectionDate("2027-01-01"),
                        end: projectionDate("2028-01-01")
                    ))
                    let allocation = try Ownership.Allocation().evaluate(.init(
                        period: period,
                        ownership: previous.rollforward.allocation.ownership,
                        policy: .init(basis: .timeline, attribution: .effective)
                    ))
                    let observed: Equity.Continuation.Error?
                    do {
                        _ = try Equity.Continuation().evaluate(.init(
                            previous: previous.closingState,
                            allocation: allocation
                        ))
                        observed = nil
                    } catch {
                        observed = error as? Equity.Continuation.Error
                    }
                    try Expect.equal(
                        observed == .incompatibleHistoricalJournal,
                        true,
                        "\(label): exact historical mismatch rejection"
                    )
                }

                let backfill = try fixture.entry(
                    id: 10,
                    time: projectionDate("2026-05-01").timeIntervalSince1970,
                    debit: fixture.bank,
                    credit: fixture.revenue,
                    amount: 15
                )
                try expectHistoricalRejection(entries + [backfill], label: "backdated entry")

                let altered = try fixture.entry(
                    id: 2,
                    time: projectionDate("2026-03-01").timeIntervalSince1970,
                    debit: fixture.bank,
                    credit: fixture.revenue,
                    amount: 201
                )
                try expectHistoricalRejection(
                    entries.map { $0.id.value == 2 ? altered : $0 },
                    label: "modified historical amount"
                )
                try expectHistoricalRejection(
                    entries.filter { $0.id.value != 3 },
                    label: "deleted historical entry"
                )
            }

            Step("continuation accepts reordered entries and future-only changes") {
                let fixture = try V2ClosingFixture()
                let previous = try Equity.Projection().evaluate(.init(
                    rollforward: projectionRollforward(
                        fixture, contributes: true, attribution: .declared
                    )
                ))
                let entries = previous.rollforward.allocation.period.ledger.journal.entries

                func continueWith(_ candidate: [Entry]) throws -> (
                    opening: Equity.Continuation.Result,
                    allocation: Ownership.Allocation.Result,
                    journal: Journal
                ) {
                    let journal = try Journal(.init(
                        entries: candidate,
                        chart: fixture.chart,
                        entities: fixture.entities
                    ))
                    let period = try Period(.init(
                        ledger: Ledger(.init(journal: journal)),
                        start: projectionDate("2027-01-01"),
                        end: projectionDate("2028-01-01")
                    ))
                    let allocation = try Ownership.Allocation().evaluate(.init(
                        period: period,
                        ownership: previous.rollforward.allocation.ownership,
                        policy: .init(basis: .timeline, attribution: .effective)
                    ))
                    let opening = try Equity.Continuation().evaluate(.init(
                        previous: previous.closingState,
                        allocation: allocation
                    ))
                    return (opening, allocation, journal)
                }

                let reordered = try continueWith(Array(entries.reversed()))
                try Expect.equal(
                    Journal.History(reordered.journal, before: previous.closingState.boundary),
                    previous.closingState.sourceHistory,
                    "journal entry order does not change historical evidence"
                )
                try Expect.equal(reordered.opening.directTotal, 285, "reordered history opens unchanged")
                try Expect.equal(reordered.allocation.netIncome, 300, "reordered future profit unchanged")

                let boundaryEntry = try fixture.entry(
                    id: 10,
                    time: projectionDate("2027-01-01").timeIntervalSince1970,
                    debit: fixture.bank,
                    credit: fixture.revenue,
                    amount: 17
                )
                let extended = try continueWith(entries + [boundaryEntry])
                try Expect.equal(
                    Journal.History(extended.journal, before: previous.closingState.boundary),
                    previous.closingState.sourceHistory,
                    "entry on next-period boundary does not modify previous history"
                )
                try Expect.equal(extended.opening.directTotal, 285, "new future entry leaves inherited equity unchanged")
                try Expect.equal(extended.allocation.netIncome, 317, "boundary entry enters new-period income")

                let changedFuture = try fixture.entry(
                    id: 6,
                    time: projectionDate("2027-02-01").timeIntervalSince1970,
                    debit: fixture.bank,
                    credit: fixture.revenue,
                    amount: 350
                )
                let revised = try continueWith(entries.map {
                    $0.id.value == 6 ? changedFuture : $0
                })
                try Expect.equal(
                    Journal.History(revised.journal, before: previous.closingState.boundary),
                    previous.closingState.sourceHistory,
                    "future-only revision does not change previous history"
                )
                try Expect.equal(revised.opening.directTotal, 285, "future revision leaves inherited equity unchanged")
                try Expect.equal(revised.allocation.netIncome, 350, "future revision is accounted for in new period")
            }

            Step("continuation detects exact historical source field drift") {
                let fixture = try V2ClosingFixture()
                let previous = try Equity.Projection().evaluate(.init(
                    rollforward: projectionRollforward(
                        fixture, contributes: true, attribution: .declared
                    )
                ))
                let entries = previous.rollforward.allocation.period.ledger.journal.entries
                let original = entries[1]
                try Expect.equal(original.id.value, 2, "targeted historical source ID")

                func expectRejected(_ replacement: Entry, label: String) throws {
                    let journal = try Journal(.init(
                        entries: entries.map { $0.id == original.id ? replacement : $0 },
                        chart: fixture.chart,
                        entities: fixture.entities
                    ))
                    let period = try Period(.init(
                        ledger: Ledger(.init(journal: journal)),
                        start: projectionDate("2027-01-01"),
                        end: projectionDate("2028-01-01")
                    ))
                    let allocation = try Ownership.Allocation().evaluate(.init(
                        period: period,
                        ownership: previous.rollforward.allocation.ownership,
                        policy: .init(basis: .timeline, attribution: .effective)
                    ))
                    let observed: Equity.Continuation.Error?
                    do {
                        _ = try Equity.Continuation().evaluate(.init(
                            previous: previous.closingState,
                            allocation: allocation
                        ))
                        observed = nil
                    } catch {
                        observed = error as? Equity.Continuation.Error
                    }
                    try Expect.equal(
                        observed == .incompatibleHistoricalJournal,
                        true,
                        "\(label): exact historical source mismatch"
                    )
                }

                try expectRejected(Entry(.init(
                    id: original.id,
                    date: original.date,
                    lines: original.lines,
                    sort: original.sort,
                    details: original.details,
                    metadata: ["source": "amended"]
                )), label: "metadata")

                try expectRejected(Entry(.init(
                    id: original.id,
                    date: original.date,
                    lines: original.lines,
                    sort: original.sort,
                    details: "changed source note",
                    metadata: original.metadata
                )), label: "details")

                try expectRejected(Entry(.init(
                    id: original.id,
                    date: original.date,
                    lines: original.lines,
                    sort: .adjusting,
                    details: original.details,
                    metadata: original.metadata
                )), label: "sort")

                try expectRejected(Entry(.init(
                    id: original.id,
                    date: original.date,
                    lines: Array(original.lines.reversed()),
                    sort: original.sort,
                    details: original.details,
                    metadata: original.metadata
                )), label: "line order")

                try expectRejected(Entry(.init(
                    id: Entry.ID(11),
                    date: original.date,
                    lines: original.lines,
                    sort: original.sort,
                    details: original.details,
                    metadata: original.metadata
                )), label: "entry identity")

                try expectRejected(Entry(.init(
                    id: original.id,
                    date: original.date.addingTimeInterval(86_400),
                    lines: original.lines,
                    sort: original.sort,
                    details: original.details,
                    metadata: original.metadata
                )), label: "entry date")
            }

            Step("three-year equity chain reconciles without historical duplication") {
                let fixture = try V2ClosingFixture()
                let second = try projectionAdvancementFixture(fixture, withMovements: true)
                let first = second.opening.previous
                var entries = second.opening.allocation.period.ledger.journal.entries

                entries.append(try fixture.entry(
                    id: 10,
                    time: projectionDate("2028-02-01").timeIntervalSince1970,
                    debit: fixture.bank,
                    credit: fixture.revenue,
                    amount: 90
                ))
                entries.append(try fixture.entry(
                    id: 11,
                    time: projectionDate("2028-05-01").timeIntervalSince1970,
                    debit: fixture.expenses,
                    credit: fixture.bank,
                    amount: 35
                ))
                entries.append(try fixture.entry(
                    id: 12,
                    time: projectionDate("2028-06-01").timeIntervalSince1970,
                    entity: fixture.secondOwner,
                    debit: fixture.bank,
                    credit: fixture.equity,
                    amount: 13
                ))
                entries.append(try fixture.entry(
                    id: 13,
                    time: projectionDate("2028-09-01").timeIntervalSince1970,
                    debit: fixture.dividends,
                    credit: fixture.bank,
                    amount: 8
                ))
                entries.append(try fixture.entry(
                    id: 14,
                    time: projectionDate("2029-03-01").timeIntervalSince1970,
                    debit: fixture.bank,
                    credit: fixture.revenue,
                    amount: 250
                ))

                let journal = try Journal(.init(
                    entries: entries,
                    chart: fixture.chart,
                    entities: fixture.entities
                ))
                let ledger = try Ledger(.init(journal: journal))
                let period = try Period(.init(
                    ledger: ledger,
                    start: projectionDate("2028-01-01"),
                    end: projectionDate("2029-01-01")
                ))
                let allocation = try Ownership.Allocation().evaluate(.init(
                    period: period,
                    ownership: second.opening.allocation.ownership,
                    policy: .init(basis: .timeline, attribution: .effective)
                ))
                let opening = try Equity.Continuation().evaluate(.init(
                    previous: second.closingState,
                    allocation: allocation
                ))
                let third = try Equity.Advancement().evaluate(.init(
                    opening: opening,
                    contributions: [fixture.equity],
                    drawings: [fixture.dividends]
                ))
                let state = third.closingState

                try Expect.equal(first.directTotal, 285, "2026 closing")
                try Expect.equal(first.recordedCapitalTotal, 80, "2026 recorded capital")
                try Expect.equal(first.allocatedProfitTotal, 205, "2026 profit")
                try Expect.equal(second.opening.directTotal, first.directTotal, "2027 inherits 2026")
                try Expect.equal(second.opening.allocation.netIncome, 300, "2027 income")
                try Expect.equal(second.directTotal, 603, "2027 closing")
                try Expect.equal(second.directTotal, 285 + 300 + 25 - 7, "2027 period conservation")
                try Expect.equal(second.effectiveTotal, second.directTotal, "2027 effective conservation")
                try Expect.equal(second.adjustmentTotal, 0, "2027 adjustments conserve")
                try Expect.equal(second.profitSources.map(\.entryID.value), [6], "2027 income source")
                try Expect.equal(second.movements.map(\.source.entryID.value).sorted(), [8, 9], "2027 capital sources")

                try Expect.equal(opening.directTotal, second.directTotal, "2028 inherits 2027")
                try Expect.equal(opening.effectiveTotal, second.effectiveTotal, "2028 effective opening")
                try Expect.equal(opening.directOpening, second.directClosing, "2027 direct closing becomes 2028 opening")
                try Expect.equal(opening.effectiveOpening, second.effectiveClosing, "2027 effective closing becomes 2028 opening")
                try Expect.equal(allocation.netIncome, 55, "2028 revenue less expenses")
                try Expect.equal(allocation.allocatedTotal, 55, "2028 income allocated exactly")
                try Expect.equal(allocation.remainder, 0, "2028 allocation conserved")
                try Expect.equal(third.profitSources.map(\.entryID.value).sorted(), [10, 11], "2028 profit sources only")
                try Expect.equal(third.movements.map(\.source.entryID.value).sorted(), [12, 13], "2028 capital sources only")
                try Expect.equal(third.directTotal, 603 + 55 + 13 - 8, "2028 period conservation")
                try Expect.equal(third.directTotal, 663, "2028 closing")
                try Expect.equal(third.effectiveTotal, 663, "2028 effective closing")
                try Expect.equal(third.adjustmentTotal, 0, "2028 adjustments conserve")
                try Expect.equal(third.directTotal, 40 + 205 + 50 - 10 + 300 + 25 - 7 + 55 + 13 - 8, "cumulative source-derived equity")

                try Expect.equal(state.recordedCapital[fixture.owner], 15, "A cumulative capital")
                try Expect.equal(state.recordedCapital[fixture.secondOwner], 88, "B cumulative capital")
                try Expect.equal(state.recordedCapitalTotal, 103, "cumulative recorded capital")
                try Expect.equal(state.allocatedProfit[fixture.owner], 528, "A cumulative allocated profit")
                try Expect.equal(state.allocatedProfit[fixture.secondOwner], 32, "B original allocated profit retained")
                try Expect.equal(state.effectiveProfit[fixture.owner], 560, "cumulative effective profit")
                try Expect.equal(state.allocatedProfitTotal, 560, "all income counted once")
                try Expect.equal(state.effectiveProfitTotal, 560, "effective income conserved")
                try Expect.equal(third.directClosing[fixture.owner], 543, "A direct closing")
                try Expect.equal(third.directClosing[fixture.secondOwner], 120, "B direct closing")
                try Expect.equal(third.effectiveClosing[fixture.owner], 663, "A effective closing")
                try Expect.equal(third.effectiveClosing[fixture.secondOwner] == nil, true, "collapsed B remains absent")
                try Expect.equal(third.adjustments[fixture.owner], 120, "A nonjournal adjustment")
                try Expect.equal(third.adjustments[fixture.secondOwner], -120, "B nonjournal adjustment")

                try Expect.equal(first.boundary, second.closingState.periodStart, "first adjacent boundary")
                try Expect.equal(second.closingState.boundary, state.periodStart, "second adjacent boundary")
                try Expect.equal(state.boundary, try projectionDate("2029-01-01"), "third closing boundary")
                try Expect.equal(state.openingStateIdentifier, first.openingStateIdentifier, "original opening lineage retained")
                try Expect.equal(first.sourceHistory.entries.map(\.id.value), [1, 2, 3, 4, 5, 7], "2026 exact history")
                try Expect.equal(second.closingState.sourceHistory.entries.map(\.id.value), [1, 2, 3, 4, 5, 6, 7, 8, 9], "2027 exact history")
                try Expect.equal(state.sourceHistory.entries.map(\.id.value), [1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13], "2028 history excludes 2029")
                try Expect.equal(
                    second.closingState.sourceHistory.entries.filter { $0.date < first.boundary },
                    first.sourceHistory.entries,
                    "2026 source evidence retained unchanged through 2027"
                )
                try Expect.equal(
                    state.sourceHistory.entries.filter { $0.date < second.closingState.boundary },
                    second.closingState.sourceHistory.entries,
                    "2027 source evidence retained unchanged through 2028"
                )
                try Expect.equal(
                    Journal.History(journal, before: second.closingState.boundary),
                    second.closingState.sourceHistory,
                    "2028 continuation uses identical historical sources"
                )
                try Expect.equal(second.opening.allocation.period.ledger.postings.count, 18, "2027 ledger retains nine source entries")
                try Expect.equal(ledger.postings.count, 28, "fourteen original source entries produce twenty-eight postings")
            }

            Step("later continuation guards accumulated history and chart identity") {
                let fixture = try V2ClosingFixture()
                let previous = try projectionAdvancementFixture(fixture, withMovements: true)
                let entries = previous.opening.allocation.period.ledger.journal.entries

                func continueWith(_ candidate: [Entry], chart: Chart) throws -> Equity.Continuation.Result {
                    let journal = try Journal(.init(
                        entries: candidate,
                        chart: chart,
                        entities: fixture.entities
                    ))
                    let period = try Period(.init(
                        ledger: Ledger(.init(journal: journal)),
                        start: projectionDate("2028-01-01"),
                        end: projectionDate("2029-01-01")
                    ))
                    let allocation = try Ownership.Allocation().evaluate(.init(
                        period: period,
                        ownership: previous.opening.allocation.ownership,
                        policy: .init(basis: .timeline, attribution: .effective)
                    ))
                    return try Equity.Continuation().evaluate(.init(
                        previous: previous.closingState,
                        allocation: allocation
                    ))
                }

                func expectRejected(
                    _ candidate: [Entry],
                    chart: Chart,
                    error expected: Equity.Continuation.Error,
                    label: String
                ) throws {
                    let observed: Equity.Continuation.Error?
                    do {
                        _ = try continueWith(candidate, chart: chart)
                        observed = nil
                    } catch {
                        observed = error as? Equity.Continuation.Error
                    }
                    try Expect.equal(observed == expected, true, label)
                }

                let backfill = try fixture.entry(
                    id: 10,
                    time: projectionDate("2027-11-01").timeIntervalSince1970,
                    debit: fixture.bank,
                    credit: fixture.revenue,
                    amount: 11
                )
                try expectRejected(
                    entries + [backfill], chart: fixture.chart,
                    error: .incompatibleHistoricalJournal,
                    label: "2027 backfill invalidates 2028 inherited closing"
                )

                let revisedCapital = try fixture.entry(
                    id: 8,
                    time: projectionDate("2027-04-01").timeIntervalSince1970,
                    entity: fixture.secondOwner,
                    debit: fixture.bank,
                    credit: fixture.equity,
                    amount: 26
                )
                try expectRejected(
                    entries.map { $0.id.value == 8 ? revisedCapital : $0 },
                    chart: fixture.chart,
                    error: .incompatibleHistoricalJournal,
                    label: "2027 capital revision invalidates 2028 inherited closing"
                )

                let extra = try Account(.init(
                    code: "EXTRA.EQUITY", category: .equity, postable: true
                ))
                let accounts = fixture.accountOrder.compactMap { fixture.chart.account($0) }
                let children = accounts.dropFirst().map(\.reference) + [extra.reference]
                let expanded = try Chart(.init(
                    accounts: accounts + [extra],
                    roots: [fixture.heading],
                    parents: Dictionary(uniqueKeysWithValues: children.map {
                        ($0, fixture.heading)
                    }),
                    behavior: .init(carryforward: .identity)
                ))
                try Expect.equal(
                    Journal.History(try Journal(.init(
                        entries: entries, chart: expanded, entities: fixture.entities
                    )), before: previous.closingState.boundary),
                    previous.closingState.sourceHistory,
                    "chart change leaves journal evidence intact"
                )
                try expectRejected(
                    entries, chart: expanded,
                    error: .incompatibleChart,
                    label: "chart migration requires explicit continuity adapter"
                )

                let unchanged = try continueWith(entries, chart: fixture.chart)
                try Expect.equal(unchanged.directTotal, 603, "unmodified historical source remains continuable")
            }

            Step("advancement preserves signed losses without reallocating old profit") {
                let fixture = try V2ClosingFixture()
                let previous = try projectionAdvancementFixture(fixture, withMovements: true)
                let loss = try fixture.entry(
                    id: 10,
                    time: projectionDate("2028-04-01").timeIntervalSince1970,
                    debit: fixture.expenses,
                    credit: fixture.bank,
                    amount: 40
                )
                let journal = try Journal(.init(
                    entries: previous.opening.allocation.period.ledger.journal.entries + [loss],
                    chart: fixture.chart,
                    entities: fixture.entities
                ))
                let ledger = try Ledger(.init(journal: journal))
                let period = try Period(.init(
                    ledger: ledger,
                    start: projectionDate("2028-01-01"),
                    end: projectionDate("2029-01-01")
                ))
                let allocation = try Ownership.Allocation().evaluate(.init(
                    period: period,
                    ownership: previous.opening.allocation.ownership,
                    policy: .init(basis: .timeline, attribution: .effective)
                ))
                let opening = try Equity.Continuation().evaluate(.init(
                    previous: previous.closingState, allocation: allocation
                ))
                let advanced = try Equity.Advancement().evaluate(.init(
                    opening: opening,
                    contributions: [fixture.equity],
                    drawings: [fixture.dividends]
                ))
                try Expect.equal(opening.directTotal, 603, "loss does not rewrite inherited opening")
                try Expect.equal(allocation.netIncome, -40, "signed new-period loss")
                try Expect.equal(allocation.allocatedTotal, -40, "signed loss allocated exactly")
                try Expect.equal(allocation.remainder, 0, "loss allocation conserves")
                try Expect.equal(advanced.closingState.recordedCapitalTotal, 98, "historical capital unchanged")
                try Expect.equal(advanced.closingState.allocatedProfit[fixture.owner], 433, "only new loss reduces A profit")
                try Expect.equal(advanced.closingState.allocatedProfit[fixture.secondOwner], 32, "B historical profit unchanged")
                try Expect.equal(advanced.closingState.allocatedProfitTotal, 465, "cumulative signed profit")
                try Expect.equal(advanced.closingState.effectiveProfit[fixture.owner], 465, "effective profit carries loss once")
                try Expect.equal(advanced.directTotal, 563, "603 minus 40")
                try Expect.equal(advanced.effectiveTotal, 563, "effective loss conservation")
                try Expect.equal(advanced.adjustmentTotal, 0, "loss creates no adjustment value")
                try Expect.equal(advanced.movements.isEmpty, true, "loss is not a capital movement")
                try Expect.equal(advanced.profitSources.map(\.entryID.value), [10], "loss source remains inspectable")
                try Expect.equal(ledger.postings.count, 20, "ten journal entries retain twenty postings")
            }

            Step("advancement rejects invalid capital account selections") {
                let fixture = try V2ClosingFixture()
                let opening = try projectionAdvancementFixture(fixture).opening

                func expectRejected(
                    contributions: Set<Account.Reference>,
                    drawings: Set<Account.Reference>,
                    error expected: Equity.Rollforward.Error,
                    label: String
                ) throws {
                    let observed: Equity.Advancement.Error?
                    do {
                        _ = try Equity.Advancement().evaluate(.init(
                            opening: opening,
                            contributions: contributions,
                            drawings: drawings
                        ))
                        observed = nil
                    } catch {
                        observed = error as? Equity.Advancement.Error
                    }
                    try Expect.equal(observed == .invalidMovement(expected), true, label)
                }

                try expectRejected(
                    contributions: [fixture.bank],
                    drawings: [fixture.dividends],
                    error: .invalidContributionAccount(fixture.bank),
                    label: "asset account cannot represent a contribution"
                )
                try expectRejected(
                    contributions: [fixture.equity],
                    drawings: [fixture.revenue],
                    error: .invalidDrawingAccount(fixture.revenue),
                    label: "revenue account cannot represent a drawing"
                )
            }

            Step("advancement counts only new period income and preserves inherited profit") {
                let fixture = try V2ClosingFixture()
                let result = try projectionAdvancementFixture(fixture)
                let state = result.closingState
                try Expect.equal(result.opening.directTotal, 285, "validated inherited opening")
                try Expect.equal(result.opening.allocation.netIncome, 300, "only 2027 income")
                try Expect.equal(state.periodStart, try projectionDate("2027-01-01"), "period start")
                try Expect.equal(state.boundary, try projectionDate("2028-01-01"), "closing boundary")
                try Expect.equal(state.openingStateIdentifier, result.opening.previous.openingStateIdentifier, "opening lineage")
                try Expect.equal(state.recordedCapital[fixture.owner], 30, "A original capital retained")
                try Expect.equal(state.recordedCapital[fixture.secondOwner], 50, "B original capital retained")
                try Expect.equal(state.allocatedProfit[fixture.owner], 473, "A historical plus 2027 profit")
                try Expect.equal(state.allocatedProfit[fixture.secondOwner], 32, "B declared historical profit retained")
                try Expect.equal(state.effectiveProfit[fixture.owner], 505, "effective earned profit counted once")
                try Expect.equal(state.effectiveProfit[fixture.secondOwner] == nil, true, "no retroactive profit transfer")
                try Expect.equal(result.directClosing[fixture.owner], 503, "A direct closing")
                try Expect.equal(result.directClosing[fixture.secondOwner], 82, "B direct closing")
                try Expect.equal(result.effectiveClosing[fixture.owner], 585, "effective closing")
                try Expect.equal(result.effectiveClosing[fixture.secondOwner] == nil, true, "B remains collapsed")
                try Expect.equal(result.adjustments[fixture.owner], 82, "A nonjournal adjustment")
                try Expect.equal(result.adjustments[fixture.secondOwner], -82, "B nonjournal adjustment")
                try Expect.equal(result.adjustmentTotal, 0, "adjustments conserve")
                try Expect.equal(result.directTotal, 585, "285 inherited plus 300 earned")
                try Expect.equal(result.effectiveTotal, 585, "effective conservation")
                try Expect.equal(result.movements.isEmpty, true, "no new capital transactions")
                try Expect.equal(result.profitSources.map(\.entryID.value), [6], "original 2027 source")
                try Expect.equal(result.opening.allocation.period.ledger.postings.count, 14, "ledger untouched")
            }

            Step("following empty year does not allocate historical income again") {
                let fixture = try V2ClosingFixture()
                let second = try projectionAdvancementFixture(fixture)
                let thirdPeriod = try Period(.init(
                    ledger: second.opening.allocation.period.ledger,
                    start: projectionDate("2028-01-01"),
                    end: projectionDate("2029-01-01")
                ))
                let thirdAllocation = try Ownership.Allocation().evaluate(.init(
                    period: thirdPeriod,
                    ownership: second.opening.allocation.ownership,
                    policy: .init(basis: .timeline, attribution: .effective)
                ))
                let thirdOpening = try Equity.Continuation().evaluate(.init(
                    previous: second.closingState,
                    allocation: thirdAllocation
                ))
                let third = try Equity.Advancement().evaluate(.init(
                    opening: thirdOpening,
                    contributions: [fixture.equity],
                    drawings: [fixture.dividends]
                ))
                try Expect.equal(thirdAllocation.netIncome, 0, "no 2028 income")
                try Expect.equal(thirdOpening.directTotal, 585, "2027 closing becomes 2028 opening")
                try Expect.equal(third.closingState.recordedCapital, second.closingState.recordedCapital, "capital unchanged")
                try Expect.equal(third.closingState.allocatedProfit, second.closingState.allocatedProfit, "historical allocated profit unchanged")
                try Expect.equal(third.closingState.effectiveProfit, second.closingState.effectiveProfit, "historical effective profit unchanged")
                try Expect.equal(third.directTotal, 585, "no double-counted profit")
                try Expect.equal(third.effectiveTotal, 585, "effective closing conserved")
                try Expect.equal(third.adjustmentTotal, 0, "nonjournal adjustment conserved")
                try Expect.equal(third.movements.isEmpty, true, "no capital postings")
                try Expect.equal(third.profitSources.isEmpty, true, "no new income sources")
                try Expect.equal(third.closingState.boundary, try projectionDate("2029-01-01"), "third closing boundary")
            }

            Step("new-period capital movements change recorded capital with exact sources") {
                let fixture = try V2ClosingFixture()
                let result = try projectionAdvancementFixture(fixture, withMovements: true)
                let state = result.closingState
                try Expect.equal(result.opening.directTotal, 285, "unchanged opening")
                try Expect.equal(result.movements.count, 2, "two sourced capital movements")
                try Expect.equal(result.movements.map(\.source.entryID.value).sorted(), [8, 9], "exact 2027 entry IDs")
                let contributions = result.movements.filter {
                    if case .contribution = $0.kind { return true }
                    return false
                }
                let drawings = result.movements.filter {
                    if case .drawing = $0.kind { return true }
                    return false
                }
                try Expect.equal(contributions.count, 1, "one contribution")
                try Expect.equal(drawings.count, 1, "one drawing")
                try Expect.equal(contributions[0].owner, fixture.secondOwner, "B contribution owner")
                try Expect.equal(contributions[0].amount, 25, "positive contribution")
                try Expect.equal(drawings[0].owner, fixture.owner, "A drawing owner")
                try Expect.equal(drawings[0].amount, 7, "positive drawing")
                try Expect.equal(state.recordedCapital[fixture.owner], 23, "A capital after drawing")
                try Expect.equal(state.recordedCapital[fixture.secondOwner], 75, "B capital after contribution")
                try Expect.equal(state.allocatedProfit[fixture.owner], 473, "A profit unaffected by capital")
                try Expect.equal(state.allocatedProfit[fixture.secondOwner], 32, "B historical profit unaffected")
                try Expect.equal(state.effectiveProfit[fixture.owner], 505, "earned effective profit unaffected")
                try Expect.equal(result.directClosing[fixture.owner], 496, "A direct closing")
                try Expect.equal(result.directClosing[fixture.secondOwner], 107, "B direct closing")
                try Expect.equal(result.effectiveClosing[fixture.owner], 603, "effective closing")
                try Expect.equal(result.adjustments[fixture.owner], 107, "A effective difference")
                try Expect.equal(result.adjustments[fixture.secondOwner], -107, "B effective difference")
                try Expect.equal(result.directTotal, 603, "285 plus 300 plus 25 minus 7")
                try Expect.equal(result.effectiveTotal, 603, "same consolidated total")
                try Expect.equal(result.adjustmentTotal, 0, "nonjournal conservation")
                try Expect.equal(result.profitSources.map(\.entryID.value), [6], "profit source not confused with capital")
                try Expect.equal(result.opening.allocation.period.ledger.postings.count, 18, "nine entries, no manufactured lines")
            }
        }
    }
}
