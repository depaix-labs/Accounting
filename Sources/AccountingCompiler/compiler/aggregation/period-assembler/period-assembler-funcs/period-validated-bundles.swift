import Accounting
import Foundation

public enum PeriodValidatedAssemblyError: Error, Equatable, Sendable {
    case missingPreviousSourceSelection
}

extension PeriodAssembler {
    struct PreparedValidatedPeriod: Sendable {
        let chart: CompiledChart
        let windows: PeriodWindows
        let sources: RGSPeriodResolvedSeedProjection
    }

    /// Build one authoritative posting index and derive every reporting view
    /// from the original resolved-entry collection.
    static func prepareValidatedPeriod(
        shape: PeriodShape,
        anchor: Date,
        result: EntryCompileDriver.Result,
        calendar: Calendar
    ) throws -> PreparedValidatedPeriod {
        let windows = resolveWindows(
            shape: shape,
            anchor: anchor,
            calendar: calendar
        )
        return try prepareValidatedPeriod(
            windows: windows,
            result: result,
            calendar: calendar
        )
    }

    /// Preserve authoritative caller-supplied windows rather than
    /// reconstructing them from a shape and anchor.
    static func prepareValidatedPeriod(
        windows: PeriodWindows,
        result: EntryCompileDriver.Result,
        calendar: Calendar
    ) throws -> PreparedValidatedPeriod {
        let chart = try buildChart(from: result)
        let selection = PeriodEntrySelection(
            sourceEntries: result.resolved,
            windows: windows,
            calendar: calendar
        )

        let entityIDs = result.entities.idIndex
        let postingIndex = try RGSPeriodPostingIndex(
            chart: chart,
            entries: result.resolved,
            entityId: { entityIDs[$0] }
        )
        let sources = try postingIndex.project(selection)

        return PreparedValidatedPeriod(
            chart: chart,
            windows: windows,
            sources: sources
        )
    }

    /// Current-period presentation from validated source movements.
    static func buildValidatedCurrentBundle(
        prepared: PreparedValidatedPeriod,
        anchor: Date,
        result: EntryCompileDriver.Result,
        cut: AssembleCut,
        omslag: OmslagMode,
        entity: BusinessEntity,
        shape: PeriodShape,
        calendar: Calendar
    ) throws -> StatementBundle {
        let ownership = result.entities.ownershipSlices(
            asOf: prepared.windows.window.to ?? anchor
        )

        let bundle = try assembleSplitResolvedSeeds(
            chart: prepared.chart,
            incomeWindow: prepared.sources.window,
            balanceWindow: prepared.sources.window,
            overlayForNI: prepared.sources.window,
            preWindowForOpening: prepared.sources.historical,
            cut: cut,
            omslag: omslag,
            entity: entity,
            ownershipSlices: ownership
        )

        return attachFinancialAverages(
            bundle,
            shape: shape,
            range: prepared.windows.window,
            calendar: calendar
        )
    }

    /// Previous-period presentation uses its own historical opening and
    /// ownership cutoff, but references the same original source postings.
    static func buildValidatedPreviousBundle(
        prepared: PreparedValidatedPeriod,
        anchor: Date,
        result: EntryCompileDriver.Result,
        cut: AssembleCut,
        omslag: OmslagMode,
        entity: BusinessEntity,
        shape: PeriodShape,
        calendar: Calendar
    ) throws -> PeriodAssembleResultPeriod? {
        guard let previousWindow = prepared.windows.previous else {
            return nil
        }

        guard let previous = prepared.sources.previous,
              let historical = prepared.sources.previousHistorical else {
            throw PeriodValidatedAssemblyError.missingPreviousSourceSelection
        }

        let ownership = result.entities.ownershipSlices(
            asOf: previousWindow.to ?? anchor
        )

        let bundle = try assembleSplitResolvedSeeds(
            chart: prepared.chart,
            incomeWindow: previous,
            balanceWindow: previous,
            overlayForNI: previous,
            preWindowForOpening: historical,
            cut: cut,
            omslag: omslag,
            entity: entity,
            ownershipSlices: ownership
        )

        return PeriodAssembleResultPeriod(
            range: previousWindow,
            bundle: attachFinancialAverages(
                bundle,
                shape: shape,
                range: previousWindow,
                calendar: calendar
            )
        )
    }
}
