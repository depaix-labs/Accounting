import Accounting
import Foundation

/// Native compiler output assembled from validated resolved postings.
/// Original source entries remain authoritative; statement overlays are
/// derived presentation values rather than fabricated journal movements.
public struct NativeResolvedCompileOutput: Sendable {
    public let result: EntryCompileDriver.Result
    public let chart: CompiledChart
    public let assembly: RGSResolvedAssembly

    public init(
        result: EntryCompileDriver.Result,
        chart: CompiledChart,
        assembly: RGSResolvedAssembly
    ) {
        self.result = result
        self.chart = chart
        self.assembly = assembly
    }

    public var bundle: StatementBundle {
        assembly.statements
    }

    public var movements: RGSResolvedRollup {
        assembly.movements
    }

    /// Compatibility projection for existing native renderers and consumers.
    /// The validated assembly remains available on this result.
    public var output: NativeCompileOutput {
        NativeCompileOutput(
            result: result,
            chart: chart,
            bundle: bundle
        )
    }
}
