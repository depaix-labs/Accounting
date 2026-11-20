import Accounting
import Foundation

extension RGSAssembler {
    /// Shared compatibility seam for the original trial-row route and the
    /// provenance-preserving resolved-posting route.
    ///
    /// Inputs are direct source seeds, never ancestor-inclusive totals.
    /// Derived presentation and auto-close overlays remain kernel concerns.
    static func assembleSeeded(
        chart: CompiledChart,
        index: RGSIndex,
        maps: RGSAssemblerResult,
        cut: AssembleCut,
        omslag: OmslagMode,
        businessEntity: BusinessEntity,
        autoClose: Bool,
        seed: [Int: Decimal],
        seedAE: [AccEntKey: Decimal]
    ) throws -> StatementBundle {
        let targets = AutoCloseTargets(for: businessEntity)
        let resolved = try targets.resolve(in: index, validateWith: maps)

        try assertSeedSumsToZero(seed)

        if !autoClose {
            return try assembleNoAutoClose(
                chart: chart,
                index: index,
                maps: maps,
                cut: cut,
                omslag: omslag,
                businessEntity: businessEntity,
                seed: seed,
                seedAE: seedAE
            )
        }

        return try assembleWithAutoClose(
            chart: chart,
            index: index,
            maps: maps,
            cut: cut,
            omslag: omslag,
            businessEntity: businessEntity,
            seed: seed,
            seedAE: seedAE,
            autoCloseTargets: (
                niId: resolved.ni.id,
                niCode: resolved.ni.code,
                eqId: resolved.equity.id,
                eqCode: resolved.equity.code
            )
        )
    }
}
