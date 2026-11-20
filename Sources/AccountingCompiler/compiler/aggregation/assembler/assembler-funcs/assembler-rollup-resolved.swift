import Accounting
import Foundation

public extension RGSAssembler {
    /// Aggregate resolved journal entries through the validated native chart.
    ///
    /// The result retains each source entry and posting. Its numeric-ID maps
    /// are derived only for interoperability with existing RGS compiler APIs.
    ///
    /// This operation represents source movements. Derived opening balances,
    /// net-income overlays, and presentation adjustments must be applied at
    /// their respective accounting stages, not fabricated as source postings.
    static func rollupResolvedEntries(
        _ entries: [ResolvedEntry],
        in source: CompiledChart,
        entityId: (EntityKey) -> Int? = { _ in nil }
    ) throws -> RGSResolvedRollup {
        let chart = try RGSChartProvider().compile(source)
        let batch = try chart.postings(from: entries)
        let rollup = try chart.rollup(batch.postings)

        // Construct direct seeds from original contributions, not rolled
        // ancestor totals. The source batch retains all original line data.
        var sourceSeedById: [Int: Decimal] = [:]
        var sourceSeedAEById: [AccEntKey: Decimal] = [:]

        for posting in batch.postings {
            guard let node = chart.node(for: posting.account.key) else {
                throw AccountPostingError.unknownAccount(posting.account.key)
            }

            let origin = posting.origin
            let line = batch.entries[origin.entryIndex].lines[origin.lineIndex]

            sourceSeedById[node.id, default: 0] += posting.amount
            sourceSeedAEById[
                AccEntKey(node.id, entityId(line.entity)),
                default: 0
            ] += posting.amount
        }

        var totalsById: [Int: Decimal] = [:]
        var parentById: [Int: Int] = [:]
        var postingOffsetsById: [Int: [Int]] = [:]

        totalsById.reserveCapacity(rollup.totalsByAccount.count)
        parentById.reserveCapacity(source.nodes.count)
        postingOffsetsById.reserveCapacity(rollup.postingOffsetsByAccount.count)

        for node in source.nodes {
            let key = try chart.provider.key(of: node)

            if let amount = rollup.totalsByAccount[key] {
                totalsById[node.id] = amount
            }

            if let offsets = rollup.postingOffsetsByAccount[key] {
                postingOffsetsById[node.id] = offsets
            }

            if let parentKey = chart.parent(of: key),
               let parentNode = chart.node(for: parentKey) {
                parentById[node.id] = parentNode.id
            }
        }

        return RGSResolvedRollup(
            batch: batch,
            rollup: rollup,
            sourceSeedById: sourceSeedById,
            sourceSeedAEById: sourceSeedAEById,
            totalsById: totalsById,
            parentById: parentById,
            postingOffsetsById: postingOffsetsById
        )
    }
}
