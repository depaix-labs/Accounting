import AccountingV2
import TestFlows

extension AccountingTestFlowsSuite {
    static var accountingV2ChartFlow: TestFlow {
        TestFlow("accounting-v2-chart", tags: ["accounting", "v2", "chart"]) {
            Step("rejects invalid account definitions") {
                try Expect.throwsError("blank account code") {
                    _ = try Account(.init(code: " ", category: .assets, postable: true))
                }
                try Expect.throwsError("blank account label") {
                    _ = try Account(.init(code: "B", label: " ", postable: false))
                }
                try Expect.throwsError("postable accounts require a category") {
                    _ = try Account(.init(code: "BLimBan", postable: true))
                }
            }

            Step("builds a complete tree with source-order children") {
                let root = try Account(.init(code: "B", postable: false))
                let group = try Account(.init(code: "BLim", postable: false))
                let bank = try Account(.init(code: "BLimBan", category: .assets, postable: true))
                let cash = try Account(.init(code: "BLimKas", category: .assets, postable: true))
                let chart = try Chart(.init(
                    accounts: [root, group, bank, cash],
                    roots: [root.reference],
                    parents: [
                        group.reference: root.reference,
                        bank.reference: group.reference,
                        cash.reference: group.reference
                    ],
                    behavior: .init(carryforward: .identity)
                ))
                try Expect.equal(chart.count, 4, "complete chart account count")
                try Expect.equal(chart.hierarchy.roots.count, 1, "one declared root")
                try Expect.equal(chart.hierarchy.roots[0].children[0].value.code, "BLim", "group")
                try Expect.equal(chart.hierarchy.roots[0].children[0].children.map(\.value.code), ["BLimBan", "BLimKas"], "source-order children")
                try Expect.equal(chart.ancestors(of: bank.reference), [group.reference, root.reference], "complete ancestry")
                try Expect.equal(chart.isPostable(root.reference), false, "heading not postable")
                try Expect.equal(chart.isPostable(bank.reference), true, "leaf postable")
                try Expect.equal(chart.account(try Account.Reference("missing"))?.code, nil, "unknown reference")
            }

            Step("rejects duplicate accounts, missing links and cycles") {
                let root = try Account(.init(code: "B", postable: false))
                let a = try Account(.init(code: "A", category: .assets, postable: true))
                let b = try Account(.init(code: "C", category: .assets, postable: true))
                let unknown = try Account.Reference("unknown")

                try Expect.throwsError("duplicate account identity") {
                    _ = try Chart(.init(accounts: [root, root], roots: [root.reference], parents: [:], behavior: .init(carryforward: .identity)))
                }
                try Expect.throwsError("missing parent for unlisted root") {
                    _ = try Chart(.init(accounts: [root, a], roots: [root.reference], parents: [:], behavior: .init(carryforward: .identity)))
                }
                try Expect.throwsError("unknown parent") {
                    _ = try Chart(.init(accounts: [root, a], roots: [root.reference], parents: [a.reference: unknown], behavior: .init(carryforward: .identity)))
                }
                try Expect.throwsError("cycle disconnected from root") {
                    _ = try Chart(.init(
                        accounts: [root, a, b],
                        roots: [root.reference],
                        parents: [a.reference: b.reference, b.reference: a.reference],
                        behavior: .init(carryforward: .identity)
                    ))
                }
                try Expect.throwsError("root cannot have parent") {
                    _ = try Chart(.init(accounts: [root, a], roots: [root.reference], parents: [root.reference: a.reference, a.reference: root.reference], behavior: .init(carryforward: .identity)))
                }
            }
        }
    }
}
