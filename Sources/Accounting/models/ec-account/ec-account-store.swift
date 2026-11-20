import Foundation
import Position

public struct AccountStore: Codable, Sendable {
    /// Canonical map: posting code -> node
    public let byCode: [String: RGSNode]
    /// Optional map: RGS identifier -> node (requires chart index)
    public let byIdentifier: [String: RGSNode]

    public let hierarchyProblemsById: [Int: RGSIdentifierHierarchy.Problem]

    /// A chart-backed store exposes both posting-code and RGS-identifier lookup.
    /// The chart's index must agree with its authoritative node collection.
    public init(chart: CompiledChart) throws {
        guard let index = chart.index else {
            throw AccountStoreError.compiledChartIndexEmpty
        }
        try self.init(nodes: chart.nodes, chartIndex: index)
    }

    /// Nodes-only construction deliberately leaves identifier lookup disabled.
    public init(nodes: [RGSNode]) throws {
        try self.init(nodes: nodes, chartIndex: nil)
    }

    private init(nodes: [RGSNode], chartIndex: RGSIndex?) throws {
        var codeMap: [String: RGSNode] = [:]
        for node in nodes {
            if codeMap.updateValue(node, forKey: node.codes.code) != nil {
                throw AccountStoreError.duplicateCode(node.codes.code, at: nil)
            }
        }

        // Validate numeric identity even for nodes-only stores. In chart-backed
        // stores, reject indexes that disagree with their authoritative nodes.
        let (canonicalIndex, _) = try RGSIndex.build(from: nodes)
        if let chartIndex, chartIndex != canonicalIndex {
            throw AccountStoreError.inconsistentChartIndex
        }

        var identifierMap: [String: RGSNode] = [:]
        if chartIndex != nil {
            // Numeric IDs are unique after RGSIndex.build, so this is safe.
            let nodesByID = Dictionary(uniqueKeysWithValues: nodes.map { ($0.id, $0) })
            for (identifier, id) in canonicalIndex.byIdentifier {
                guard let node = nodesByID[id] else {
                    throw AccountStoreError.inconsistentChartIndex
                }
                identifierMap[identifier] = node
            }
        }

        self.byCode = codeMap
        self.byIdentifier = identifierMap

        // Hierarchy diagnostics are retained as a separate resolution gate.
        let hierarchy = RGSIdentifierHierarchy.build(from: nodes)
        self.hierarchyProblemsById = Dictionary(
            uniqueKeysWithValues: hierarchy.problems.map { ($0.childId, $0) }
        )
    }

    // @inlinable
    // public func resolve(_ ref: AccountRef, at loc: Position?) throws -> RGSNode {
    //     switch ref {
    //     case .code(let s):
    //         if let node = byCode[s] { return node }
    //         // also allow passing an identifier via .code by accident (be forgiving)
    //         if let node = byIdentifier[s] { return node }
    //         throw AccountStoreError.notFound(code: s, at: loc)

    //     case .identifier(let ident):
    //         if let node = byIdentifier[ident] { return node }
    //         throw AccountStoreError.notFound(code: ident, at: loc)

    //     case .path(let segs):
    //         // numeric first segment → posting code
    //         if let first = segs.first,
    //            first.allSatisfy(\.isNumber),
    //            let node = byCode[first] {
    //             return node
    //         }
    //         // legacy: account 10201
    //         if segs.first == "account",
    //            let code = segs.dropFirst().first,
    //            code.allSatisfy(\.isNumber),
    //            let node = byCode[code] {
    //             return node
    //         }
    //         // single non-numeric path segment? treat as identifier if we can
    //         if segs.count == 1, let node = byIdentifier[segs[0]] {
    //             return node
    //         }
    //         throw AccountStoreError.invalidReference(path: segs, at: loc)
    //     }
    // }

    @inlinable
    public func resolve(_ ref: AccountRef, at loc: Position?) throws -> RGSNode {
        let node: RGSNode
        switch ref {
        case .code(let s):
            if let n = byCode[s] { node = n }
            else { throw AccountStoreError.notFound(code: s, at: loc) }

        case .identifier(let ident):
            if let n = byIdentifier[ident] { node = n }
            else { throw AccountStoreError.notFound(code: ident, at: loc) }

        case .path(let segs):
            if let first = segs.first, first.allSatisfy(\.isNumber), let n = byCode[first] {
                node = n
            } else if segs.first == "account",
                      let code = segs.dropFirst().first,
                      code.allSatisfy(\.isNumber),
                      let n = byCode[code] {
                node = n
            } else if segs.count == 1, let n = byIdentifier[segs[0]] {
                node = n
            } else {
                throw AccountStoreError.invalidReference(path: segs, at: loc)
            }
        }

        // NEW: block nodes with known hierarchy issues
        if let problem = hierarchyProblemsById[node.id] {
            throw AccountStoreError.hierarchyIssue(problem: problem, at: loc)
        }
        return node
    }


    public var all: [RGSNode] { Array(byCode.values) }
    public var count: Int { byCode.count }
}

