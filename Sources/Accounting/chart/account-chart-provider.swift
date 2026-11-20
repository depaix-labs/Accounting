import Foundation

/// Interprets a native chart without replacing its source nodes or metadata.
public protocol AccountChartProvider: Sendable {
    associatedtype Source: Sendable
    associatedtype Node: Sendable

    func nodes(in source: Source) -> [Node]
    func key(of node: Node) throws -> AccountKey
    func parents(in source: Source) throws -> [AccountKey: AccountKey]
    func category(of node: Node) -> AccountCategory?
    func isPostable(_ node: Node) -> Bool
}

public extension AccountChartProvider {
    func compile(_ source: Source) throws -> CompiledAccountChart<Self> {
        try CompiledAccountChart(provider: self, source: source)
    }
}
