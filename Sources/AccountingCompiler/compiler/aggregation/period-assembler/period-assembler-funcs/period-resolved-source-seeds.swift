import Accounting
import Foundation

public enum PeriodSourceSeedProjectionError: Error, Equatable, Sendable {
    case sourceMismatch
}

/// Direct source contributions for one period membership view.
/// All offsets refer to the original collection, never a renumbered slice.
public struct RGSPeriodResolvedSeedView: Sendable {
    public let entryOffsets: [Int]
    public let postingOffsets: [Int]
    public let sourceSeedById: [Int: Decimal]
    public let sourceSeedAEById: [AccEntKey: Decimal]

    init(
        entryOffsets: [Int],
        postingOffsets: [Int],
        sourceSeedById: [Int: Decimal],
        sourceSeedAEById: [AccEntKey: Decimal]
    ) {
        self.entryOffsets = entryOffsets
        self.postingOffsets = postingOffsets
        self.sourceSeedById = sourceSeedById
        self.sourceSeedAEById = sourceSeedAEById
    }
}

/// Period-specific seed views derived from one unchanged source collection.
/// Overlapping views reference the same original postings.
public struct RGSPeriodResolvedSeedProjection: Sendable {
    public let selection: PeriodEntrySelection
    public let batch: ResolvedPostingBatch

    public let historical: RGSPeriodResolvedSeedView
    public let window: RGSPeriodResolvedSeedView
    public let ytd: RGSPeriodResolvedSeedView
    public let previous: RGSPeriodResolvedSeedView?
    public let previousHistorical: RGSPeriodResolvedSeedView?

    init(
        selection: PeriodEntrySelection,
        batch: ResolvedPostingBatch,
        historical: RGSPeriodResolvedSeedView,
        window: RGSPeriodResolvedSeedView,
        ytd: RGSPeriodResolvedSeedView,
        previous: RGSPeriodResolvedSeedView?,
        previousHistorical: RGSPeriodResolvedSeedView?
    ) {
        self.selection = selection
        self.batch = batch
        self.historical = historical
        self.window = window
        self.ytd = ytd
        self.previous = previous
        self.previousHistorical = previousHistorical
    }

    public func postings(
        in view: RGSPeriodResolvedSeedView
    ) -> [AccountPosting<RGSChartProvider, ResolvedPostingSource>] {
        view.postingOffsets.map { batch.postings[$0] }
    }
}

/// Validates the RGS chart and source postings once, then supports multiple
/// period selections without rebuilding the chart or renumbering origins.
///
/// Numeric IDs and entity IDs are derived projections. The retained resolved
/// source entries remain authoritative, including local-account identities.
public struct RGSPeriodPostingIndex: Sendable {
    public let batch: ResolvedPostingBatch

    private let accountIdByPosting: [Int]
    private let entityIdByPosting: [Int?]
    private let postingOffsetsByEntry: [[Int]]

    public init(
        chart: CompiledChart,
        entries: [ResolvedEntry],
        entityId: (EntityKey) -> Int? = { _ in nil }
    ) throws {
        let compiled = try RGSChartProvider().compile(chart)
        let batch = try compiled.postings(from: entries)

        var accountIDs: [Int] = []
        var entityIDs: [Int?] = []
        var offsets = Array(repeating: [Int](), count: entries.count)

        accountIDs.reserveCapacity(batch.postings.count)
        entityIDs.reserveCapacity(batch.postings.count)

        for (postingOffset, posting) in batch.postings.enumerated() {
            guard let node = compiled.node(for: posting.account.key) else {
                throw AccountPostingError.unknownAccount(posting.account.key)
            }

            let source = posting.origin
            let line = entries[source.entryIndex].lines[source.lineIndex]

            accountIDs.append(node.id)
            entityIDs.append(entityId(line.entity))
            offsets[source.entryIndex].append(postingOffset)
        }

        self.batch = batch
        self.accountIdByPosting = accountIDs
        self.entityIdByPosting = entityIDs
        self.postingOffsetsByEntry = offsets
    }

    /// Build reporting views from the exact source collection validated above.
    /// A different entry collection cannot silently reuse the posting offsets.
    public func project(
        _ selection: PeriodEntrySelection
    ) throws -> RGSPeriodResolvedSeedProjection {
        guard selection.sourceEntries == batch.entries else {
            throw PeriodSourceSeedProjectionError.sourceMismatch
        }

        func view(_ entryOffsets: [Int]) -> RGSPeriodResolvedSeedView {
            var postingOffsets: [Int] = []
            var seedById: [Int: Decimal] = [:]
            var seedAEById: [AccEntKey: Decimal] = [:]

            for entryOffset in entryOffsets {
                for postingOffset in postingOffsetsByEntry[entryOffset] {
                    let posting = batch.postings[postingOffset]
                    let accountId = accountIdByPosting[postingOffset]
                    let entityId = entityIdByPosting[postingOffset]

                    postingOffsets.append(postingOffset)
                    seedById[accountId, default: 0] += posting.amount
                    seedAEById[
                        AccEntKey(accountId, entityId),
                        default: 0
                    ] += posting.amount
                }
            }

            return RGSPeriodResolvedSeedView(
                entryOffsets: entryOffsets,
                postingOffsets: postingOffsets,
                sourceSeedById: seedById,
                sourceSeedAEById: seedAEById
            )
        }

        return RGSPeriodResolvedSeedProjection(
            selection: selection,
            batch: batch,
            historical: view(selection.historicalOffsets),
            window: view(selection.windowOffsets),
            ytd: view(selection.ytdOffsets),
            previous: selection.previousOffsets.map(view),
            previousHistorical: selection.previousHistoricalOffsets.map(view)
        )
    }
}
