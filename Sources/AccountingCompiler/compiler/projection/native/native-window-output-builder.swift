import Accounting
import Foundation

public extension NativeOutputBuilder {
    /// Compile the explicitly supplied reporting window through validated
    /// source postings rather than reconstructing trial balances.
    /// Existing consumers continue receiving NativeCompileOutput.
    static func buildWindowOutput(
        result: EntryCompileDriver.Result,
        windows: PeriodWindows,
        anchor: Date,
        shape: PeriodShape,
        cut: AssembleCut,
        omslag: OmslagMode,
        entity: BusinessEntity = .vof,
        calendar: Calendar = periodCalendar()
    ) throws -> NativeCompileOutput {
        let prepared = try PeriodAssembler.prepareValidatedPeriod(
            windows: windows,
            result: result,
            calendar: calendar
        )

        let bundle = try PeriodAssembler.buildValidatedCurrentBundle(
            prepared: prepared,
            anchor: anchor,
            result: result,
            cut: cut,
            omslag: omslag,
            entity: entity,
            shape: shape,
            calendar: calendar
        )

        return NativeCompileOutput(
            result: result,
            chart: prepared.chart,
            bundle: bundle
        )
    }
}
