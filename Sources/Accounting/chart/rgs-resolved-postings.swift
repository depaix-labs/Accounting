import Foundation

/// Identifies a source line inside the unchanged resolved entry collection.
public struct ResolvedPostingSource: Hashable, Sendable {
    public let entryIndex: Int
    public let lineIndex: Int

    fileprivate init(entryIndex: Int, lineIndex: Int) {
        self.entryIndex = entryIndex
        self.lineIndex = lineIndex
    }
}

/// Retains the complete resolved entries, not only their aggregated amounts.
/// Posting origins refer to stable offsets in this retained collection.
public struct ResolvedPostingBatch: Sendable {
    public let entries: [ResolvedEntry]
    public let postings: [AccountPosting<RGSChartProvider, ResolvedPostingSource>]

    fileprivate init(
        entries: [ResolvedEntry],
        postings: [AccountPosting<RGSChartProvider, ResolvedPostingSource>]
    ) {
        self.entries = entries
        self.postings = postings
    }

    public func entry(for source: ResolvedPostingSource) -> ResolvedEntry? {
        guard entries.indices.contains(source.entryIndex) else { return nil }
        return entries[source.entryIndex]
    }

    public func line(for source: ResolvedPostingSource) -> ResolvedLine? {
        guard let entry = entry(for: source),
              entry.lines.indices.contains(source.lineIndex) else {
            return nil
        }
        return entry.lines[source.lineIndex]
    }
}

public extension CompiledAccountChart where Provider == RGSChartProvider {
    /// Adapt resolved RGS classifications to signed chart postings.
    /// Debit-positive and credit-negative match TrialBalanceRow.net.
    /// No unknown or nonpostable account is silently omitted.
    /// The original entries, including local account identity, entity, date,
    /// transaction references, adjustments, and metadata, remain accessible.
    func postings(from entries: [ResolvedEntry]) throws -> ResolvedPostingBatch {
        var postings: [AccountPosting<RGSChartProvider, ResolvedPostingSource>] = []
        postings.reserveCapacity(entries.reduce(0) { $0 + $1.lines.count })

        for (entryIndex, entry) in entries.enumerated() {
            for (lineIndex, line) in entry.lines.enumerated() {
                let account = try postingAccount(for: line.account)
                let amount = line.direction == .debit ? line.amount : -line.amount
                postings.append(
                    AccountPosting(
                        account: account,
                        amount: amount,
                        origin: ResolvedPostingSource(
                            entryIndex: entryIndex,
                            lineIndex: lineIndex
                        )
                    )
                )
            }
        }

        return ResolvedPostingBatch(entries: entries, postings: postings)
    }
}
