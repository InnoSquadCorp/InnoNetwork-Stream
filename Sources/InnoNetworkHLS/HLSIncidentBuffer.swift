import Foundation

public enum HLSOperationStage: String, Codable, Sendable {
    case starting, planning, transferring, committing, completed, failed, cancelled
}
public enum HLSIncidentError: Error, Equatable, Sendable {
    case invalidCapacity, mismatchedOperation, sequenceExhausted
}

public struct HLSIncident: Codable, Equatable, Sendable {
    public let operationID: UUID
    public let sequence: UInt64
    public let stage: HLSOperationStage
    public let failure: HLSFailureReport?
}
public struct HLSIncidentSnapshot: Codable, Equatable, Sendable {
    public let operationID: UUID
    public let records: [HLSIncident]
    public let droppedRecordCount: UInt64
    public var isTruncated: Bool { droppedRecordCount > 0 }
}

/// Explicit application-side incident composition, not automatic interception.
/// Only typed scalar classifications enter the buffer. Raw progress, URL,
/// headers, local paths and key/credential payloads cannot be supplied here.
/// Do not call from a realtime audio callback; hop from the application layer.
public actor HLSIncidentBuffer {
    private let operationID: UUID
    private let maximumRecords: Int
    private var records: [HLSIncident] = []
    private var sequence: UInt64 = 0
    private var drops: UInt64 = 0
    public init(operationID: UUID, maximumRecords: Int = 64) throws {
        guard (1...128).contains(maximumRecords) else { throw HLSIncidentError.invalidCapacity }
        self.operationID = operationID
        self.maximumRecords = maximumRecords
    }
    public func record(_ stage: HLSOperationStage, failure: HLSFailureReport? = nil) throws {
        guard failure?.operationID == nil || failure?.operationID == operationID else {
            throw HLSIncidentError.mismatchedOperation
        }
        guard sequence < UInt64.max else { throw HLSIncidentError.sequenceExhausted }
        sequence += 1
        if records.count == maximumRecords {
            records.removeFirst()
            drops += 1
        }
        records.append(HLSIncident(operationID: operationID, sequence: sequence, stage: stage, failure: failure))
    }
    public func snapshot() -> HLSIncidentSnapshot {
        .init(operationID: operationID, records: records, droppedRecordCount: drops)
    }
}
