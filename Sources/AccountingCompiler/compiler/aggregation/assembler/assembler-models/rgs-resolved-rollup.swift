import Accounting
import Foundation

/// A provenance-preserving aggregation of resolved source entries.
/// Numeric RGS indexes are derived projections, not authoritative postings.
public struct RGSResolvedRollup: Sendable {
    public let batch: ResolvedPostingBatch
    public let rollup: AccountRollupResult<RGSChartProvider, ResolvedPostingSource>
    /// Direct source postings only, before ancestor aggregation or overlays.
    public let sourceSeedById: [Int: Decimal]
    /// Direct source postings grouped by native RGS ID and resolved entity.
    public let sourceSeedAEById: [AccEntKey: Decimal]
    /// Ancestor-inclusive source totals; never feed these back as leaf seeds.
    public let totalsById: [Int: Decimal]
    public let parentById: [Int: Int]
    public let postingOffsetsById: [Int: [Int]]

    init(
        batch: ResolvedPostingBatch,
        rollup: AccountRollupResult<RGSChartProvider, ResolvedPostingSource>,
        sourceSeedById: [Int: Decimal],
        sourceSeedAEById: [AccEntKey: Decimal],
        totalsById: [Int: Decimal],
        parentById: [Int: Int],
        postingOffsetsById: [Int: [Int]]
    ) {
        self.batch = batch
        self.rollup = rollup
        self.sourceSeedById = sourceSeedById
        self.sourceSeedAEById = sourceSeedAEById
        self.totalsById = totalsById
        self.parentById = parentById
        self.postingOffsetsById = postingOffsetsById
    }

    /// Returns source postings contributing to a native RGS node, including
    /// contributions inherited through the validated account hierarchy.
    public func postings(for nodeId: Int) -> [AccountPosting<RGSChartProvider, ResolvedPostingSource>] {
        (postingOffsetsById[nodeId] ?? []).map { batch.postings[$0] }
    }

    /// Retrieve the original resolved line without flattening its local
    /// account identity, entity, adjustment, or source location.
    public func line(for source: ResolvedPostingSource) -> ResolvedLine? {
        batch.line(for: source)
    }

    public func entry(for source: ResolvedPostingSource) -> ResolvedEntry? {
        batch.entry(for: source)
    }
}
