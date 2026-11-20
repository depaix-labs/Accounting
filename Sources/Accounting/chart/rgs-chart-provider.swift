import Foundation

public enum RGSChartProviderError: Error, Equatable, Sendable {
    case duplicateNodeID(Int)
    case ambiguousParent(String)
    case unknownNodeID(Int)
}

/// Interprets a native CompiledChart without replacing its RGS nodes,
/// XLSX/XBRL source bundles, presentation relationships, or identifiers.
public struct RGSChartProvider: AccountChartProvider {
    public let categoryMapping: RGSCategoryMapping?

    public init(categoryMapping: RGSCategoryMapping? = nil) {
        self.categoryMapping = categoryMapping
    }

    public func nodes(in source: CompiledChart) -> [RGSNode] {
        source.nodes
    }

    public func key(of node: RGSNode) throws -> AccountKey {
        try AccountKey(node.codes.code)
    }

    /// Derives the posting/aggregation hierarchy from canonical RGS codes.
    /// XLSX sorting and XBRL presentation links remain native metadata,
    /// not alternative parents in this hierarchy.
    public func hierarchy(in source: CompiledChart) -> RGSIdentifierHierarchy.Result {
        RGSIdentifierHierarchy.build(from: source.nodes)
    }

    public func parents(in source: CompiledChart) throws -> [AccountKey: AccountKey] {
        let result = hierarchy(in: source)
        var keysByID: [Int: AccountKey] = [:]
        keysByID.reserveCapacity(source.nodes.count)

        for node in source.nodes {
            let key = try self.key(of: node)
            if keysByID.updateValue(key, forKey: node.id) != nil {
                throw RGSChartProviderError.duplicateNodeID(node.id)
            }
        }

        // Missing parents are retained as hierarchy diagnostics. An ambiguous
        // parent must not silently become an authoritative compiled edge.
        for problem in result.problems {
            if case .multipleParents = problem.kind {
                throw RGSChartProviderError.ambiguousParent(problem.childCode)
            }
        }

        var parents: [AccountKey: AccountKey] = [:]
        parents.reserveCapacity(result.parentById.count)

        for (childID, parentID) in result.parentById {
            guard let parentID else { continue }
            guard let child = keysByID[childID] else {
                throw RGSChartProviderError.unknownNodeID(childID)
            }
            guard let parent = keysByID[parentID] else {
                throw RGSChartProviderError.unknownNodeID(parentID)
            }
            parents[child] = parent
        }

        return parents
    }

    /// Category membership is supplied independently of the native chart.
    /// No mapping means no inferred economic category.
    public func category(of node: RGSNode) -> AccountCategory? {
        categoryMapping?.category(of: node)
    }

    public func isPostable(_ node: RGSNode) -> Bool {
        node.postable
    }
}
