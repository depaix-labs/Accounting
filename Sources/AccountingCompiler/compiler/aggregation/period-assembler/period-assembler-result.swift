import Accounting
import Foundation

public struct PeriodAssembleResultPeriod: Sendable {
    public let range: PeriodWindow
    public let bundle: StatementBundle

    public init(range: PeriodWindow, bundle: StatementBundle) {
        self.range = range
        self.bundle = bundle
    }
}

public struct PeriodAssembleResult: Sendable {
    public let current: PeriodAssembleResultPeriod
    public let previous: PeriodAssembleResultPeriod?

    /// Validated source views for this compilation, retaining the complete
    /// original resolved-entry and posting collections and global offsets.
    /// Nil is reserved for compatibility callers without source provenance.
    public let sources: RGSPeriodResolvedSeedProjection?

    public init(
        current: PeriodAssembleResultPeriod,
        previous: PeriodAssembleResultPeriod?,
        sources: RGSPeriodResolvedSeedProjection? = nil
    ) {
        self.current = current
        self.previous = previous
        self.sources = sources
    }
}
