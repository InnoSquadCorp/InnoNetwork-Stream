import AVFoundation
import Foundation
import os

/// Observes server-authored or application-authored interstitial playback.
///
/// The monitor is read-only: it does not replace the interstitial schedule,
/// cancel playback, or invoke skip controls.
@MainActor
public final class HLSInterstitialPlaybackMonitor {
    private let monitor: AVPlayerInterstitialEventMonitor
    private let notificationCenter: NotificationCenter
    private let maximumBufferedEventCount: Int

    /// Creates a read-only monitor for one caller-owned primary player.
    ///
    /// The buffer limit is clamped to `2...1,024` so the initial schedule and
    /// current-event snapshots are both retained. The caller must retain the
    /// player and this bridge for the desired observation lifetime.
    public init(
        primaryPlayer: AVPlayer,
        maximumBufferedEventCount: Int = 64
    ) {
        self.monitor = AVPlayerInterstitialEventMonitor(
            primaryPlayer: primaryPlayer
        )
        self.notificationCenter = .default
        self.maximumBufferedEventCount =
            Self.clampedBufferedEventCount(
                maximumBufferedEventCount
            )
    }

    init(
        monitor: AVPlayerInterstitialEventMonitor,
        notificationCenter: NotificationCenter = .default,
        maximumBufferedEventCount: Int = 64
    ) {
        self.monitor = monitor
        self.notificationCenter = notificationCenter
        self.maximumBufferedEventCount =
            Self.clampedBufferedEventCount(
                maximumBufferedEventCount
            )
    }

    static func clampedBufferedEventCount(_ value: Int) -> Int {
        min(1_024, max(2, value))
    }

    /// Starts one independent, cancellation-safe lifecycle stream.
    ///
    /// The stream first yields the current schedule and current event. When a
    /// consumer falls behind, the newest events replace older buffered values.
    /// Notification listeners are installed before this method returns.
    public func events()
        -> AsyncStream<HLSInterstitialRuntimeEvent>
    {
        let (stream, continuation) =
            AsyncStream<
                HLSInterstitialRuntimeEvent
            >.makeStream(
                bufferingPolicy: .bufferingNewest(
                    maximumBufferedEventCount
                )
            )
        let monitor = monitor
        let notificationCenter = notificationCenter
        continuation.yield(
            .scheduleChanged(
                monitor.events.map(
                    HLSInterstitialRuntimeMapper.snapshot
                )
            )
        )
        continuation.yield(
            .currentEventChanged(
                monitor.currentEvent.map(
                    HLSInterstitialRuntimeMapper.snapshot
                )
            )
        )

        let observations = Self.observations(
            monitor: monitor,
            notificationCenter: notificationCenter,
            continuation: continuation
        )
        continuation.onTermination = { _ in
            observations.cancel()
        }
        return stream
    }

    private static func observations(
        monitor: AVPlayerInterstitialEventMonitor,
        notificationCenter: NotificationCenter,
        continuation:
            AsyncStream<
                HLSInterstitialRuntimeEvent
            >.Continuation
    ) -> HLSInterstitialNotificationObservations {
        let receive: @MainActor @Sendable (Notification) -> Void = {
            notification in
            if let event = HLSInterstitialRuntimeMapper.map(
                notification,
                monitor: monitor
            ) {
                continuation.yield(event)
            }
        }
        let tokens = notificationNames.map { name in
            notificationCenter.addObserver(
                forName: name,
                object: monitor,
                queue: .main
            ) { notification in
                // NotificationCenter guarantees delivery on the supplied
                // main queue. Map AVFoundation objects here instead of
                // transferring non-Sendable notification payloads to a task.
                // The synchronous queue contract supplies the isolation that
                // Foundation's observer callback type cannot express. Keep
                // this escape local; the notification must never be stored
                // or captured by an asynchronous operation.
                nonisolated(unsafe) let deliveredNotification = notification
                MainActor.assumeIsolated {
                    receive(deliveredNotification)
                }
            }
        }
        return HLSInterstitialNotificationObservations(
            notificationCenter: notificationCenter,
            tokens: tokens
        )
    }

