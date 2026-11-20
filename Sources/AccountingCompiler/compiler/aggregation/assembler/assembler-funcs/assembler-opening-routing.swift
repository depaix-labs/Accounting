import Accounting
import Foundation

/// Shared RGS opening-account destination policy.
/// Source movements are not mutated; this resolves only their derived
/// opening-balance presentation destinations.
struct RGSOpeningRouter {
    let kindById: [Int: StatementKind]
    let parentById: [Int: Int]
    let codeById: [Int: String]
    let labelById: [Int: String]
    let levelById: [Int: UInt8]
    let begChildrenByL4: [Int: [Int]]
    let equityAnchorId: Int?
    let equityOpeningId: Int?
    let exceptionAnchorIds: [Int]

    init(
        chart: CompiledChart,
        index: RGSIndex,
        maps: RGSAssemblerResult,
        routing: PeriodOpeningRouting
    ) {
        let codeById = Dictionary(uniqueKeysWithValues: chart.nodes.map {
            ($0.id, $0.codes.code)
        })
        let labelById = Dictionary(uniqueKeysWithValues: chart.nodes.map {
            ($0.id, $0.labels.short.lowercased())
        })
        let levelById = Dictionary(uniqueKeysWithValues: chart.nodes.map {
            ($0.id, $0.level)
        })

        var begChildrenByL4: [Int: [Int]] = [:]
        for node in chart.nodes {
            guard let parent = maps.parentById[node.id],
                  levelById[parent] == 4 else {
                continue
            }

            if node.codes.code.hasSuffix("Beg") ||
               node.labels.short.lowercased().contains("beginbalans") {
                begChildrenByL4[parent, default: []].append(node.id)
            }
        }

        self.kindById = maps.kindById
        self.parentById = maps.parentById
        self.codeById = codeById
        self.labelById = labelById
        self.levelById = levelById
        self.begChildrenByL4 = begChildrenByL4
        self.equityAnchorId = index.byIdentifier[routing.equityAnchorCode]
        self.equityOpeningId = routing.equityOpeningCode.flatMap {
            index.byIdentifier[$0]
        }
        self.exceptionAnchorIds = routing.exceptionKeepLeafAnchors.compactMap {
            index.byIdentifier[$0]
        }
    }

    var equityTarget: Int? {
        equityOpeningId ?? equityAnchorId
    }

    func isDescendant(_ id: Int, of ancestor: Int) -> Bool {
        var current: Int? = id
        while let candidate = current {
            if candidate == ancestor { return true }
            current = parentById[candidate]
        }
        return false
    }

    func l4Parent(of id: Int) -> Int? {
        var current: Int? = id
        while let candidate = current {
            if levelById[candidate] == 4 { return candidate }
            current = parentById[candidate]
        }
        return nil
    }

    func destination(for id: Int) -> Int {
        let code = codeById[id] ?? ""
        let label = labelById[id] ?? ""

        // Existing opening leaves remain their own destinations.
        if code.hasSuffix("Beg") || label.contains("beginbalans") {
            return id
        }

        // Configured exceptions, notably liquid assets, remain at the leaf.
        if exceptionAnchorIds.contains(where: {
            isDescendant(id, of: $0)
        }) {
            return id
        }

        // Route level-five balances to an opening child of their L4 parent.
        if levelById[id] == 5,
           let parent = l4Parent(of: id),
           let candidates = begChildrenByL4[parent],
           !candidates.isEmpty {
            if candidates.count == 1 {
                return candidates[0]
            }

            let hintSource = label + " " + code
            let numericParts = hintSource.split(whereSeparator: {
                !"0123456789".contains($0)
            })
            if let hint = numericParts.last.map(String.init),
               let chosen = candidates.first(where: {
                   (labelById[$0] ?? "").contains(hint) ||
                   (codeById[$0] ?? "").contains(hint)
               }) {
                return chosen
            }

            // Ambiguous opening children must not be chosen arbitrarily.
            return id
        }

        if let equityAnchorId,
           isDescendant(id, of: equityAnchorId) {
            return equityOpeningId ?? equityAnchorId
        }

        return id
    }
}

public extension RGSAssembler {
    /// Build opening presentation from validated direct account seeds.
    /// Historical income is injected into the configured equity opening,
    /// independently of the original source postings.
    static func openingBegSeed(
        fromSourceSeeds seeds: [Int: Decimal],
        chart: CompiledChart,
        index: RGSIndex,
        maps: RGSAssemblerResult,
        routing: PeriodOpeningRouting
    ) -> [Int: Decimal] {
        let router = RGSOpeningRouter(
            chart: chart,
            index: index,
            maps: maps,
            routing: routing
        )

        var result: [Int: Decimal] = [:]
        var historicalNI: Decimal = 0

        for (id, amount) in seeds where amount != 0 {
            switch router.kindById[id] {
            case .balance:
                result[router.destination(for: id), default: 0] += amount
            case .income:
                historicalNI += amount
            case .cash, .equity, nil:
                continue
            }
        }

        if let target = router.equityTarget, historicalNI != 0 {
            result[target, default: 0] += historicalNI
        }

        return result
    }

    /// Entity-aware opening presentation from validated direct AE seeds.
    /// Historical BS movements retain their source entity. Only historical
    /// income injection is allocated using ownership slices.
    static func openingBegSeedAE(
        fromSourceSeeds seeds: [AccEntKey: Decimal],
        chart: CompiledChart,
        index: RGSIndex,
        maps: RGSAssemblerResult,
        routing: PeriodOpeningRouting,
        profitShareCode: String?,
        ownershipSlices: [OwnershipSlice] = []
    ) -> [AccEntKey: Decimal] {
        let router = RGSOpeningRouter(
            chart: chart,
            index: index,
            maps: maps,
            routing: routing
        )

        var result: [AccEntKey: Decimal] = [:]
        var historicalNI: Decimal = 0

        for (key, amount) in seeds where amount != 0 {
            switch router.kindById[key.accountId] {
            case .balance:
                let target = router.destination(for: key.accountId)
                result[AccEntKey(target, key.entityId), default: 0] += amount
            case .income:
                historicalNI += amount
            case .cash, .equity, nil:
                continue
            }
        }

        if let equityTarget = router.equityTarget, historicalNI != 0 {
            if ownershipSlices.isEmpty {
                result[AccEntKey(equityTarget, nil), default: 0] += historicalNI
            } else {
                let target = profitShareCode.flatMap {
                    index.byIdentifier[$0]
                } ?? equityTarget

                for slice in ownershipSlices where slice.percent != 0 {
                    result[AccEntKey(target, slice.entityId), default: 0] += historicalNI * slice.percent
                }
            }
        }

        return result
    }
}
