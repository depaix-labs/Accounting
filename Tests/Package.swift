// swift-tools-version: 6.2
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "AccountingTests",
    platforms: [
        .macOS(.v13)
    ],
    products: [

        // test
        .executable(name: "t_accounting_syntax", targets: ["AccountingSyntaxTests"]),
        .executable(
            name: "t_accounting",
            targets: ["AccountingTestFlows"]
        ),
        .executable(
            name: "t_accounting_full",
            targets: ["AccountingTestFlowsFull"]
        ),
    ],
    dependencies: [
        .package(url: "https://github.com/leviouwendijk/plate.git", branch: "master"),
        .package(url: "https://github.com/leviouwendijk/Primitives.git", branch: "master"),
        .package(url: "https://github.com/leviouwendijk/Methods.git", branch: "master"),
        .package(url: "https://github.com/leviouwendijk/HTML.git", branch: "master"),
        .package(url: "https://github.com/leviouwendijk/CSS.git", branch: "master"),
        .package(url: "https://github.com/leviouwendijk/Writers.git", branch: "master"),
        .package(url: "https://github.com/leviouwendijk/Terminal.git", branch: "master"),
        .package(url: "https://github.com/leviouwendijk/Arguments.git", branch: "master"),
        .package(url: "https://github.com/leviouwendijk/IO.git", branch: "master"),
        .package(url: "https://github.com/leviouwendijk/Readers.git", branch: "master"),
        .package(url: "https://github.com/leviouwendijk/Path.git", branch: "master"),
        .package(url: "https://github.com/leviouwendijk/Workspace.git", branch: "master"),
        .package(url: "https://github.com/leviouwendijk/TestFlows.git", branch: "master"),
        .package(url: "https://github.com/leviouwendijk/Syntax.git", branch: "master"),
        .package(url: "https://github.com/leviouwendijk/Testing.git", branch: "master"),
        .package(path: ".."),
    ],
    targets: [
        .target(
            name: "AccountingV2Fixtures",
            dependencies: [.product(name: "AccountingV2", package: "Accounting")]
        ),

        .executableTarget(
            name: "AccountingSyntaxTests",
            dependencies: [
                .product(name: "AccountingSyntax", package: "Accounting"),
                .product(name: "AccountingCompiler", package: "Accounting"),
                .product(name: "Syntax", package: "Syntax"),
                .product(name: "SyntaxStyling", package: "Syntax"),
                .product(name: "Testing", package: "Testing"),
            ]
        ),
        .executableTarget(
            name: "AccountingTestFlows",
            dependencies: [
                .product(name: "Accounting", package: "Accounting"),
                .product(name: "AccountingV2", package: "Accounting"),
                "AccountingV2Fixtures",
                .product(name: "AccountingParsers", package: "Accounting"),
                .product(name: "AccountingCompiler", package: "Accounting"),
                .product(name: "plate", package: "plate"),
                .product(name: "Primitives", package: "Primitives"),
                .product(name: "Methods", package: "Methods"),
                .product(name: "HTML", package: "HTML"),
                .product(name: "CSS", package: "CSS"),
                .product(name: "Writers", package: "Writers"),
                .product(name: "Terminal", package: "Terminal"),
                .product(name: "Arguments", package: "Arguments"),
                .product(name: "TestFlows", package: "TestFlows"),
                .product(name: "Readers", package: "Readers"),
                .product(name: "IO", package: "IO"),
                .product(name: "Path", package: "Path"),
                .product(name: "Workspace", package: "Workspace"),
            ]
        ),

        .executableTarget(
            name: "AccountingTestFlowsFull",
            dependencies: [
                .product(name: "Accounting", package: "Accounting"),
                .product(name: "AccountingParsers", package: "Accounting"),
                .product(name: "AccountingCompiler", package: "Accounting"),
                .product(name: "plate", package: "plate"),
                .product(name: "Primitives", package: "Primitives"),
                .product(name: "Methods", package: "Methods"),
                .product(name: "HTML", package: "HTML"),
                .product(name: "CSS", package: "CSS"),
                .product(name: "Writers", package: "Writers"),
                .product(name: "Terminal", package: "Terminal"),
                .product(name: "Arguments", package: "Arguments"),
                .product(name: "TestFlows", package: "TestFlows"),
                .product(name: "Readers", package: "Readers"),
                .product(name: "IO", package: "IO"),
                .product(name: "Path", package: "Path"),
                .product(name: "Workspace", package: "Workspace"),
            ]
        ),
    ]
)

for target in package.targets {
    switch target.type {
    case .regular, .executable, .test, .macro:
        var settings = target.swiftSettings ?? []

        settings.append(
            .treatAllWarnings(as: .error)
        )

        settings.append(
            .unsafeFlags(
                [
                    "-continue-building-after-errors"
                ]
            )
        )

        target.swiftSettings = settings

    case .plugin, .system, .binary:
        break

    @unknown default:
        break
    }
}
