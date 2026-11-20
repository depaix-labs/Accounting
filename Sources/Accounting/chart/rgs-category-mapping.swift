import Foundation

public enum RGSCategoryMappingError: Error, Equatable, Sendable {
    case unknownFamily(String)
    case ambiguousParent(String)
    case incompatibleStatementSide(code: String, category: AccountCategory)
}

/// Semantic classifications attached to RGS account families.
/// Native nodes and their hierarchy remain authoritative and unchanged.
public struct RGSCategoryMapping: Sendable {
    public let families: [String: AccountCategory]
    private let categoriesByCode: [String: AccountCategory]

    public init(
        chart: CompiledChart,
        families: [String: AccountCategory]
    ) throws {
        let nodesByCode = Dictionary(uniqueKeysWithValues:
            chart.nodes.map { ($0.codes.code, $0) }
        )
        let nodesById = Dictionary(uniqueKeysWithValues:
            chart.nodes.map { ($0.id, $0) }
        )
        let hierarchy = RGSIdentifierHierarchy.build(from: chart.nodes)

        for problem in hierarchy.problems {
            if case .multipleParents = problem.kind {
                throw RGSCategoryMappingError.ambiguousParent(problem.childCode)
            }
        }

        for (code, category) in families {
            guard let node = nodesByCode[code] else {
                throw RGSCategoryMappingError.unknownFamily(code)
            }

            let expectedSide: RGSNodeSide = switch category {
            case .assets, .liabilities, .equity, .dividends:
                .balance
            case .revenue, .expenses:
                .profitLoss
            }

            guard node.side == expectedSide else {
                throw RGSCategoryMappingError.incompatibleStatementSide(
                    code: code,
                    category: category
                )
            }
        }

        var derived: [String: AccountCategory] = [:]
        derived.reserveCapacity(chart.nodes.count)

        for node in chart.nodes {
            var cursor: Int? = node.id
            while let id = cursor, let ancestor = nodesById[id] {
                if let category = families[ancestor.codes.code] {
                    derived[node.codes.code] = category
                    break
                }
                cursor = hierarchy.parentById[id] ?? nil
            }
        }

        self.families = families
        self.categoriesByCode = derived
    }

    public func category(for code: String) -> AccountCategory? {
        categoriesByCode[code]
    }

    public func category(of node: RGSNode) -> AccountCategory? {
        category(for: node.codes.code)
    }
}
