import Foundation

public enum CompiledChartIndexError: Error, CustomStringConvertible, Sendable {
    case duplicateIdentifier(String)
    case duplicateNodeID(id: Int, first: String, duplicate: String)
    case duplicateSortKey(String)
    case duplicateReference(String)
    case missingParentKey(String, for: String) // (parentKey, childCode)

    public var description: String {
        switch self {
        case .duplicateIdentifier(let k): return "Duplicate identifier: \(k)"
        case let .duplicateNodeID(id, first, duplicate): return "Duplicate RGS node ID \(id): \(first) and \(duplicate)"
        case .duplicateSortKey(let k):    return "Duplicate sort key: \(k)"
        case .duplicateReference(let k):  return "Duplicate reference: \(k)"
        case .missingParentKey(let p, let c): return "Missing parent key '\(p)' referenced by node '\(c)'"
        }
    }
}
