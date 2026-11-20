import Foundation

public enum AccountPostingError: Error, Equatable, Sendable {
    case unknownAccount(AccountKey)
    case nonPostableAccount(AccountKey)
}

/// A posting target constructed only after chart-level eligibility validation.
/// Generic provider identity prevents mixing different provider types.
public struct PostingAccount<Provider: AccountChartProvider>: Hashable, Sendable {
    public let key: AccountKey

    fileprivate init(key: AccountKey) {
        self.key = key
    }
}

/// A signed contribution retaining its original source information.
/// Positive and negative amounts are preserved without normalization.
public struct AccountPosting<Provider: AccountChartProvider, Origin: Sendable>: Sendable {
    public let account: PostingAccount<Provider>
    public let amount: Decimal
    public let origin: Origin

    public init(
        account: PostingAccount<Provider>,
        amount: Decimal,
        origin: Origin
    ) {
        self.account = account
        self.amount = amount
        self.origin = origin
    }
}

/// Derived totals and contribution relationships.
/// Original postings remain authoritative and inspectable.
public struct AccountRollupResult<Provider: AccountChartProvider, Origin: Sendable>: Sendable {
    public let postings: [AccountPosting<Provider, Origin>]
    public let totalsByAccount: [AccountKey: Decimal]
    public let postingOffsetsByAccount: [AccountKey: [Int]]

    fileprivate init(
        postings: [AccountPosting<Provider, Origin>],
        totalsByAccount: [AccountKey: Decimal],
        postingOffsetsByAccount: [AccountKey: [Int]]
    ) {
        self.postings = postings
        self.totalsByAccount = totalsByAccount
        self.postingOffsetsByAccount = postingOffsetsByAccount
    }

    /// Returns original contributions, including their source payloads,
    /// in input order. Ancestors reference the same original postings.
    public func postings(for account: AccountKey) -> [AccountPosting<Provider, Origin>] {
        (postingOffsetsByAccount[account] ?? []).map { postings[$0] }
    }
}

public extension CompiledAccountChart {
    /// Resolves a posting-eligible account through the validated chart.
    /// Nonpostable headings and unknown identities cannot construct one.
    func postingAccount(for key: AccountKey) throws -> PostingAccount<Provider> {
        guard let node = node(for: key) else {
            throw AccountPostingError.unknownAccount(key)
        }
        guard provider.isPostable(node) else {
            throw AccountPostingError.nonPostableAccount(key)
        }
        return PostingAccount(key: key)
    }

    /// Aggregates each signed contribution into its account and every ancestor.
    /// The source contributions are retained, not replaced by a totals map.
    /// Accounts are revalidated against this chart because a posting account
    /// may have been constructed by another chart of the same provider type.
    func rollup<Origin: Sendable>(
        _ postings: [AccountPosting<Provider, Origin>]
    ) throws -> AccountRollupResult<Provider, Origin> {
        var totals: [AccountKey: Decimal] = [:]
        var offsets: [AccountKey: [Int]] = [:]

        for (offset, posting) in postings.enumerated() {
            let key = posting.account.key
            _ = try postingAccount(for: key)

            var current: AccountKey? = key
            while let account = current {
                totals[account, default: 0] += posting.amount
                offsets[account, default: []].append(offset)
                current = parent(of: account)
            }
        }

        return AccountRollupResult(
            postings: postings,
            totalsByAccount: totals,
            postingOffsetsByAccount: offsets
        )
    }
}
