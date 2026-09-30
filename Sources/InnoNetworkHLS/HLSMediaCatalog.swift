import Foundation

/// Catalog identity is distinct from URL identity, task IDs and key identities.
public struct HLSMediaID: Codable, Hashable, Sendable {
    public let rawValue: UUID
    public init(_ rawValue: UUID = UUID()) { self.rawValue = rawValue }
}

public enum HLSMediaOwnership: String, Codable, Sendable {
    case applicationFile
    case offlinePackage
    case nativeBackgroundAsset
}

public enum HLSMediaAvailability: String, Codable, Sendable { case unknown, available, missing }

/// Metadata only. Opaque references are app-resolved identifiers, not URLs,
/// paths, credentials or key payloads. The catalog never owns the media itself.
public struct HLSMediaRecord: Codable, Equatable, Sendable {
    public let id: HLSMediaID
    public let ownership: HLSMediaOwnership
    public let reference: String
    public let availability: HLSMediaAvailability
    public init(
        id: HLSMediaID, ownership: HLSMediaOwnership, reference: String, availability: HLSMediaAvailability = .unknown
    ) throws {
        guard (1...128).contains(reference.utf8.count),
            reference.utf8.allSatisfy({
                (48...57).contains($0) || (65...90).contains($0) || (97...122).contains($0)
                    || [45, 46, 95].contains($0)
            })
        else { throw HLSMediaCatalogError.invalidReference }
        self.id = id
        self.ownership = ownership
        self.reference = reference
        self.availability = availability
    }
    private enum CodingKeys: String, CodingKey { case id, ownership, reference, availability }
    public init(from decoder: any Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(
            id: values.decode(HLSMediaID.self, forKey: .id),
            ownership: values.decode(HLSMediaOwnership.self, forKey: .ownership),
            reference: values.decode(String.self, forKey: .reference),
            availability: values.decodeIfPresent(HLSMediaAvailability.self, forKey: .availability) ?? .unknown)
    }
}

public enum HLSMediaCatalogError: Error, Equatable, Sendable {
    case invalidLimits
    case invalidReference
    case capacityExceeded
    case snapshotTooLarge
    case corruptSnapshot
    case unsupportedVersion(Int)
    /// Another staged mutation owns the transaction; retry explicitly later.
    case transactionInProgress
}

public struct HLSMediaCatalogConfiguration: Sendable {
    public let maximumEntries: Int
    public let maximumSnapshotBytes: Int
    private init(maximumEntries: Int, maximumSnapshotBytes: Int) {
        self.maximumEntries = maximumEntries
        self.maximumSnapshotBytes = maximumSnapshotBytes
    }
    public static func safeDefaults() -> Self { Self(maximumEntries: 512, maximumSnapshotBytes: 1_048_576) }
    public static func validated(maximumEntries: Int = 512, maximumSnapshotBytes: Int = 1_048_576) throws -> Self {
        guard (1...512).contains(maximumEntries), (1024...1_048_576).contains(maximumSnapshotBytes) else {
            throw HLSMediaCatalogError.invalidLimits
        }
        return Self(maximumEntries: maximumEntries, maximumSnapshotBytes: maximumSnapshotBytes)
    }
}

/// A staged metadata replacement. App implementations must serialize access
/// to the same store and atomically publish on commit. Successful commit wins
/// late cancellation; discard removes staging only, never the existing store.
public protocol HLSMediaCatalogCommit: Sendable {
    func commit() async throws
    func discard() async
}

/// App-owned storage contract. Read must bound allocation by maximumBytes
/// before loading untrusted bytes; the coordinator also checks returned size.
/// Staging must not modify existing metadata or media. No default filesystem,
/// asset deletion, URL resolution or key-store access is implied.
public protocol HLSMediaCatalogPersisting: Sendable {
    func read(maximumBytes: Int) async throws -> Data?
    func stage(_ data: Data) async throws -> any HLSMediaCatalogCommit
}

