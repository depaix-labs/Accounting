import Accounting
import Foundation

public extension PeriodAssembler {
    /// Compatibility adapter for existing trial-balance callers.
    /// Only input conversion happens here. Accounting calculations remain
    /// exclusively in assembleSplitSourceSeeds.
    static func assembleSplitSeeds(
        chart: CompiledChart,
        tbIncomeWindow: [TrialBalanceRow],
        tbBalanceWindow: [TrialBalanceRow],
        tbOverlayForNI: [TrialBalanceRow],
        tbPreWindowForOpening: [TrialBalanceRow]?,
        cut: AssembleCut,
        omslag: OmslagMode,
        entity: BusinessEntity,
        ownershipSlices: [OwnershipSlice] = [],
        entityIdOnRow: (TrialBalanceRow) -> Int? = { _ in nil }
    ) throws -> StatementBundle {
        let indexed = try chart.ensuringIndex(
            enrichNodes: true,
            strict: false
        )
        guard let index = indexed.index else {
            throw RGSAssemblerError.missingIndex
        }

        let historical = tbPreWindowForOpening.map {
            RGSAssembler.seedLeafs(from: $0, using: index)
        }
        let historicalAE = tbPreWindowForOpening.map {
            RGSAssembler.seedLeafsAE(
                from: $0,
                using: index,
                entityId: entityIdOnRow
            )
        }

        return try assembleSplitSourceSeeds(
            chart: chart,
            sourceIncomeWindow: RGSAssembler.seedLeafs(
                from: tbIncomeWindow,
                using: index
            ),
            sourceBalanceWindow: RGSAssembler.seedLeafs(
                from: tbBalanceWindow,
                using: index
            ),
            sourceOverlayForNI: RGSAssembler.seedLeafs(
                from: tbOverlayForNI,
                using: index
            ),
            sourcePreWindowForOpening: historical,
            sourceBalanceWindowAE: RGSAssembler.seedLeafsAE(
                from: tbBalanceWindow,
                using: index,
                entityId: entityIdOnRow
            ),
            sourcePreWindowForOpeningAE: historicalAE,
            cut: cut,
            omslag: omslag,
            entity: entity,
            ownershipSlices: ownershipSlices
        )
    }

    /// Assemble already-validated period posting views without flattening
    /// them into TrialBalanceRow or changing their original source offsets.
    /// The caller retains the authoritative RGSPeriodResolvedSeedProjection.
    static func assembleSplitResolvedSeeds(
        chart: CompiledChart,
        incomeWindow: RGSPeriodResolvedSeedView,
        balanceWindow: RGSPeriodResolvedSeedView,
        overlayForNI: RGSPeriodResolvedSeedView,
        preWindowForOpening: RGSPeriodResolvedSeedView?,
        cut: AssembleCut,
        omslag: OmslagMode,
        entity: BusinessEntity,
        ownershipSlices: [OwnershipSlice] = []
    ) throws -> StatementBundle {
        try assembleSplitSourceSeeds(
            chart: chart,
            sourceIncomeWindow: incomeWindow.sourceSeedById,
            sourceBalanceWindow: balanceWindow.sourceSeedById,
            sourceOverlayForNI: overlayForNI.sourceSeedById,
            sourcePreWindowForOpening: preWindowForOpening?.sourceSeedById,
            sourceBalanceWindowAE: balanceWindow.sourceSeedAEById,
            sourcePreWindowForOpeningAE: preWindowForOpening?.sourceSeedAEById,
            cut: cut,
            omslag: omslag,
            entity: entity,
            ownershipSlices: ownershipSlices
        )
    }
}
