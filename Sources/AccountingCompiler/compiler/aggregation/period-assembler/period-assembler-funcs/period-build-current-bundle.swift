import Accounting
import Foundation

extension PeriodAssembler {
    @inline(__always)
    public static func buildCurrentBundle(
        chart: CompiledChart,
        wins: PeriodWindows,
        anchor: Date,
        result: EntryCompileDriver.Result,
        cut: AssembleCut,
        omslag: OmslagMode,
        entity: BusinessEntity,
        shape: PeriodShape,
        calendar: Calendar
    ) throws -> StatementBundle {
        let (eHist, eWin, _) = entriesForWindows(
            result.resolved,
            wins
        )

        let idIndex = result.entities.idIndex

        let tbHist = trialBalance(
            eHist,
            entityId: { idIndex[$0] }
        )
        let tbWin = trialBalance(
            eWin,
            entityId: { idIndex[$0] }
        )

        let slices = result.entities.ownershipSlices(
            asOf: wins.window.to ?? anchor
        )

        let bundle = try assembleSplitSeeds(
            chart: chart,
            tbIncomeWindow: tbWin,
            tbBalanceWindow: tbWin,
            tbOverlayForNI: tbWin,
            tbPreWindowForOpening: tbHist,
            cut: cut,
            omslag: omslag,
            entity: entity,
            ownershipSlices: slices,
            entityIdOnRow: { $0.entityId }
        )

        return attachFinancialAverages(
            bundle,
            shape: shape,
            range: wins.window,
            calendar: calendar
        )
    }
}
