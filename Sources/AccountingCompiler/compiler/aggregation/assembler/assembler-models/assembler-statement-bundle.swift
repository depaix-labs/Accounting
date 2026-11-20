import Accounting
import Foundation

public struct StatementBundle: Sendable, PresentableOutput {
    public let balance: [StatementLine]
    public let income: [StatementLine]
    public let totalsById: [Int: Decimal]
    public let entity: EntityBreakdown?
    public let analytics: BundleAnalytics?
    public let autoCloseAudit: AutoCloseAudit?

    public init(
        balance: [StatementLine],
        income: [StatementLine],
        totalsById: [Int: Decimal],
        entity: EntityBreakdown? = nil,
        analytics: BundleAnalytics? = nil,
        autoCloseAudit: AutoCloseAudit? = nil
    ) {
        self.balance = balance
        self.income = income
        self.totalsById = totalsById
        self.entity = entity
        self.analytics = analytics
        self.autoCloseAudit = autoCloseAudit
    }
}

extension StatementBundle {
    public func withAnalytics(
        _ analytics: BundleAnalytics?
    ) -> StatementBundle {
        .init(
            balance: balance,
            income: income,
            totalsById: totalsById,
            entity: entity,
            analytics: analytics,
            autoCloseAudit: autoCloseAudit
        )
    }

    public func withAutoCloseAudit(
        _ audit: AutoCloseAudit?
    ) -> StatementBundle {
        .init(
            balance: balance,
            income: income,
            totalsById: totalsById,
            entity: entity,
            analytics: analytics,
            autoCloseAudit: audit
        )
    }
}
