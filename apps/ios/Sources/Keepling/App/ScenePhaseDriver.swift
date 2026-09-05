import Foundation
import KeeplingCore
import Network
import SwiftUI

/// Translates SwiftUI `ScenePhase` transitions and network path changes
/// into `KeeplingApplication.runSyncPass` invocations (04-08-PLAN.md
/// Task 3). This is the FOREGROUND half of the "background is an
/// accelerator, not a correctness dependency" proof: entering the active
/// scene phase, or a network reconnect while active, is what actually
/// drives correctness. The background handler (`BackgroundRefresh`) calls
/// the SAME `runSyncPass` entry point on the SAME `KeeplingApplication`
/// instance -- there is no separate reconciliation path for the two
/// triggers to drift from.
@MainActor
public final class ScenePhaseDriver {
    private let application: KeeplingApplication
    private let pathMonitor: NWPathMonitor
    private let monitorQueue = DispatchQueue(label: "com.szTheory.keepling.scene-phase-driver.path-monitor")
    private var lastPathWasSatisfied = true
    private var currentPassTask: Task<Void, Never>?

    /// Test seam: overrides the real `NWPathMonitor`-driven reconnect
    /// signal is not needed for MOST tests (they call `triggerPass()`
    /// directly), but `activePhaseAlsoStartsMonitoring` lets a test disable
    /// the real monitor entirely (it touches a real system service) while
    /// still exercising `scenePhaseChanged`.
    public init(application: KeeplingApplication, startMonitoringPath: Bool = true) {
        self.application = application
        pathMonitor = NWPathMonitor()
        if startMonitoringPath {
            pathMonitor.pathUpdateHandler = { [weak self] path in
                Task { @MainActor in self?.handlePathUpdate(path) }
            }
            pathMonitor.start(queue: monitorQueue)
        }
    }

    deinit {
        pathMonitor.cancel()
    }

    /// Call from `.onChange(of: scenePhase)` in the app's root scene.
    /// Entering `.active` runs a pass -- covers cold launch (SwiftUI
    /// delivers an initial `.active` phase), foreground resume, AND a
    /// non-empty outbox from a PRIOR launch that never got a chance to
    /// drain, regardless of whether any background wake ever ran.
    /// `.inactive`/`.background` deliberately do nothing here: a pass
    /// already in flight is never interrupted by THIS driver (it is the
    /// pass's own transactional design -- claim, then push, then settle --
    /// that guarantees nothing is left half-applied, not a check made at
    /// this call site).
    public func scenePhaseChanged(to phase: ScenePhase) {
        switch phase {
        case .active:
            triggerPass()
        case .inactive, .background:
            break
        @unknown default:
            break
        }
    }

    private func handlePathUpdate(_ path: NWPath) {
        let satisfied = path.status == .satisfied
        defer { lastPathWasSatisfied = satisfied }
        guard satisfied, !lastPathWasSatisfied else { return }
        triggerPass()
    }

    /// Runs one sync pass. Public (not merely `private`) so a test can
    /// drive it directly without depending on real `ScenePhase`/`NWPath`
    /// delivery timing.
    @discardableResult
    public func triggerPass() -> Task<Void, Never> {
        let task = Task { [application] in
            _ = try? await application.runSyncPass()
        }
        currentPassTask = task
        return task
    }
}
