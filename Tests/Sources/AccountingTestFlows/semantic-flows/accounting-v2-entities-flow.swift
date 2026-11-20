import AccountingV2
import TestFlows

extension AccountingTestFlowsSuite {
    static var accountingV2EntitiesFlow: TestFlow {
        TestFlow("accounting-v2-entities", tags: ["accounting", "v2", "entities"]) {
            Step("validates full entity identity and alias variants") {
                try Expect.throwsError("empty alias") {
                    _ = try Entity.Alias(name: " ")
                }
                try Expect.throwsError("reserved separator") {
                    _ = try Entity.Alias(name: "bad.name")
                }
                try Expect.throwsError("empty variant") {
                    _ = try Entity.Alias(name: "camera", variants: [""])
                }

                let alias = try Entity.Alias(name: "camera", variants: ["body"])
                let reference = try Entity.Reference(
                    class: "asset", family: "equipment", alias: alias
                )
                try Expect.equal(reference.identifier, "asset.equipment.camera#body", "full identity")
                try Expect.equal(alias.identifier, "camera#body", "variant preserved")

                try Expect.throwsError("invalid class") {
                    _ = try Entity.Reference(class: " ", family: "equipment", alias: alias)
                }
                try Expect.throwsError("invalid family") {
                    _ = try Entity.Reference(class: "asset", family: "eq#x", alias: alias)
                }
            }

            Step("validates immutable entity definitions") {
                let alias = try Entity.Alias(name: "camera")
                let reference = try Entity.Reference(
                    class: "asset", family: "equipment", alias: alias
                )

                try Expect.throwsError("blank display name") {
                    _ = try Entity(.init(reference: reference, displayName: " "))
                }
                try Expect.throwsError("blank details") {
                    _ = try Entity(.init(reference: reference, details: " "))
                }

                let entity = try Entity(.init(
                    reference: reference,
                    displayName: "Camera",
                    details: "Acquired in 2026",
                    metadata: ["serial": "abc"]
                ))
                try Expect.equal(entity.reference, reference, "identity retained")
                try Expect.equal(entity.metadata["serial"], "abc", "metadata retained")
            }

            Step("indexes exact full identities and preserves source order") {
                let rootAlias = try Entity.Alias(name: "camera")
                let variantAlias = try Entity.Alias(name: "camera", variants: ["body"])
                let rootRef = try Entity.Reference(
                    class: "asset", family: "equipment", alias: rootAlias
                )
                let variantRef = try Entity.Reference(
                    class: "asset", family: "equipment", alias: variantAlias
                )
                let root = try Entity(.init(reference: rootRef))
                let variant = try Entity(.init(reference: variantRef))
                let entities = try Entities([variant, root])

                try Expect.equal(entities.count, 2, "full identity count")
                try Expect.equal(
                    entities.all.map(\.reference.identifier),
                    [variantRef.identifier, rootRef.identifier],
                    "input order"
                )
                try Expect.equal(
                    try entities.resolve(rootRef).reference,
                    rootRef,
                    "exact lookup"
                )
                try Expect.equal(
                    entities.entity(variantRef)?.reference,
                    variantRef,
                    "distinct variant lookup"
                )

                try Expect.throwsError("duplicate identity") {
                    _ = try Entities([root, root])
                }

                let missing = try Entity.Reference(
                    class: "asset",
                    family: "equipment",
                    alias: try Entity.Alias(name: "missing")
                )
                try Expect.throwsError("unknown identity does not fallback") {
                    _ = try entities.resolve(missing)
                }
            }
        }
    }
}
