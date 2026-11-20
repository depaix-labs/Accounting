import Foundation

public enum AutoCloseOverlayDisposition: Sendable, Equatable {
    case notNeeded
    case applied
    case suppressedByManualPostings
}

/// Inspectable decision about a derived net-income overlay.
/// This audit records the decision; it does not alter journal postings.
public struct AutoCloseAudit: Sendable {
    public let ni: Decimal
    public let niNode: (code: String, id: Int)
    public let equityNode: (code: String, id: Int)
    public let adjustedForManual: Decimal
    public let suppressed: Bool
    public let manualAtNetIncome: Decimal
    public let manualAtEquity: Decimal

    public var disposition: AutoCloseOverlayDisposition {
        if ni == 0 {
            return .notNeeded
        }
        return suppressed ? .suppressedByManualPostings : .applied
    }

    public init(
        ni: Decimal,
        niNode: (code: String, id: Int),
        equityNode: (code: String, id: Int),
        adjustedForManual: Decimal,
        suppressed: Bool,
        manualAtNetIncome: Decimal = 0,
        manualAtEquity: Decimal = 0
    ) {
        self.ni = ni
        self.niNode = niNode
        self.equityNode = equityNode
        self.adjustedForManual = adjustedForManual
        self.suppressed = suppressed
        self.manualAtNetIncome = manualAtNetIncome
        self.manualAtEquity = manualAtEquity
    }

    /// Evaluate the existing manual-posting suppression rule without IO.
    /// A zero overlay does not constitute a suppressed closing operation.
    public static func evaluate(
        ni: Decimal,
        niNode: (code: String, id: Int),
        equityNode: (code: String, id: Int),
        manualAtNetIncome: Decimal,
        manualAtEquity: Decimal
    ) -> AutoCloseAudit {
        let suppressed = ni != 0 && (
            manualAtNetIncome != 0 || manualAtEquity != 0
        )

        return AutoCloseAudit(
            ni: ni,
            niNode: niNode,
            equityNode: equityNode,
            adjustedForManual: suppressed ? 0 : ni,
            suppressed: suppressed,
            manualAtNetIncome: manualAtNetIncome,
            manualAtEquity: manualAtEquity
        )
    }
}
