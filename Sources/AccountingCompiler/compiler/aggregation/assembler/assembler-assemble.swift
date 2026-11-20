import Accounting

extension RGSAssembler {
    public static func assemble(
        chart: CompiledChart,
        trialRows: [TrialBalanceRow],
        cut: AssembleCut,
        omslag: OmslagMode,
        for businessEntity: BusinessEntity = .vof,
        autoClose: Bool = true
    ) throws -> StatementBundle {
        let ch = try chart.ensuringIndex(enrichNodes: true, strict: false)
        guard let index = ch.index else {
            throw RGSAssemblerError.missingIndex
        }

        let maps = try makeMaps(from: ch)
        let seed = seedLeafs(from: trialRows, using: index)
        let seedAE = seedLeafsAE(from: trialRows, using: index)

        return try assembleSeeded(
            chart: ch,
            index: index,
            maps: maps,
            cut: cut,
            omslag: omslag,
            businessEntity: businessEntity,
            autoClose: autoClose,
            seed: seed,
            seedAE: seedAE
        )
    }
}
