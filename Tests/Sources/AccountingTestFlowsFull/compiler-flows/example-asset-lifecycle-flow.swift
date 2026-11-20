import Accounting
import AccountingCompiler
import Foundation
import TestFlows

extension AccountingTestFlowsSuite {
    static var exampleAssetLifecycleFlow: TestFlow {
        TestFlow("accounting-example-asset-lifecycle", tags: ["accounting", "example", "assets"]) {
            Step("extended example compiles to independent asset and bank oracles") {
                let packageRoot = URL(fileURLWithPath: #filePath)
                    .deletingLastPathComponent()
                    .deletingLastPathComponent()
                    .deletingLastPathComponent()
                    .deletingLastPathComponent()
                let example = packageRoot.appendingPathComponent("Fixtures/accounting-example", isDirectory: true)
                let scenario = example.appendingPathComponent("scenarios/assets", isDirectory: true)
                let fm = FileManager.default
                let scratch = fm.temporaryDirectory.appendingPathComponent(
                    "accounting-asset-oracle-\(UUID().uuidString)", isDirectory: true
                )
                try fm.createDirectory(at: scratch, withIntermediateDirectories: true)
                defer { try? fm.removeItem(at: scratch) }
                let projectRoot = scratch.appendingPathComponent("project", isDirectory: true)
                try fm.copyItem(at: example, to: projectRoot)
                let project = EntryCompilerProject(root: projectRoot)
                let base = try EntryCompileDriver.compile(
                    project: project, setting: CompileDriveSetting(loc_trace: false)
                )

                let files = [
                    "config/entities/objects/usable/assets.ec",
                    "entries/2026/4/10/assets.ec",
                    "entries/2026/4/11/depreciation.ec",
                    "transactions/2026/4/10/assets.ec"
                ]
                for file in files {
                    let destination = projectRoot.appendingPathComponent(file)
                    try fm.createDirectory(
                        at: destination.deletingLastPathComponent(),
                        withIntermediateDirectories: true
                    )
                    try fm.copyItem(at: scenario.appendingPathComponent(file), to: destination)
                }

                let compiled = try EntryCompileDriver.compile(
                    project: project, setting: CompileDriveSetting(loc_trace: false)
                )
                try Expect.equal(compiled.resolved.count - base.resolved.count, 4, "four-new-entries")
                let ids: Set<Int> = [9960, 9961, 9962, 9963]
                let added = compiled.resolved.filter { $0.id.map(ids.contains) ?? false }
                try Expect.equal(added.count, 4, "scenario-entry-identities")

                func total(_ code: String, _ side: Direction) -> Decimal {
                    added.flatMap(\.lines)
                        .filter { $0.account.code == code && $0.direction == side }
                        .reduce(into: Decimal(0)) { $0 += $1.amount }
                }
                let inputVAT = Decimal(3024) / 10
                let grossBank = Decimal(23424) / 10
                try Expect.equal(total("BMvaMeiAkpIna", .debit), Decimal(2040), "asset-purchases")
                try Expect.equal(total("BSchBepBtwVoo", .debit), inputVAT, "purchase-vat")
                try Expect.equal(total("BLimBanRba", .credit), grossBank, "bank-outflow")
                try Expect.equal(total("WAfsAmvMei", .debit), Decimal(34), "depreciation-expense")
                try Expect.equal(total("BMvaMeiCaeAfs", .credit), Decimal(34), "depreciation-contra")

                let configured = try DepreciationResolutionPass.run(
                    on: compiled.entities, using: compiled.accounts
                )
                try Expect.equal(configured.depreciationMap.count, 3, "three-assets")
                var calendar = Calendar(identifier: .gregorian)
                calendar.timeZone = TimeZone(identifier: "Europe/Amsterdam") ?? .gmt
                guard let december1 = calendar.date(from: DateComponents(year: 2026, month: 12, day: 1)),
                    let anchor = calendar.date(from: DateComponents(year: 2026, month: 11, day: 30)) else {
                    try Expect.true(false, "valid-calendar-dates")
                    return
                }
                let depreciation = try DepreciationAuditRunner.run(
                    entities: compiled.entities,
                    accounts: compiled.accounts,
                    resolvedEntries: compiled.resolved,
                    through: december1.addingTimeInterval(-1),
                    options: .init(granularity: .monthly, tolerance: 0, calendar: calendar)
                )
                func month(_ month: Int) -> [DepreciationAuditItem] {
                    depreciation.items.filter {
                        let parts = calendar.dateComponents([.year, .month], from: $0.periodStart)
                        return parts.year == 2026 && parts.month == month
                    }
                }
                let october = month(10)
                let november = month(11)
                try Expect.equal(october.count, 2, "two-october-assets")
                try Expect.equal(november.count, 3, "three-november-assets")
                try Expect.equal(october.reduce(into: Decimal(0)) { $0 += $1.expected }, 44, "october-expected-depreciation")
                try Expect.equal(october.reduce(into: Decimal(0)) { $0 += $1.actual }, 24, "october-posted-depreciation")
                try Expect.equal(november.reduce(into: Decimal(0)) { $0 += $1.expected }, 54, "november-expected-depreciation")
                try Expect.equal(november.reduce(into: Decimal(0)) { $0 += $1.actual }, 10, "november-posted-depreciation")

                let shape = PeriodShape(kind: .quarter)
                let windows = PeriodSlicer.resolve(shape: shape, anchor: anchor, calendar: calendar)
                let cut = AssembleCut(
                    target: .L3, includeCodes: [], includeIntermediates: true,
                    omitZerosBeyondLevel1: true
                )
                let before = try NativeOutputBuilder.buildWindowOutput(
                    result: base, windows: windows, anchor: anchor, shape: shape,
                    cut: cut, omslag: .apply, entity: .vof, calendar: calendar
                )
                let after = try NativeOutputBuilder.buildWindowOutput(
                    result: compiled, windows: windows, anchor: anchor, shape: shape,
                    cut: cut, omslag: .apply, entity: .vof, calendar: calendar
                )
                guard let bankID = after.chart.index?.byIdentifier["BLimBanRba"] else {
                    try Expect.true(false, "bank-account-in-chart")
                    return
                }
                let delta = (after.bundle.totalsById[bankID] ?? 0)
                    - (before.bundle.totalsById[bankID] ?? 0)
                try Expect.equal(delta, -grossBank, "compiled-bank-delta")
            }
        }
    }
}
