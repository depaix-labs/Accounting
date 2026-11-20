import Accounting
import Foundation

extension RGSAssembler {
    @inline(__always)
    public static func assembleWithAutoClose(
        chart: CompiledChart,
        index: RGSIndex,
        maps: RGSAssemblerResult,
        cut: AssembleCut,
        omslag: OmslagMode,
        businessEntity: BusinessEntity,
        seed: [Int: Decimal],
        seedAE: [AccEntKey: Decimal],
        autoCloseTargets: (
            niId: Int,
            niCode: String,
            eqId: Int,
            eqCode: String
        )
    ) throws -> StatementBundle {
        let ni = seed.reduce(into: Decimal(0)) { acc, kv in
            if maps.kindById[kv.key] == .income {
                acc += kv.value
            }
        }

        let manualAtNi = seed[autoCloseTargets.niId] ?? 0
        let manualAtEquity = seed[autoCloseTargets.eqId] ?? 0
        let hasManual = (manualAtNi != 0 || manualAtEquity != 0)

        let audit = AutoCloseAudit.evaluate(
            ni: ni,
            niNode: (
                code: autoCloseTargets.niCode,
                id: autoCloseTargets.niId
            ),
            equityNode: (
                code: autoCloseTargets.eqCode,
                id: autoCloseTargets.eqId
            ),
            manualAtNetIncome: manualAtNi,
            manualAtEquity: manualAtEquity
        )

        let rolled = AssemblerKernel.rollup(
            maps: maps,
            cut: cut,
            plan: .init(
                incomeSeed: seed,
                balanceSeed: seed,
                balanceSeedAE: seedAE,
                netIncomePresentationId: autoCloseTargets.niId,
                netIncomePresentationCode: autoCloseTargets.niCode,
                equityPresentationId: autoCloseTargets.eqId,
                equityPresentationCode: autoCloseTargets.eqCode,
                netIncomeOverlay: ni,
                suppressOverlay: hasManual
            )
        )

        let bundle = try AssemblerKernel.makeBundle(
            chart: chart,
            index: index,
            maps: maps,
            cut: cut,
            omslag: omslag,
            businessEntity: businessEntity,
            rolled: rolled
        )

        return bundle.withAutoCloseAudit(audit)
    }
}
