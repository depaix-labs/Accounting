import Accounting
import Foundation

public extension RGSAssembler {
    /// Compatibility adapter for the existing period assembler.
    /// Routing is implemented by the shared native-ID opening policy.
    static func openingBegSeed(
        from tbHist: [TrialBalanceRow],
        chart: CompiledChart,
        index: RGSIndex,
        maps: RGSAssemblerResult,
        routing: PeriodOpeningRouting
    ) -> [Int: Decimal] {
        openingBegSeed(
            fromSourceSeeds: seedLeafs(from: tbHist, using: index),
            chart: chart,
            index: index,
            maps: maps,
            routing: routing
        )
    }
}
