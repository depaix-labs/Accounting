import Foundation

public extension RGSNode {
    /// Explicit, non-mutating diagnostic derived from native XLSX metadata.
    /// A mismatch is informational and does not invalidate an RGS node.
    var sortingLevelConsistencyReport: String? {
        guard let xlsx else { return nil }

        return xlsx.sorting.softConsistencyReport(
            expectedLevel: level,
            code: codes.code
        )
    }
}
