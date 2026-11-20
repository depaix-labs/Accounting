import Foundation

public enum AccountRef: Hashable, Codable, Sendable {
    case identifier(String)    // RGS identifier, e.g. "BLimBanRba"
    case code(String)          // posting-code lookup; numeric legacy syntax retained
    case path([String])        // legacy segmented syntax; no local chart path resolution yet
}

public extension AccountRef {
    var debugString: String { "\(self)" }
}
