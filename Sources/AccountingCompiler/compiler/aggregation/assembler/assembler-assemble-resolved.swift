import Accounting
import Foundation

public enum RGSResolvedAssemblyError: Error, Sendable {
    case hierarchyMismatch
}

/// Final statements together with the original validated source movements.
/// Presentation overlays are reflected in statements, not fabricated as
/// source journal postings.
public struct RGSResolvedAssembly: Sendable {
    public let statements: StatementBundle
    public let movements: RGSResolvedRollup

    public init(
        statements: StatementBundle,
        movements: RGSResolvedRollup
    ) {
        self.statements = statements
        self.movements = movements
    }
}

public extension RGSAssembler {
    /// Assemble directly from resolved journal entries while retaining
    /// original entries, lines, local identities, and source provenance.
    ///
    /// The optional entity resolver controls numeric entity bucketing.
    /// Its default matches the existing trialBalance(entries) route, which
    /// places all contributions in the nil entity bucket.
    ///
    /// Unlike the legacy trial-row route, this rejects unknown and
    /// nonpostable source targets, as well as ambiguous chart hierarchy.
    static func assembleResolved(
        chart: CompiledChart,
        entries: [ResolvedEntry],
        cut: AssembleCut,
        omslag: OmslagMode,
        for businessEntity: BusinessEntity = .vof,
        autoClose: Bool = true,
        entityId: (EntityKey) -> Int? = { _ in nil }
    ) throws -> RGSResolvedAssembly {
        let ch = try chart.ensuringIndex(enrichNodes: true, strict: false)
        guard let index = ch.index else {
            throw RGSAssemblerError.missingIndex
        }

        let maps = try makeMaps(from: ch)
        let movements = try rollupResolvedEntries(
            entries,
            in: ch,
            entityId: entityId
        )

        // The validated provider's hierarchy must not diverge from the
        // native numeric topology consumed by the existing kernel.
        guard movements.parentById == maps.parentById else {
            throw RGSResolvedAssemblyError.hierarchyMismatch
        }

        let statements = try assembleSeeded(
            chart: ch,
            index: index,
            maps: maps,
            cut: cut,
            omslag: omslag,
            businessEntity: businessEntity,
            autoClose: autoClose,
            seed: movements.sourceSeedById,
            seedAE: movements.sourceSeedAEById
        )

        return RGSResolvedAssembly(
            statements: statements,
            movements: movements
        )
    }
}
