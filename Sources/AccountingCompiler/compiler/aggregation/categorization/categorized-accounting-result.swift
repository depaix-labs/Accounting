import Accounting
import Foundation

public enum CategorizedAccountingError: Error, Equatable, Sendable {
    case unknownAccountID(Int)
    case unclassifiedSourceAccount(String)
    case unclassifiedBalanceFamily(String)
    case invalidBalanceCategory(code: String, category: AccountCategory)
    case sourceIdentityMismatch(Decimal)
    case closingIdentityMismatch(Decimal)
}

public extension RGSCategoryMapping {
    /// Explicit RGS/VOF category assignments, independent of accounting
    /// direction and statement presentation. Additional active RGS families
    /// must be mapped deliberately rather than inferred from signs.
    static func standard(
        chart: CompiledChart,
        equityCode: String = "BEiv"
    ) throws -> RGSCategoryMapping {
        let available = Set(chart.nodes.map { $0.codes.code })
        let declared: [String: AccountCategory] = [
            // Balance-sheet families
            "BIva": .assets,
            "BMva": .assets,
            "BVas": .assets,
            "BFva": .assets,
            "BVrd": .assets,
            "BPro": .assets,
            "BVor": .assets,
            "BEff": .assets,
            "BLim": .assets,
            "BVrz": .liabilities,
            "BLas": .liabilities,
            "BSch": .liabilities,

            // Profit-and-loss families with unambiguous economic meaning
            "WOmz": .revenue,
            "WKpr": .expenses,
            "WBed": .expenses,
            "WAfs": .expenses,

            // VOF drawings: DEALER's distribution category is a semantic
            // equivalent, not a claim of corporate dividend treatment.
            "BEivKapPro": .dividends
        ]

        var families = declared.filter { available.contains($0.key) }
        // Preserve the equity-anchor parameter without inferring the
        // category from the RGS account's debit/credit direction.
        families[equityCode] = .equity

        return try RGSCategoryMapping(chart: chart, families: families)
    }
}

/// Two non-overlapping economic projections of one accounting compilation.
/// Source totals reflect direct journal postings. Closing totals reflect
/// the balance sheet after opening-balance routing and closing adjustments.
public struct CategorizedAccountingResult: Sendable {
    public let sourceRawByCategory: [AccountCategory: Decimal]
    public let closingRawByCategory: [AccountCategory: Decimal]

    /// Both projections are taken from one resolved compilation.
    /// Source postings exclude closing overlays; statements include them.
    public init(
        output: NativeResolvedCompileOutput,
        mapping: RGSCategoryMapping
    ) throws {
        let chart = output.chart
        let compiled = try RGSChartProvider(
            categoryMapping: mapping
        ).compile(chart)
        var source: [AccountCategory: Decimal] = [:]
        // Check every original posting account before aggregation. A debit
        // and credit on the same unmapped account must still fail validation.
        for posting in output.movements.batch.postings {
            let key = posting.account.key
            _ = try compiled.postingAccount(for: key)
            guard let category = compiled.category(of: key) else {
                throw CategorizedAccountingError.unclassifiedSourceAccount(
                    key.code
                )
            }
            source[category, default: 0] += posting.amount
        }

        // L2 balance families partition the complete balance-sheet hierarchy.
        // Never sum all ancestor-inclusive bundle.totalsById entries.
        var closing: [AccountCategory: Decimal] = [:]
        for node in chart.nodes where node.level == 2 && node.side == .balance {
            let key = try AccountKey(node.codes.code)
            guard let category = compiled.category(of: key) else {
                throw CategorizedAccountingError.unclassifiedBalanceFamily(
                    node.codes.code
                )
            }
            switch category {
            case .assets, .liabilities, .equity:
                closing[category, default: 0] += output.bundle.totalsById[node.id] ?? 0
            case .dividends, .expenses, .revenue:
                throw CategorizedAccountingError.invalidBalanceCategory(
                    code: node.codes.code,
                    category: category
                )
            }
        }

        self.sourceRawByCategory = source
        self.closingRawByCategory = closing
    }

    private static func normalized(
        _ category: AccountCategory,
        raw: Decimal
    ) -> Decimal {
        switch category {
        case .assets, .expenses, .dividends:
            return raw
        case .liabilities, .equity, .revenue:
            return -raw
        }
    }

    public func source(_ category: AccountCategory) -> Decimal {
        Self.normalized(
            category,
            raw: sourceRawByCategory[category] ?? 0
        )
    }

    public func closing(_ category: AccountCategory) -> Decimal {
        Self.normalized(
            category,
            raw: closingRawByCategory[category] ?? 0
        )
    }

    /// A + Expenses + Distributions = L + Equity + Revenue.
    /// This tests conservation and coverage, not semantic correctness alone.
    public var sourceIdentityDelta: Decimal {
        source(.assets) + source(.expenses) + source(.dividends)
            - source(.liabilities) - source(.equity) - source(.revenue)
    }

    /// The assembled equity position already includes closing adjustments.
    public var closingIdentityDelta: Decimal {
        closing(.assets) - closing(.liabilities) - closing(.equity)
    }

    public func assertIdentities() throws {
        guard sourceIdentityDelta == 0 else {
            throw CategorizedAccountingError.sourceIdentityMismatch(
                sourceIdentityDelta
            )
        }
        guard closingIdentityDelta == 0 else {
            throw CategorizedAccountingError.closingIdentityMismatch(
                closingIdentityDelta
            )
        }
    }
}
