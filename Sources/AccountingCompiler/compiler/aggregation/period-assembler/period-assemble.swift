import Accounting
import Foundation

public enum PeriodAssembler {
    /// Assemble a reporting period from validated, provenance-preserving
    /// resolved postings. No trial-balance conversion occurs on this route.
    public static func assemble(
        shape: PeriodShape,
        anchor: Date,
        result: EntryCompileDriver.Result,
        cut: AssembleCut = .init(
            target: .L3,
            includeCodes: [],
            includeIntermediates: true,
            omitZerosBeyondLevel1: true
        ),
        omslag: OmslagMode = .apply,
        entity: BusinessEntity = .vof,
        calendar: Calendar = periodCalendar()
    ) throws -> PeriodAssembleResult {
        let prepared = try prepareValidatedPeriod(
            shape: shape,
            anchor: anchor,
            result: result,
            calendar: calendar
        )

        return try assemblePrepared(
            prepared: prepared,
            anchor: anchor,
            result: result,
            cut: cut,
            omslag: omslag,
            entity: entity,
            shape: shape,
            calendar: calendar
        )
    }

    /// Assemble from a previously validated chart and source projection.
    /// Reuse this when the caller also needs the compiled chart.
    static func assemblePrepared(
        prepared: PreparedValidatedPeriod,
        anchor: Date,
        result: EntryCompileDriver.Result,
        cut: AssembleCut,
        omslag: OmslagMode,
        entity: BusinessEntity,
        shape: PeriodShape,
        calendar: Calendar
    ) throws -> PeriodAssembleResult {
        let currentBundle = try buildValidatedCurrentBundle(
            prepared: prepared,
            anchor: anchor,
            result: result,
            cut: cut,
            omslag: omslag,
            entity: entity,
            shape: shape,
            calendar: calendar
        )
        let previous = try buildValidatedPreviousBundle(
            prepared: prepared,
            anchor: anchor,
            result: result,
            cut: cut,
            omslag: omslag,
            entity: entity,
            shape: shape,
            calendar: calendar
        )

        return PeriodAssembleResult(
            current: PeriodAssembleResultPeriod(
                range: prepared.windows.window,
                bundle: currentBundle
            ),
            previous: previous,
            sources: prepared.sources
        )
    }

    /// Current and previous presentations may assemble concurrently while
    /// sharing one immutable validated source projection and source offsets.
    public static func assemble_concurrent(
        shape: PeriodShape,
        anchor: Date,
        result: EntryCompileDriver.Result,
        cut: AssembleCut = .init(
            target: .L3,
            includeCodes: [],
            includeIntermediates: true,
            omitZerosBeyondLevel1: true
        ),
        omslag: OmslagMode = .apply,
        entity: BusinessEntity = .vof,
        calendar: Calendar = periodCalendar()
    ) async throws -> PeriodAssembleResult {
        let prepared = try prepareValidatedPeriod(
            shape: shape,
            anchor: anchor,
            result: result,
            calendar: calendar
        )

        async let currentBundleTask: StatementBundle = buildValidatedCurrentBundle(
            prepared: prepared,
            anchor: anchor,
            result: result,
            cut: cut,
            omslag: omslag,
            entity: entity,
            shape: shape,
            calendar: calendar
        )

        async let previousPeriodTask: PeriodAssembleResultPeriod? = buildValidatedPreviousBundle(
            prepared: prepared,
            anchor: anchor,
            result: result,
            cut: cut,
            omslag: omslag,
            entity: entity,
            shape: shape,
            calendar: calendar
        )

        let currentBundle = try await currentBundleTask
        let previous = try await previousPeriodTask

        return PeriodAssembleResult(
            current: PeriodAssembleResultPeriod(
                range: prepared.windows.window,
                bundle: currentBundle
            ),
            previous: previous,
            sources: prepared.sources
        )
    }
}
