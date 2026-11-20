import Accounting
import AccountingCompiler
import Foundation
import TestFlows

private func makeRollupParityNode(
    id: Int,
    code: String,
    level: UInt8,
    direction: Direction? = nil
) throws -> RGSNode {
    let side: RGSNodeSide = code.hasPrefix("B") ? .balance : .profitLoss
    return try RGSNode(
        id: id,
        codes: .init(code: code),
        labels: .init(short: code, long: code),
        direction: direction,
        level: level,
        temporality: side == .balance ? .instant : .duration,
        side: side
    )
}

extension AccountingTestFlowsSuite {
    static var resolvedPostingRollupFlow: TestFlow {
        TestFlow("accounting-resolved-posting-rollup", tags: ["accounting", "chart", "parity"]) {
            Step("preserves resolved entries and matches legacy RGS totals") {
                let source = try CompiledChart(
                    name: "resolved-rollup-parity",
                    version: .init(major: 3, minor: 8),
                    nodes: [
                        try makeRollupParityNode(id: 100, code: "B", level: 1),
                        try makeRollupParityNode(id: 101, code: "BLim", level: 2),
                        try makeRollupParityNode(id: 102, code: "BLimBan", level: 3),
                        try makeRollupParityNode(id: 103, code: "BLimBanRba", level: 4, direction: .debit),
                        try makeRollupParityNode(id: 104, code: "BLimKas", level: 3),
                        try makeRollupParityNode(id: 105, code: "BLimKasKas", level: 4, direction: .debit),
                        try makeRollupParityNode(id: 200, code: "W", level: 1),
                        try makeRollupParityNode(id: 201, code: "WOmz", level: 2),
                        try makeRollupParityNode(id: 202, code: "WOmzNod", level: 3),
                        try makeRollupParityNode(id: 203, code: "WOmzNodOdh", level: 4, direction: .credit)
                    ]
                )
                let entries = try ECModelFixtures.resolveEntries(
                    ECModelFixtures.validResolutionEntrySource
                )
                let bankLine = entries[0].lines[0]
                let revenueLine = entries[0].lines[1]
                let localKey = try AccountKey("LOCAL-100")
                let enriched = ResolvedEntry(
                    id: 9301,
                    date: entries[0].date,
                    lines: [
                        ResolvedLine(
                            entity: bankLine.entity,
                            account: bankLine.account,
                            direction: .debit,
                            amount: 4,
                            adjustment: bankLine.adjustment,
                            localAccount: localKey
                        ),
                        ResolvedLine(
                            entity: revenueLine.entity,
                            account: revenueLine.account,
                            direction: .credit,
                            amount: 4,
                            adjustment: revenueLine.adjustment
                        )
                    ],
                    details: "retained source metadata",
                    timezone: "Europe/Amsterdam",
                    metadata: ["reference": "invoice-9301"],
                    transactionReferences: entries[0].transactionReferences
                )
                let completeEntries = entries + [enriched]
                let chart = try RGSChartProvider().compile(source)
                let batch = try chart.postings(from: completeEntries)
                let rollup = try chart.rollup(batch.postings)

                try Expect.equal(batch.entries.count, 3, "original resolved entries retained")
                try Expect.equal(batch.postings.count, 6, "all source lines retained")
                try Expect.equal(
                    batch.postings.map(\.origin.entryIndex),
                    [0, 0, 1, 1, 2, 2],
                    "posting origins preserve entry order"
                )
                try Expect.equal(
                    batch.postings.map(\.amount),
                    [Decimal(10), Decimal(-10), Decimal(5), Decimal(-5), Decimal(4), Decimal(-4)],
                    "signed amounts preserve debit-positive convention"
                )
                let lastBankSource = batch.postings[4].origin
                try Expect.equal(batch.entry(for: lastBankSource)?.id, 9301, "entry identity retained")
                try Expect.equal(
                    batch.entry(for: lastBankSource)?.metadata["reference"],
                    "invoice-9301",
                    "entry metadata retained"
                )
                try Expect.equal(
                    batch.line(for: lastBankSource)?.localAccount,
                    localKey,
                    "local posting identity is not flattened to RGS"
                )
                try Expect.equal(
                    batch.entry(for: lastBankSource)?.transactionReferences,
                    entries[0].transactionReferences,
                    "transaction references retained"
                )

                let bank = try AccountKey("BLimBanRba")
                let balanceRoot = try AccountKey("B")
                let incomeRoot = try AccountKey("W")
                try Expect.equal(rollup.totalsByAccount[bank], 14, "bank net including local posting")
                try Expect.equal(rollup.totalsByAccount[balanceRoot], 19, "balance ancestor total")
                try Expect.equal(rollup.totalsByAccount[incomeRoot], -19, "income ancestor total")
                try Expect.equal(
                    rollup.postings(for: bank).map(\.origin.entryIndex),
                    [0, 2],
                    "bank ancestor can trace both source entries"
                )

                let trial = trialBalance(completeEntries)
                let (legacyIndex, _) = try RGSIndex.build(from: source.nodes)
                let legacySeed = RGSAssembler.seedLeafs(from: trial, using: legacyIndex)
                let legacyMaps = try RGSAssembler.makeMaps(from: source)
                let legacyRolled = RGSAssembler.rollupAmounts(
                    legacySeed,
                    parentById: legacyMaps.parentById
                )

                let projected = try RGSAssembler.rollupResolvedEntries(
                    completeEntries,
                    in: source
                )

                try Expect.equal(
                    projected.sourceSeedById,
                    legacySeed,
                    "direct source seeds match original trial-balance seeds"
                )
                try Expect.equal(
                    projected.sourceSeedAEById,
                    RGSAssembler.seedLeafsAE(from: trial, using: legacyIndex),
                    "default entity seeds match legacy nil-entity buckets"
                )

                let entityProjected = try RGSAssembler.rollupResolvedEntries(
                    completeEntries,
                    in: source,
                    entityId: { _ in 42 }
                )
                try Expect.equal(
                    entityProjected.sourceSeedAEById[AccEntKey(103, 42)],
                    Decimal(14),
                    "entity bucket retains native account and resolved entity mapping"
                )
                try Expect.equal(
                    entityProjected.sourceSeedAEById[AccEntKey(203, 42)],
                    Decimal(-19),
                    "entity buckets preserve debit-positive signed amounts"
                )

                try Expect.equal(
                    projected.parentById,
                    legacyMaps.parentById,
                    "validated chart hierarchy matches existing RGS assembler"
                )
                try Expect.equal(
                    projected.totalsById,
                    legacyRolled,
                    "native-ID projection matches every legacy rolled amount"
                )
                try Expect.equal(
                    projected.batch.entries.count,
                    completeEntries.count,
                    "compiler projection retains complete resolved entries"
                )
                try Expect.equal(
                    projected.batch.postings.count,
                    batch.postings.count,
                    "compiler projection retains every original posting"
                )
                try Expect.equal(
                    projected.postings(for: 103).map(\.origin.entryIndex),
                    [0, 2],
                    "native RGS leaf retains original entry references"
                )
                try Expect.equal(
                    projected.postings(for: 100).count,
                    3,
                    "native RGS ancestor retains all contributing balance postings"
                )
                try Expect.equal(
                    projected.line(for: projected.postings(for: 103)[1].origin)?.localAccount,
                    localKey,
                    "native-ID projection preserves local posting identity"
                )
                try Expect.equal(
                    projected.entry(for: projected.postings(for: 103)[1].origin)?.metadata["reference"],
                    "invoice-9301",
                    "native-ID projection preserves source metadata"
                )

                for node in source.nodes {
                    let key = try AccountKey(node.codes.code)
                    try Expect.equal(
                        rollup.totalsByAccount[key] ?? 0,
                        legacyRolled[node.id] ?? 0,
                        "parity at RGS node \(node.codes.code)"
                    )
                }
                try Expect.equal(
                    rollup.totalsByAccount.values.reduce(Decimal(0), +),
                    legacyRolled.values.reduce(Decimal(0), +),
                    "all aggregate nodes match legacy sign conventions"
                )
            }

            Step("assembles resolved sources with legacy statement parity") {
                let chart = try CompiledChart(
                    name: "resolved-assembly-parity",
                    version: .init(major: 3, minor: 8),
                    nodes: [
                        try makeRollupParityNode(id: 100, code: "B", level: 1),
                        try makeRollupParityNode(id: 101, code: "BLim", level: 2),
                        try makeRollupParityNode(id: 102, code: "BLimBan", level: 3),
                        try makeRollupParityNode(id: 103, code: "BLimBanRba", level: 4, direction: .debit),
                        try makeRollupParityNode(id: 104, code: "BLimKas", level: 3),
                        try makeRollupParityNode(id: 105, code: "BLimKasKas", level: 4, direction: .debit),
                        try makeRollupParityNode(id: 110, code: "BEiv", level: 2, direction: .credit),
                        try makeRollupParityNode(id: 111, code: "BEivKap", level: 3),
                        try makeRollupParityNode(id: 112, code: "BEivKapOnd", level: 4),
                        try makeRollupParityNode(id: 113, code: "BEivKapOndAow", level: 5, direction: .credit),
                        try makeRollupParityNode(id: 200, code: "W", level: 1),
                        try makeRollupParityNode(id: 201, code: "WOmz", level: 2),
                        try makeRollupParityNode(id: 202, code: "WOmzNod", level: 3),
                        try makeRollupParityNode(id: 203, code: "WOmzNodOdh", level: 4, direction: .credit),
                        try makeRollupParityNode(id: 210, code: "WNer", level: 2),
                        try makeRollupParityNode(id: 211, code: "WNerKap", level: 3),
                        try makeRollupParityNode(id: 212, code: "WNerKapKap", level: 4, direction: .credit)
                    ]
                )
                let entries = try ECModelFixtures.resolveEntries(
                    ECModelFixtures.validResolutionEntrySource
                )
                let compiled = EntryCompileDriver.Result(
                    entities: EntityStore([:]),
                    accounts: try AccountStore(nodes: chart.nodes),
                    transactions: try TransactionStore([]),
                    entries: [],
                    resolved: entries
                )
                let cut = AssembleCut(target: .L5)
                let trial = trialBalance(entries)

                let index = try RGSIndex.build(from: chart.nodes).0
                try Expect.true(
                    trial.allSatisfy { index.byIdentifier[$0.accountCode] != nil },
                    "every source account must exist in the parity chart"
                )
                try Expect.equal(
                    RGSAssembler.seedLeafs(from: trial, using: index)
                        .values.reduce(Decimal(0), +),
                    Decimal(0),
                    "complete direct source seeds must balance"
                )

                for autoClose in [false, true] {
                    let legacy = try RGSAssembler.assemble(
                        chart: chart,
                        trialRows: trial,
                        cut: cut,
                        omslag: .ignore,
                        autoClose: autoClose
                    )
                    let resolved = try RGSAssembler.assembleResolved(
                        chart: chart,
                        entries: entries,
                        cut: cut,
                        omslag: .ignore,
                        autoClose: autoClose
                    )

                    let nativeCompatibility = try NativeOutputBuilder.buildCompileOutput(
                        result: compiled,
                        cut: cut,
                        omslag: .ignore,
                        autoClose: autoClose
                    )
                    let nativeResolved = try NativeOutputBuilder.buildResolvedCompileOutput(
                        result: compiled,
                        cut: cut,
                        omslag: .ignore,
                        autoClose: autoClose
                    )

                    if autoClose {
                        try Expect.equal(
                            nativeResolved.bundle.autoCloseAudit?.disposition,
                            AutoCloseOverlayDisposition.applied,
                            "validated native output records applied auto-close"
                        )
                        try Expect.equal(
                            nativeResolved.bundle.autoCloseAudit?.ni,
                            Decimal(-15),
                            "audit records signed source net income"
                        )
                        try Expect.equal(
                            nativeResolved.bundle.autoCloseAudit?.adjustedForManual,
                            Decimal(-15),
                            "unsuppressed overlay retains its full amount"
                        )
                        try Expect.equal(
                            nativeResolved.bundle.autoCloseAudit?.manualAtNetIncome,
                            Decimal(0),
                            "audit distinguishes derived net income from manual postings"
                        )
                    } else {
                        try Expect.true(
                            nativeResolved.bundle.autoCloseAudit == nil,
                            "disabled auto-close has no execution audit"
                        )
                    }

                    // Public compatibility API must preserve the validated
                    // result. The independent oracle remains RGSAssembler's
                    // direct trial-balance calculation above.
                    try Expect.equal(
                        nativeCompatibility.bundle.totalsById,
                        nativeResolved.bundle.totalsById,
                        "native compatibility delegates to validated assembly"
                    )
                    try Expect.equal(
                        nativeCompatibility.bundle.autoCloseAudit?.disposition,
                        nativeResolved.bundle.autoCloseAudit?.disposition,
                        "native compatibility preserves auto-close selection"
                    )
                    try Expect.equal(
                        nativeResolved.bundle.totalsById,
                        legacy.totalsById,
                        "validated native totals match independent trial-balance assembly"
                    )
                    try Expect.equal(
                        nativeResolved.bundle.balance.map(\.id),
                        legacy.balance.map(\.id),
                        "native balance presentation identities match independent oracle"
                    )
                    try Expect.equal(
                        nativeResolved.bundle.balance.map(\.amount),
                        legacy.balance.map(\.amount),
                        "native balance presentation amounts match independent oracle"
                    )
                    try Expect.equal(
                        nativeResolved.bundle.income.map(\.id),
                        legacy.income.map(\.id),
                        "native income presentation identities match independent oracle"
                    )
                    try Expect.equal(
                        nativeResolved.bundle.income.map(\.amount),
                        legacy.income.map(\.amount),
                        "native income presentation amounts match independent oracle"
                    )
                    try Expect.equal(
                        nativeResolved.output.bundle.totalsById,
                        nativeResolved.bundle.totalsById,
                        "compatibility output preserves validated statement totals"
                    )
                    try Expect.equal(
                        nativeResolved.movements.batch.entries.count,
                        entries.count,
                        "native compiler preserves original resolved entries"
                    )
                    try Expect.equal(
                        nativeResolved.movements.batch.postings.count,
                        entries.reduce(0) { $0 + $1.lines.count },
                        "native compiler preserves every source posting"
                    )
                    try Expect.equal(
                        nativeResolved.movements.sourceSeedById[203],
                        Decimal(-15),
                        "native source movements exclude derived net-income overlays"
                    )

                    try Expect.equal(
                        resolved.statements.totalsById,
                        legacy.totalsById,
                        "balance and derived overlay totals match legacy assembly"
                    )
                    try Expect.equal(
                        resolved.statements.balance.map(\.id),
                        legacy.balance.map(\.id),
                        "balance presentation nodes match legacy"
                    )
                    try Expect.equal(
                        resolved.statements.balance.map(\.amount),
                        legacy.balance.map(\.amount),
                        "balance presentation amounts match legacy"
                    )
                    try Expect.equal(
                        resolved.statements.income.map(\.id),
                        legacy.income.map(\.id),
                        "income presentation nodes match legacy"
                    )
                    try Expect.equal(
                        resolved.statements.income.map(\.amount),
                        legacy.income.map(\.amount),
                        "income presentation amounts match legacy"
                    )
                    try Expect.equal(
                        resolved.movements.batch.entries.count,
                        entries.count,
                        "source resolved entries retained through statement assembly"
                    )
                    try Expect.equal(
                        resolved.movements.batch.postings.count,
                        entries.reduce(0) { $0 + $1.lines.count },
                        "all original line contributions remain inspectable"
                    )
                    try Expect.equal(
                        resolved.movements.sourceSeedById[203],
                        Decimal(-15),
                        "source income postings remain independent of overlays"
                    )
                    try Expect.equal(
                        resolved.movements.sourceSeedById[212] ?? 0,
                        Decimal(0),
                        "derived net income is not fabricated as a source posting"
                    )

                    if autoClose {
                        try Expect.equal(
                            resolved.statements.totalsById[212],
                            Decimal(15),
                            "derived net income appears only in assembled presentation"
                        )
                        try Expect.equal(
                            resolved.statements.totalsById[113],
                            Decimal(-15),
                            "derived equity adjustment remains a presentation overlay"
                        )
                    }
                }
            }

            Step("rejects unresolved targets rather than skipping their sources") {
                let source = try CompiledChart(
                    name: "strict-resolved-targets",
                    version: .init(major: 3, minor: 8),
                    nodes: [
                        try makeRollupParityNode(id: 301, code: "B", level: 1),
                        try makeRollupParityNode(id: 302, code: "BLim", level: 2),
                        try makeRollupParityNode(id: 303, code: "BLimBan", level: 3),
                        try makeRollupParityNode(id: 304, code: "BLimBanRba", level: 4, direction: .debit)
                    ]
                )
                let chart = try RGSChartProvider().compile(source)
                let originals = try ECModelFixtures.resolveEntries(
                    ECModelFixtures.validResolutionEntrySource
                )
                try Expect.throwsError("missing RGS target cannot be dropped") {
                    _ = try chart.postings(from: originals)
                }
                let bankLine = originals[0].lines[0]
                let nonpostable = ResolvedEntry(
                    id: 9302,
                    date: originals[0].date,
                    lines: [
                        ResolvedLine(
                            entity: bankLine.entity,
                            account: try AccountKey("BLim"),
                            direction: .debit,
                            amount: 1,
                            adjustment: nil
                        )
                    ],
                    details: nil,
                    timezone: nil,
                    metadata: [:],
                    transactionReferences: []
                )
                try Expect.throwsError("RGS header cannot be posted to") {
                    _ = try chart.postings(from: [nonpostable])
                }
            }
        }
    }
}