    private static var notificationNames: [Notification.Name] {
        var names: [Notification.Name] = [
            AVPlayerInterstitialEventMonitor
                .eventsDidChangeNotification,
            AVPlayerInterstitialEventMonitor
                .currentEventDidChangeNotification,
        ]
        names.append(
            contentsOf:
                HLSInterstitialAssetListMapper.notificationNames
        )
        if #available(macOS 26,
        iOS 26,
        tvOS 26,
        watchOS 26,
        visionOS 26,
        *) {
            names.append(
                contentsOf: [
                    AVPlayerInterstitialEventMonitor
                        .currentEventSkippableStateDidChangeNotification,
                    AVPlayerInterstitialEventMonitor
                        .currentEventSkippedNotification,
                    AVPlayerInterstitialEventMonitor
                        .interstitialEventWasUnscheduledNotification,
                    AVPlayerInterstitialEventMonitor
                        .interstitialEventDidFinishNotification,
                ]
            )
        }
        names.append(
            contentsOf:
                HLSInterstitialScheduleRequestMapper
                .notificationNames
        )
        return names
    }
}

// Termination may run on any executor. The lock transfers token ownership to
// exactly one remover, without retaining the monitor in a long-lived task.
private final class HLSInterstitialNotificationObservations: Sendable {
    private let notificationCenter: NotificationCenter
    private let tokens: OSAllocatedUnfairLock<[any NSObjectProtocol]>

    init(
        notificationCenter: NotificationCenter,
        tokens: [any NSObjectProtocol]
    ) {
        self.notificationCenter = notificationCenter
        self.tokens = OSAllocatedUnfairLock(uncheckedState: tokens)
    }

    func cancel() {
        // Foundation observer tokens are opaque and non-Sendable. They
        // escape the lock only after removal from its state, to be handed
        // straight back to the thread-safe NotificationCenter exactly once.
        let pending = tokens.withLockUnchecked { tokens in
            let pending = tokens
            tokens.removeAll()
            return pending
        }
        for token in pending {
            notificationCenter.removeObserver(token)
        }
    }

    deinit {
        cancel()
    }
}

@MainActor
enum HLSInterstitialRuntimeMapper {
    static func map(
        _ notification: Notification,
        monitor: AVPlayerInterstitialEventMonitor
    ) -> HLSInterstitialRuntimeEvent? {
        switch notification.name {
        case AVPlayerInterstitialEventMonitor
            .eventsDidChangeNotification:
            return .scheduleChanged(
                monitor.events.map(snapshot)
            )
        case AVPlayerInterstitialEventMonitor
            .currentEventDidChangeNotification:
            return .currentEventChanged(
                monitor.currentEvent.map(snapshot)
            )
        default:
            return HLSInterstitialAssetListMapper.map(notification)
                ?? mapNewerNotification(notification)
        }
    }

    private static func mapNewerNotification(
        _ notification: Notification
    ) -> HLSInterstitialRuntimeEvent? {
        if #available(macOS 26,
        iOS 26,
        tvOS 26,
        watchOS 26,
        visionOS 26,
        *) {
            return mapVersion26Notification(notification)
        }
        return nil
    }

    static func snapshot(
        _ event: AVPlayerInterstitialEvent
    ) -> HLSInterstitialEventSnapshot {
        HLSInterstitialEventSnapshot(
            identifier: event.identifier,
            scheduledTime: finite(event.time),
            scheduledDate: event.date,
            templateItemCount: max(0, event.templateItems.count),
            resumptionOffset: finite(event.resumptionOffset),
            playoutLimit: finiteNonnegative(event.playoutLimit)
        )
    }

    static func finite(_ time: CMTime) -> TimeInterval? {
        guard time.isNumeric, time.seconds.isFinite else {
            return nil
        }
        return time.seconds
    }

    static func finiteNonnegative(
        _ time: CMTime
    ) -> TimeInterval? {
        guard let seconds = finite(time), seconds >= 0 else {
            return nil
        }
        return seconds
    }
}

