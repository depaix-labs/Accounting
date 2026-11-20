import Accounting
import Foundation

public extension RGSAssembler {
    /// Compatibility adapter for entity-aware period opening balances.
    /// Historical equity remains attached to its original entity; only
    /// historical income follows the configured ownership allocation.
    static func openingBegSeedAE(
        from tbHist: [TrialBalanceRow],
        chart: CompiledChart,
        index: RGSIndex,
        maps: RGSAssemblerResult,
        routing: PeriodOpeningRouting,
        profitShareCode: String?,
        ownershipSlices: [OwnershipSlice] = [],
        entityIdOnRow: (TrialBalanceRow) -> Int? = { _ in nil }
    ) -> [AccEntKey: Decimal] {
        openingBegSeedAE(
            fromSourceSeeds: seedLeafsAE(
                from: tbHist,
                using: index,
                entityId: entityIdOnRow
            ),
            chart: chart,
            index: index,
            maps: maps,
            routing: routing,
            profitShareCode: profitShareCode,
            ownershipSlices: ownershipSlices
        )
    }
}
