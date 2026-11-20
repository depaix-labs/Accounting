import Foundation

public enum AccountChartCompilationError: Error, Equatable, Sendable {
    case duplicateKey(AccountKey)
    case unknownChild(AccountKey)
    case unknownParent(child: AccountKey, parent: AccountKey)
    case hierarchyCycle(AccountKey)
}

/// Validated native chart. Source is authoritative; indexes and hierarchy
/// are derived, retained for lookup, and not separately serialized.
public struct CompiledAccountChart<Provider: AccountChartProvider>: Sendable {
    public let provider: Provider
    public let source: Provider.Source

    /// Derived node snapshot, sharing storage with native array sources when possible.
    private let indexedNodes: [Provider.Node]
    private let offsetsByKey: [AccountKey: Int]
    private let parentByKey: [AccountKey: AccountKey]

    public init(provider: Provider, source: Provider.Source) throws {
        let nodes = provider.nodes(in: source)
        var offsetsByKey: [AccountKey: Int] = [:]
        offsetsByKey.reserveCapacity(nodes.count)

        for (offset, node) in nodes.enumerated() {
            let key = try provider.key(of: node)
            if offsetsByKey.updateValue(offset, forKey: key) != nil {
                throw AccountChartCompilationError.duplicateKey(key)
            }
        }

        let parentByKey = try provider.parents(in: source)
        for (child, parent) in parentByKey {
            guard offsetsByKey[child] != nil else {
                throw AccountChartCompilationError.unknownChild(child)
            }
            guard offsetsByKey[parent] != nil else {
                throw AccountChartCompilationError.unknownParent(child: child, parent: parent)
            }
        }

        for key in offsetsByKey.keys {
            var visited: Set<AccountKey> = []
            var current = key
            while let parent = parentByKey[current] {
                guard visited.insert(current).inserted else {
                    throw AccountChartCompilationError.hierarchyCycle(current)
                }
                current = parent
            }
        }

        self.provider = provider
        self.source = source
        self.indexedNodes = nodes
        self.offsetsByKey = offsetsByKey
        self.parentByKey = parentByKey
    }

    public var count: Int { offsetsByKey.count }

    public func node(for key: AccountKey) -> Provider.Node? {
        guard let offset = offsetsByKey[key] else { return nil }
        return indexedNodes[offset]
    }

    public func parent(of key: AccountKey) -> AccountKey? {
        parentByKey[key]
    }

    public func category(of key: AccountKey) -> AccountCategory? {
        node(for: key).flatMap { provider.category(of: $0) }
    }

    public func isPostable(_ key: AccountKey) -> Bool? {
        node(for: key).map { provider.isPostable($0) }
    }
}
