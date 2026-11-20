import Foundation

/// A project-local posting-account identity, mapped explicitly to an RGS concept.
/// Local accounts and RGS nodes are separate namespaces: several local accounts
/// may share one RGS target without becoming the same posting account.
public struct LocalAccount: Hashable, Codable, Sendable {
    public let key: AccountKey
    public let rgsIdentifier: String
    public let label: String?

    public init(key: AccountKey, rgsIdentifier: String, label: String? = nil) throws {
        guard !rgsIdentifier.isEmpty, !rgsIdentifier.allSatisfy(\.isWhitespace) else {
            throw LocalAccountError.emptyRGSIdentifier(code: key.code)
        }
        self.key = key
        self.rgsIdentifier = rgsIdentifier
        self.label = label
    }

    private enum CodingKeys: String, CodingKey {
        case key, rgsIdentifier, label
    }

    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        let key = try values.decode(AccountKey.self, forKey: .key)
        let rgsIdentifier = try values.decode(String.self, forKey: .rgsIdentifier)
        let label = try values.decodeIfPresent(String.self, forKey: .label)
        do {
            try self.init(key: key, rgsIdentifier: rgsIdentifier, label: label)
        } catch {
            throw DecodingError.dataCorruptedError(
                forKey: .rgsIdentifier,
                in: values,
                debugDescription: "Invalid local account RGS binding: \(error)"
            )
        }
    }
}

public enum LocalAccountError: Error, CustomStringConvertible, Sendable, Equatable {
    case emptyRGSIdentifier(code: String)
    case duplicateCode(String)
    case unknownRGSIdentifier(code: String, identifier: String)
    case nonPostableRGSIdentifier(code: String, identifier: String)
    case incompatibleChartBinding(code: String, identifier: String)

    public var description: String {
        switch self {
        case .emptyRGSIdentifier(let code):
            return "Local account '\(code)' requires an RGS identifier"
        case .duplicateCode(let code):
            return "Duplicate local account code '\(code)'"
        case .unknownRGSIdentifier(let code, let identifier):
            return "Local account '\(code)' targets unknown RGS identifier '\(identifier)'"
        case .nonPostableRGSIdentifier(let code, let identifier):
            return "Local account '\(code)' targets non-postable RGS identifier '\(identifier)'"
        case .incompatibleChartBinding(let code, let identifier):
            return "Local account '\(code)' binds to an RGS concept inconsistent with the active AccountStore: '\(identifier)'"
        }
    }
}

/// Validates local-account declarations against the authoritative compiled chart.
/// The compiler loader does not install these declarations yet.
/// The entry-resolution pass accepts an explicit catalog without changing RGS reporting keys.
public struct LocalAccountCatalog: Sendable {
    private let byKey: [AccountKey: LocalAccount]
    private let rgsByKey: [AccountKey: RGSNode]

    public init(accounts: [LocalAccount], chart: CompiledChart) throws {
        guard let index = chart.index else {
            throw AccountStoreError.compiledChartIndexEmpty
        }
        let (canonicalIndex, _) = try RGSIndex.build(from: chart.nodes)
        guard index == canonicalIndex else {
            throw AccountStoreError.inconsistentChartIndex
        }

        let nodesByID = Dictionary(uniqueKeysWithValues: chart.nodes.map { ($0.id, $0) })
        var definitions: [AccountKey: LocalAccount] = [:]
        var targets: [AccountKey: RGSNode] = [:]

        for account in accounts {
            guard definitions[account.key] == nil else {
                throw LocalAccountError.duplicateCode(account.key.code)
            }
            guard let id = index.byIdentifier[account.rgsIdentifier],
                  let node = nodesByID[id] else {
                throw LocalAccountError.unknownRGSIdentifier(
                    code: account.key.code, identifier: account.rgsIdentifier
                )
            }
            guard node.postable else {
                throw LocalAccountError.nonPostableRGSIdentifier(
                    code: account.key.code, identifier: account.rgsIdentifier
                )
            }
            definitions[account.key] = account
            targets[account.key] = node
        }

        self.byKey = definitions
        self.rgsByKey = targets
    }

    public var count: Int { byKey.count }
    public func account(for key: AccountKey) -> LocalAccount? { byKey[key] }
    public func rgsNode(for key: AccountKey) -> RGSNode? { rgsByKey[key] }
}
