import Accounting
import Foundation

public extension PeriodAssembler {
    /// Shared period calculation from direct, validated source seeds.
    /// Opening balances and NI overlays are derived presentation values.
    /// Source postings are never replaced by these adjustments.
    @inline(__always)
    internal static func assembleSplitSourceSeeds(
        chart: CompiledChart,
        sourceIncomeWindow: [Int: Decimal],
        sourceBalanceWindow: [Int: Decimal],
        sourceOverlayForNI: [Int: Decimal],
        sourcePreWindowForOpening: [Int: Decimal]?,
        sourceBalanceWindowAE: [AccEntKey: Decimal],
        sourcePreWindowForOpeningAE: [AccEntKey: Decimal]?,
        cut: AssembleCut,
        omslag: OmslagMode,
        entity: BusinessEntity,
        ownershipSlices: [OwnershipSlice] = []
    ) throws -> StatementBundle {
        // maps + index
        let ch  = try chart.ensuringIndex(enrichNodes: true, strict: false)
        guard let index = ch.index else { throw RGSAssemblerError.missingIndex }
        let maps = try RGSAssembler.makeMaps(from: ch)

        // Resolve NI/Equity targets for this BusinessEntity
        let targets  = entity.autoCloseTargets()
        guard
            let niId  = index.byIdentifier[targets.netIncomeCode],
            let eqId_ = index.byIdentifier[targets.retainedEarningsCode]
        else { throw RGSAssemblerError.missingIndex }

        // Ensure equity overlay goes to a non-Beg container
        let codeById: [Int:String] = Dictionary(uniqueKeysWithValues: ch.nodes.map { ($0.id, $0.codes.code) })
        @inline(__always) func isBeg(_ id: Int) -> Bool { (codeById[id] ?? "").hasSuffix("Beg") }
        let equityTargetId: Int = isBeg(eqId_) ? (maps.parentById[eqId_] ?? eqId_) : eqId_

        // Validate the original direct movements independently of
        // historical opening balances and derived closing overlays.
        let seedIncome = sourceIncomeWindow
        let seedWinBal = sourceBalanceWindow
        let seedOverlay = sourceOverlayForNI
        try RGSAssembler.assertSeedSumsToZero(seedIncome)
        try RGSAssembler.assertSeedSumsToZero(seedWinBal)
        try RGSAssembler.assertSeedSumsToZero(seedOverlay)

        // Opening (plain) → routed to Beg (your helper also injects pre-window NI into equity opening)
        let seedOpeningPlain: [Int: Decimal] = {
            guard let historical = sourcePreWindowForOpening,
                  !historical.isEmpty else {
                return [:]
            }
            return RGSAssembler.openingBegSeed(
                fromSourceSeeds: historical,
                chart: ch,
                index: index,
                maps: maps,
                routing: entity.periodOpeningRouting
            )
        }()

        // Base BS seed = Opening + WINDOW movements
        var seedBalance = seedOpeningPlain
        for (k, v) in seedWinBal { seedBalance[k, default: 0] += v }

        // // NI overlay from the same source you present (typically WINDOW)
        // let niOverlay = seedOverlay.reduce(into: Decimal(0)) { acc, kv in
        //     if maps.kindById[kv.key] == .income { acc += kv.value }
        // }

        // // Soft suppression: only suppress if WINDOW has manual postings at NI target
        // let manualAtNiWin = seedWinBal[niId] ?? 0
        // if niOverlay != 0 && manualAtNiWin == 0 {
        //     seedBalance[niId,           default: 0] += (-niOverlay) // zero P&L node
        //     seedBalance[equityTargetId, default: 0] += ( niOverlay) // push into equity container (non-Beg)
        // }

        // replacement for equity problem

        // NI overlay from the same source you present (typically WINDOW)
        let niOverlay = seedOverlay.reduce(into: Decimal(0)) { acc, kv in
            if maps.kindById[kv.key] == .income { acc += kv.value }
        }

        // Soft suppression + WARN: if WINDOW has manual postings at NI or Equity, warn & suppress
        let manualAtNiWin = seedWinBal[niId] ?? 0
        let manualAtEqWin = seedWinBal[equityTargetId] ?? 0

        let autoCloseAudit = AutoCloseAudit.evaluate(
            ni: niOverlay,
            niNode: (
                code: codeById[niId] ?? "#\(niId)",
                id: niId
            ),
            equityNode: (
                code: codeById[equityTargetId] ?? "#\(equityTargetId)",
                id: equityTargetId
            ),
            manualAtNetIncome: manualAtNiWin,
            manualAtEquity: manualAtEqWin
        )

        if niOverlay != 0 && !autoCloseAudit.suppressed {
            seedBalance[niId,           default: 0] += (-niOverlay) // zero P&L node
            seedBalance[equityTargetId, default: 0] += ( niOverlay) // push into equity container (non-Beg)
        }

        // Roll up by the real hierarchy
        var totalsIncome  = RGSAssembler.rollupAmounts(seedIncome,  parentById: maps.parentById)
        let totalsBalance = RGSAssembler.rollupAmounts(seedBalance, parentById: maps.parentById)

        // // Put period NI onto IS NI line (presentation)
        // let niWindow = seedIncome.reduce(into: Decimal(0)) { acc, kv in
        //     if maps.kindById[kv.key] == .income { acc += kv.value }
        // }
        // if niWindow != 0 { totalsIncome[niId, default: 0] += niWindow }

        // NI repeats the computed income within its own presentation branch,
        // but must not be rolled into the already-authoritative P&L root.
        let niWindow = seedIncome.reduce(into: Decimal(0)) { acc, kv in
            if maps.kindById[kv.key] == .income { acc += kv.value }
        }
        RGSAssembler.addDerivedIncomePresentation(
            niWindow,
            at: niId,
            into: &totalsIncome,
            parentById: maps.parentById
        )

        // -------- Entity breakdown (Balance) with ownership split on profit-share --------
        var breakdown: EntityBreakdown? = nil
        do {
            // AE Opening (routes Beg; preserves historical equity opening; splits only pre-window NI by ownershipSlices)
            var seedOpeningAE: [AccEntKey: Decimal] = [:]
            if let historicalAE = sourcePreWindowForOpeningAE,
               !historicalAE.isEmpty {
                seedOpeningAE = RGSAssembler.openingBegSeedAE(
                    fromSourceSeeds: historicalAE,
                    chart: ch,
                    index: index,
                    maps: maps,
                    routing: entity.periodOpeningRouting,
                    profitShareCode: entity.profitShareCode,
                    ownershipSlices: ownershipSlices
                )
            }

            // Original entity-account window movements.
            let seedWinBalAE = sourceBalanceWindowAE

            // Base = Opening(AE) + WINDOW(AE)
            var seedBalanceAE = seedOpeningAE
            for (k, v) in seedWinBalAE { seedBalanceAE[k, default: 0] += v }

            // NI overlay (AE) — push to equity/NI in nil-entity bucket (unless you want to apportion, later)

            // // --- AE NI overlay: allocate equity overlay by ownership slices (or nil-entity fallback)
            // if niOverlay != 0 && manualAtNiWin == 0 {
            //     // If you did NOT already overlay the plain (non-AE) seed earlier, uncomment these two lines:
            //     // seedBalance[niId,           default: 0] += (-niOverlay)
            //     // seedBalance[equityTargetId, default: 0] += ( niOverlay)

            //     if ownershipSlices.isEmpty {
            //         // No ownership info → dump to unassigned bucket
            //         seedBalanceAE[AccEntKey(equityTargetId, nil), default: 0] += niOverlay
            //     } else {
            //         // Split overlay across owners by percentage
            //         for s in ownershipSlices where s.percent != 0 {
            //             seedBalanceAE[AccEntKey(equityTargetId, s.entityId), default: 0] += (niOverlay * s.percent)
            //         }
            //     }

            //     // Zero the NI node in AE space (keep in nil-entity bucket)
            //     seedBalanceAE[AccEntKey(niId, nil), default: 0] -= niOverlay
            // }

            // --- AE NI overlay: allocate equity overlay by ownership slices (or nil-entity fallback)
            if niOverlay != 0 && !autoCloseAudit.suppressed {
                if ownershipSlices.isEmpty {
                    seedBalanceAE[AccEntKey(equityTargetId, nil), default: 0] += niOverlay
                } else {
                    for s in ownershipSlices where s.percent != 0 {
                        seedBalanceAE[AccEntKey(equityTargetId, s.entityId), default: 0] += (niOverlay * s.percent)
                    }
                }
                // Zero the NI node in AE space (keep in nil-entity bucket)
                seedBalanceAE[AccEntKey(niId, nil), default: 0] -= niOverlay
            }

            // Roll up preserving entity
            let totalsAE_Balance = RGSAssembler.rollupByAccountPreservingEntity(
                seedBalanceAE, parentById: maps.parentById
            )

            // Project AE → breakdown dictionary (account → entity → amount)
            var byAccount: [Int: [Int?: Decimal]] = [:]
            for (k, v) in totalsAE_Balance where v != 0 {
                byAccount[k.accountId, default: [:]][k.entityId, default: 0] += v
            }
            breakdown = .init(byAccount: byAccount)
        }

        // Force NI + Equity visible
        var localCut = cut
        localCut.includeCodes.append(
            contentsOf: [
                targets.netIncomeCode,
                targets.retainedEarningsCode
            ]
        )

        let rolled = AssemblerKernelSeedResult(
            totalsIncome: totalsIncome,
            totalsBalance: totalsBalance,
            breakdown: breakdown,
            netIncome: niWindow,
            effectiveCut: localCut
        )

        let bundle = try AssemblerKernel.makeBundle(
            chart: chart,
            index: index,
            maps: maps,
            cut: cut,
            omslag: omslag,
            businessEntity: entity,
            rolled: rolled
        )

        return bundle.withAutoCloseAudit(autoCloseAudit)
    }
}