@available(
    macOS 26,
    iOS 26,
    tvOS 26,
    watchOS 26,
    visionOS 26,
    *
)
@MainActor
extension HLSInterstitialRuntimeMapper {
    static func mapVersion26Notification(
        _ notification: Notification
    ) -> HLSInterstitialRuntimeEvent? {
        switch notification.name {
        case AVPlayerInterstitialEventMonitor
            .currentEventSkippableStateDidChangeNotification:
            return mapSkippable(notification)
        case AVPlayerInterstitialEventMonitor
            .currentEventSkippedNotification:
            return event(
                in: notification,
                key:
                    AVPlayerInterstitialEventMonitor
                    .currentEventSkippedEventKey
            ).map {
                .skipped(snapshot($0))
            }
        case AVPlayerInterstitialEventMonitor
            .interstitialEventWasUnscheduledNotification:
            return event(
                in: notification,
                key:
                    AVPlayerInterstitialEventMonitor
                    .interstitialEventWasUnscheduledEventKey
            ).map {
                .unscheduled(
                    snapshot($0),
                    hadError:
                        notification.userInfo?[
                            AVPlayerInterstitialEventMonitor
                                .interstitialEventWasUnscheduledErrorKey
                        ] != nil
                )
            }
        case AVPlayerInterstitialEventMonitor
            .interstitialEventDidFinishNotification:
            return mapFinished(notification)
        default:
            return HLSInterstitialScheduleRequestMapper.map(
                notification
            )
        }
    }

    static func mapSkippable(
        _ notification: Notification
    ) -> HLSInterstitialRuntimeEvent? {
        guard
            let event = event(
                in: notification,
                key:
                    AVPlayerInterstitialEventMonitor
                    .currentEventSkippableStateDidChangeEventKey
            ),
            let rawState =
                (notification.userInfo?[
                    AVPlayerInterstitialEventMonitor
                        .currentEventSkippableStateDidChangeStateKey
                ] as? NSNumber)?.intValue
        else {
            return nil
        }
        let state: HLSInterstitialSkippableState
        switch AVPlayerInterstitialEvent.SkippableEventState(
            rawValue: rawState
        ) {
        case .notSkippable:
            state = .notSkippable
        case .notYetEligible:
            state = .notYetEligible
        case .eligible:
            state = .eligible
        case .noLongerEligible:
            state = .noLongerEligible
        default:
            state = .other
        }
        return .skippableStateChanged(
            snapshot(event),
            state: state
        )
    }

    static func mapFinished(
        _ notification: Notification
    ) -> HLSInterstitialRuntimeEvent? {
        guard
            let event = event(
                in: notification,
                key:
                    AVPlayerInterstitialEventMonitor
                    .interstitialEventDidFinishEventKey
            )
        else {
            return nil
        }
        let playoutTime = notification.userInfo?[
            AVPlayerInterstitialEventMonitor
                .interstitialEventDidFinishPlayoutTimeKey
        ]
        let time: CMTime?
        if let value = playoutTime as? NSValue {
            time = value.timeValue
        } else {
            time = playoutTime as? CMTime
        }
        let didPlayEntireEvent =
            (notification.userInfo?[
                AVPlayerInterstitialEventMonitor
                    .interstitialEventDidFinishDidPlayEntireEventKey
            ] as? NSNumber)?.boolValue ?? false
        return .finished(
            snapshot(event),
            playoutDuration: time.flatMap(finiteNonnegative),
            didPlayEntireEvent: didPlayEntireEvent
        )
    }

    static func event(
        in notification: Notification,
        key: String
    ) -> AVPlayerInterstitialEvent? {
        notification.userInfo?[key]
            as? AVPlayerInterstitialEvent
    }
}
