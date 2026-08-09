import Foundation

public struct LifecycleDiagnosticsSnapshot: Equatable, Sendable {
    public var activeVisibleDirectoryObserverCount: Int
    public var visibleDirectoryObserverStartCount: Int
    public var visibleDirectoryObserverStopCount: Int
    public var activeVolumeObserverCount: Int
    public var volumeObserverStartCount: Int
    public var volumeObserverStopCount: Int
    public var callbackCount: Int
    public var staleCallbackCount: Int
    public var postCloseCallbackCount: Int
    public var uiMutationCount: Int
    public var activeThumbnailCount: Int
    public var timerCount: Int
    public var animationCount: Int

    public init(
        activeVisibleDirectoryObserverCount: Int = 0,
        visibleDirectoryObserverStartCount: Int = 0,
        visibleDirectoryObserverStopCount: Int = 0,
        activeVolumeObserverCount: Int = 0,
        volumeObserverStartCount: Int = 0,
        volumeObserverStopCount: Int = 0,
        callbackCount: Int = 0,
        staleCallbackCount: Int = 0,
        postCloseCallbackCount: Int = 0,
        uiMutationCount: Int = 0,
        activeThumbnailCount: Int = 0,
        timerCount: Int = 0,
        animationCount: Int = 0
    ) {
        self.activeVisibleDirectoryObserverCount = activeVisibleDirectoryObserverCount
        self.visibleDirectoryObserverStartCount = visibleDirectoryObserverStartCount
        self.visibleDirectoryObserverStopCount = visibleDirectoryObserverStopCount
        self.activeVolumeObserverCount = activeVolumeObserverCount
        self.volumeObserverStartCount = volumeObserverStartCount
        self.volumeObserverStopCount = volumeObserverStopCount
        self.callbackCount = callbackCount
        self.staleCallbackCount = staleCallbackCount
        self.postCloseCallbackCount = postCloseCallbackCount
        self.uiMutationCount = uiMutationCount
        self.activeThumbnailCount = activeThumbnailCount
        self.timerCount = timerCount
        self.animationCount = animationCount
    }
}

public final class LifecycleDiagnostics: @unchecked Sendable {
    private let lock = NSLock()
    private var snapshotStorage = LifecycleDiagnosticsSnapshot()

    public init() {}

    public var snapshot: LifecycleDiagnosticsSnapshot {
        lock.lock()
        defer { lock.unlock() }
        return snapshotStorage
    }

    public func visibleDirectoryObserverStarted() {
        lock.lock()
        snapshotStorage.activeVisibleDirectoryObserverCount += 1
        snapshotStorage.visibleDirectoryObserverStartCount += 1
        lock.unlock()
    }

    public func visibleDirectoryObserverStopped() {
        lock.lock()
        if snapshotStorage.activeVisibleDirectoryObserverCount > 0 {
            snapshotStorage.activeVisibleDirectoryObserverCount -= 1
        }
        snapshotStorage.visibleDirectoryObserverStopCount += 1
        lock.unlock()
    }

    public func volumeObserverStarted() {
        lock.lock()
        snapshotStorage.activeVolumeObserverCount += 1
        snapshotStorage.volumeObserverStartCount += 1
        lock.unlock()
    }

    public func volumeObserverStopped() {
        lock.lock()
        if snapshotStorage.activeVolumeObserverCount > 0 {
            snapshotStorage.activeVolumeObserverCount -= 1
        }
        snapshotStorage.volumeObserverStopCount += 1
        lock.unlock()
    }

    public func callbackArrived(active: Bool, stale: Bool = false) {
        lock.lock()
        snapshotStorage.callbackCount += 1
        if stale {
            snapshotStorage.staleCallbackCount += 1
        } else if active == false {
            snapshotStorage.postCloseCallbackCount += 1
        }
        lock.unlock()
    }

    public func uiMutationRecorded() {
        lock.lock()
        snapshotStorage.uiMutationCount += 1
        lock.unlock()
    }

    public func setActiveThumbnailCount(_ count: Int) {
        lock.lock()
        snapshotStorage.activeThumbnailCount = count
        lock.unlock()
    }
}