/// Optional bounded coordinator. Mutations reject reentrant/concurrent writes
/// rather than allowing an awaited older commit to overwrite newer metadata.
public actor HLSMediaCatalog {
    private struct Snapshot: Codable {
        let version: Int
        let entries: [HLSMediaRecord]
    }
    private let configuration: HLSMediaCatalogConfiguration
    private let persistence: (any HLSMediaCatalogPersisting)?
    private var entries: [HLSMediaRecord] = []
    private var isWriting = false

    public init(
        configuration: HLSMediaCatalogConfiguration = .safeDefaults(),
        persistence: (any HLSMediaCatalogPersisting)? = nil
    ) {
        self.configuration = configuration
        self.persistence = persistence
    }
    public func snapshot() -> [HLSMediaRecord] { entries }

    /// Reads v1 or the explicitly defined v0 fixture (availability absent).
    /// Corruption/unknown versions leave current state unchanged. Restore does
    /// not automatically rewrite storage; the next explicit mutation writes v1.
    public func restore() async throws {
        try begin()
        defer { isWriting = false }
        guard let data = try await persistence?.read(maximumBytes: configuration.maximumSnapshotBytes) else { return }
        try Task.checkCancellation()
        guard data.count <= configuration.maximumSnapshotBytes else { throw HLSMediaCatalogError.snapshotTooLarge }
        let snapshot: Snapshot
        do { snapshot = try JSONDecoder().decode(Snapshot.self, from: data) } catch {
            throw HLSMediaCatalogError.corruptSnapshot
        }
        guard [0, 1].contains(snapshot.version) else { throw HLSMediaCatalogError.unsupportedVersion(snapshot.version) }
        try validate(snapshot.entries)
        entries = snapshot.entries
    }

    public func upsert(_ record: HLSMediaRecord) async throws {
        try begin()
        defer { isWriting = false }
        var candidate = entries.filter { $0.id != record.id }
        candidate.append(record)
        try await publish(candidate)
    }

    /// Removes metadata only, never files, native assets or keys.
    public func remove(_ id: HLSMediaID) async throws {
        try begin()
        defer { isWriting = false }
        try await publish(entries.filter { $0.id != id })
    }

    /// App resolves ownership-specific references. Missing media is reported,
    /// not pruned. A failed/cancelled probe publishes no partial reconciliation.
    public func reconcile(using probe: @Sendable (HLSMediaRecord) async throws -> HLSMediaAvailability) async throws {
        try begin()
        defer { isWriting = false }
        var candidate: [HLSMediaRecord] = []
        for record in entries {
            try Task.checkCancellation()
            candidate.append(
                try await HLSMediaRecord(
                    id: record.id, ownership: record.ownership, reference: record.reference, availability: probe(record)
                ))
        }
        try await publish(candidate)
    }

    private func begin() throws {
        try Task.checkCancellation()
        guard !isWriting else { throw HLSMediaCatalogError.transactionInProgress }
        isWriting = true
    }
    private func validate(_ candidate: [HLSMediaRecord]) throws {
        guard candidate.count <= configuration.maximumEntries else { throw HLSMediaCatalogError.capacityExceeded }
        guard Set(candidate.map(\.id)).count == candidate.count else { throw HLSMediaCatalogError.corruptSnapshot }
    }
    private func publish(_ candidate: [HLSMediaRecord]) async throws {
        try validate(candidate)
        let sorted = candidate.sorted { $0.id.rawValue.uuidString < $1.id.rawValue.uuidString }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let data = try encoder.encode(Snapshot(version: 1, entries: sorted))
        guard data.count <= configuration.maximumSnapshotBytes else { throw HLSMediaCatalogError.snapshotTooLarge }
        try Task.checkCancellation()
        if let persistence {
            let staged = try await persistence.stage(data)
            do {
                try Task.checkCancellation()
                try await staged.commit()
            } catch {
                await staged.discard()
                throw error
            }
            // Successful atomic commit wins cancellation arriving afterwards.
        }
        entries = sorted
    }
}
