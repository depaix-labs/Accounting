import Accounting
import Foundation

public enum NativeOutputBuilder {
    /// Explicit validated compilation route. Unlike trial-balance aggregation,
    /// this retains source posting provenance and rejects invalid targets.
    /// No fallback to the legacy route is performed on validation failure.
    public static func buildResolvedCompileOutput(
        result: EntryCompileDriver.Result,
        cut: AssembleCut,
        omslag: OmslagMode,
        entity: BusinessEntity = .vof,
        autoClose: Bool = true
    ) throws -> NativeResolvedCompileOutput {
        let chart = try PeriodAssembler.buildChart(from: result)

        let assembly = try RGSAssembler.assembleResolved(
            chart: chart,
            entries: result.resolved,
            cut: cut,
            omslag: omslag,
            for: entity,
            autoClose: autoClose,
            entityId: { result.entities.idIndex[$0] }
        )

        return NativeResolvedCompileOutput(
            result: result,
            chart: chart,
            assembly: assembly
        )
    }

    /// Compatibility surface retaining the original native output shape.
    /// All compilation is performed through validated source postings.
    /// Independent trial-balance assembly remains available directly
    /// through RGSAssembler for regression comparisons.
    public static func buildCompileOutput(
        result: EntryCompileDriver.Result,
        cut: AssembleCut,
        omslag: OmslagMode,
        entity: BusinessEntity = .vof,
        autoClose: Bool = true
    ) throws -> NativeCompileOutput {
        try buildResolvedCompileOutput(
            result: result,
            cut: cut,
            omslag: omslag,
            entity: entity,
            autoClose: autoClose
        ).output
    }

    public static func buildPeriodOutput(
        result: EntryCompileDriver.Result,
        shape: PeriodShape,
        anchor: Date,
        cut: AssembleCut,
        omslag: OmslagMode,
        entity: BusinessEntity = .vof,
        calendar: Calendar = periodCalendar()
    ) throws -> NativePeriodCompileOutput {
        let prepared = try PeriodAssembler.prepareValidatedPeriod(
            shape: shape,
            anchor: anchor,
            result: result,
            calendar: calendar
        )

        let assembled = try PeriodAssembler.assemblePrepared(
            prepared: prepared,
            anchor: anchor,
            result: result,
            cut: cut,
            omslag: omslag,
            entity: entity,
            shape: shape,
            calendar: calendar
        )

        return .init(
            result: result,
            chart: prepared.chart,
            shape: shape,
            assembled: assembled
        )
    }
}
