import Foundation
import InnoNetwork

struct HLSPathwayResource: Sendable {
    let pathwayID: String?
    let transfer: HLSResourceTransfer
    let aes128KeySet: HLSAES128KeySet
}

struct HLSPathwayFailure: Sendable {
    let pathwayID: String?
    let phase: HLSContentSteeringPhase
    let errorCode: HLSDownloadErrorCode
}

actor HLSContentSteeringRecovery {
    private let playlistResolver: PlaylistResolver
    private let keyResolver: HLSAES128KeyResolver
    private let maximumTransferBytes: Int
    private let primaryVariant: HLSVariant
    private let primaryContainer: HLSMediaContainer
    private let primaryTransfers: [HLSResourceTransfer]
    private let contentSteeringSession: HLSContentSteeringSession
    private let candidates: [HLSMediaPlaylistCandidate]
    private var activePlan: ActivePlan?
    private var activation: Activation?

    // Internal bounded lifecycle observation used by deterministic integration
    // checks; no request URL, credential or activation implementation escapes.
    var pendingActivationWaiterCount: Int { activation?.waiters.count ?? 0 }

    init(
        client: HLSHTTPClient,
        clock: any HLSClock,
        retryPolicy: (any RetryPolicy)?,
        maximumTransferBytes: Int,
        primaryVariant: HLSVariant,
        primaryContainer: HLSMediaContainer,
        primaryTransfers: [HLSResourceTransfer],
        candidates: [HLSMediaPlaylistCandidate],
        contentSteeringSession: HLSContentSteeringSession
    ) {
        self.playlistResolver = PlaylistResolver(client: client)
        self.keyResolver = HLSAES128KeyResolver(
            client: client,
            retryPolicy: retryPolicy,
            clock: clock
        )
        self.maximumTransferBytes = maximumTransferBytes
        self.primaryVariant = primaryVariant
        self.primaryContainer = primaryContainer
        self.primaryTransfers = primaryTransfers
        self.candidates = candidates
        self.contentSteeringSession = contentSteeringSession
    }

    func resource(
        at index: Int,
        after failure: HLSPathwayFailure,
        excludingPathwayIDs: Set<String>
    ) async throws -> HLSPathwayResource? {
        try Task.checkCancellation()
        if let activePlan,
            activePlan.pathwayID != failure.pathwayID,
            !Self.isExcluded(
                activePlan.pathwayID,
                by: excludingPathwayIDs
            )
        {
            return activePlan.resource(at: index)
        }
        if activePlan?.pathwayID == failure.pathwayID {
            activePlan = nil
        }

        let plan = try await waitForActivation(
            after: failure,
            excludingPathwayIDs: excludingPathwayIDs
        )
        try Task.checkCancellation()
        guard !Self.isExcluded(plan?.pathwayID, by: excludingPathwayIDs) else {
            return nil
        }
        return plan?.resource(at: index)
    }

    private func waitForActivation(
        after failure: HLSPathwayFailure,
        excludingPathwayIDs: Set<String>
    ) async throws -> ActivePlan? {
        let waiterID = UUID()
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                guard !Task.isCancelled else {
                    continuation.resume(throwing: CancellationError())
                    return
                }
                if activation != nil {
                    activation?.waiters[waiterID] = continuation
                    return
                }
                let activationID = UUID()
                let task = Task {
                    let result: Result<ActivePlan?, Error>
                    do {
                        result = .success(
                            try await self.activateNextPlan(
                                after: failure,
                                excludingPathwayIDs: excludingPathwayIDs
                            )
                        )
                    } catch {
                        result = .failure(error)
                    }
                    self.completeActivation(id: activationID, result: result)
                }
                activation = Activation(
                    id: activationID,
                    task: task,
                    waiters: [waiterID: continuation]
                )
            }
        } onCancel: {
            Task { await self.cancelWaiter(waiterID) }
        }
    }

    private func cancelWaiter(_ id: UUID) {
        guard let continuation = activation?.waiters.removeValue(forKey: id) else {
            return
        }
        if activation?.waiters.isEmpty == true {
            let task = activation?.task
            activation = nil
            task?.cancel()
        }
        continuation.resume(throwing: CancellationError())
    }

    private func completeActivation(
        id: UUID,
        result: Result<ActivePlan?, Error>
    ) {
        guard let completed = activation, completed.id == id else { return }
        activation = nil
        if case .success(let plan) = result { activePlan = plan }
        for continuation in completed.waiters.values {
            continuation.resume(with: result)
        }
    }

    private func activateNextPlan(
        after failure: HLSPathwayFailure,
        excludingPathwayIDs: Set<String>
    ) async throws -> ActivePlan? {
        for candidate in candidates {
            try Task.checkCancellation()
            guard candidate.pathwayID != failure.pathwayID else {
                continue
            }
            guard
                !Self.isExcluded(
                    candidate.pathwayID,
                    by: excludingPathwayIDs
                )
            else {
                continue
            }
            guard isVariantCompatible(candidate.variant) else {
                continue
            }
            let admission = await contentSteeringSession.beginAttempt(
                pathwayID: candidate.pathwayID,
                phase: .mediaPlaylist,
                resourceIndex: nil
            )
            guard admission != .penalized else {
                continue
            }
            try Task.checkCancellation()
            do {
                let document = try await playlistResolver.resolveDocument(
                    from: candidate.variant.url,
                    multivariantVariables:
                        candidate.multivariantVariables,
                    purpose: .mediaPlaylist
                )
                try Task.checkCancellation()
                guard
                    let media = document.playlist.media,
                    let container = document.playlist.mediaContainer
                else {
                    await emitPlaylistFailure(
                        for: candidate.pathwayID,
                        code: .invalidPlaylist
                    )
                    continue
                }
                try HLSMediaPlaylistValidator.validate(media)
                let transfers = HLSResourcePlan(
                    resources: media.resources,
                    maximumTransferBytes: maximumTransferBytes
                ).transfers
                guard
                    container == primaryContainer,
                    Self.isCompatible(
                        primaryTransfers,
                        transfers
                    )
                else {
                    await emitPlaylistFailure(
                        for: candidate.pathwayID,
                        code: .invalidPlaylist
                    )
                    continue
                }
                let keySet = try await keyResolver.resolve(
                    resources: transfers
                )
                try Task.checkCancellation()
                let plan = ActivePlan(
                    pathwayID: candidate.pathwayID,
                    transfers: transfers,
                    aes128KeySet: keySet
                )
                await contentSteeringSession.recordSuccess(
                    pathwayID: candidate.pathwayID,
                    phase: .mediaPlaylist,
                    resourceIndex: nil,
                    selection: HLSContentSteeringSession.Selection(
                        fromPathwayID: failure.pathwayID,
                        reason:
                            admission == .recovered
                            ? .cooldownRecovery
                            : .pathwayFailure(
                                phase: failure.phase,
                                errorCode: failure.errorCode
                            )
                    )
                )
                return plan
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                await emitPlaylistFailure(
                    for: candidate.pathwayID,
                    code: (error as? HLSDownloadError)?.code
                        ?? .transferFailed
                )
                continue
            }
        }
        return nil
    }

    private static func isExcluded(
        _ pathwayID: String?,
        by excludedPathwayIDs: Set<String>
    ) -> Bool {
        pathwayID.map(excludedPathwayIDs.contains) ?? false
    }

    private func emitPlaylistFailure(
        for pathwayID: String?,
        code: HLSDownloadErrorCode
    ) async {
        await contentSteeringSession.recordFailure(
            pathwayID: pathwayID,
            phase: .mediaPlaylist,
            resourceIndex: nil,
            errorCode: code
        )
    }

    private func isVariantCompatible(
        _ candidate: HLSVariant
    ) -> Bool {
        guard
            let stableID = primaryVariant.stableID,
            stableID == candidate.stableID
        else {
            return false
        }
        return primaryVariant.codecs == candidate.codecs
            && primaryVariant.supplementalCodecs
                == candidate.supplementalCodecs
            && primaryVariant.width == candidate.width
            && primaryVariant.height == candidate.height
            && primaryVariant.videoRange == candidate.videoRange
    }

    private static func isCompatible(
        _ primary: [HLSResourceTransfer],
        _ fallback: [HLSResourceTransfer]
    ) -> Bool {
        guard primary.count == fallback.count else {
            return false
        }
        return zip(primary, fallback).allSatisfy { first, second in
            first.url.path == second.url.path
                && first.byteRange == second.byteRange
                && encryptionIsCompatible(
                    first.encryption,
                    second.encryption
                )
        }
    }

    private static func encryptionIsCompatible(
        _ first: HLSAES128Encryption?,
        _ second: HLSAES128Encryption?
    ) -> Bool {
        switch (first, second) {
        case (nil, nil):
            return true
        case (.some(let first), .some(let second)):
            return first.initializationVector
                == second.initializationVector
        case (.none, .some), (.some, .none):
            return false
        }
    }

    private struct ActivePlan: Sendable {
        let pathwayID: String?
        let transfers: [HLSResourceTransfer]
        let aes128KeySet: HLSAES128KeySet

        func resource(
            at index: Int
        ) -> HLSPathwayResource? {
            guard transfers.indices.contains(index) else {
                return nil
            }
            return HLSPathwayResource(
                pathwayID: pathwayID,
                transfer: transfers[index],
                aes128KeySet: aes128KeySet
            )
        }
    }

    private struct Activation: Sendable {
        let id: UUID
        let task: Task<Void, Never>
        var waiters: [UUID: CheckedContinuation<ActivePlan?, Error>]
    }
}
