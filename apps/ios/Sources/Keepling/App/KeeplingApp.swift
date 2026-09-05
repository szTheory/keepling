import KeeplingCore
import SwiftUI

/// The app entry point. Routes to `RootTabView` (D-25's two-tab shell,
/// 04-09-PLAN.md Task 1) via one `WorkspaceFacade` constructed once here --
/// the single presentation-only boundary every view depends on.
@main
struct KeeplingApp: App {
    // Non-nil only when `KEEPLING_ACCESSORY_PROBE_MODE` is present in the
    // process environment -- exclusively set by
    // `AccessoryAbsenceProbeTests`' launch configuration (04-04-PLAN.md
    // Task 1, threat T-04-04-03). The probe scene needs no local store, so
    // resolving it first skips `GRDBLocalStore` entirely for probe runs.
    private let probeMode: AccessoryProbeMode?
    private let store: GRDBLocalStore?
    // Non-nil only alongside `store` -- the tracer/probe modes above have
    // nothing to sync, so there is no application/driver to construct
    // (04-08-PLAN.md Task 3).
    private let scenePhaseDriver: ScenePhaseDriver?
    private let backgroundRefresh: BackgroundRefresh?
    // Constructed once in `init()`, not per `body` evaluation -- `body` is a
    // computed property SwiftUI can re-evaluate, and a fresh
    // `WorkspaceFacade` on every evaluation would silently drop its
    // `@Published items` state (04-09-PLAN.md Task 1).
    private let facade: WorkspaceFacade?
    @Environment(\.scenePhase) private var scenePhase

    init() {
        if let probeMode = AccessoryProbeMode(environment: ProcessInfo.processInfo.environment) {
            self.probeMode = probeMode
            self.store = nil
            self.scenePhaseDriver = nil
            self.backgroundRefresh = nil
            self.facade = nil
            return
        }
        self.probeMode = nil

        let directory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Keepling", isDirectory: true)
        let path = directory.appendingPathComponent("keepling.sqlite").path
        // UI-test-only reset hook: XCUITest launches a fresh app process
        // each run but the simulator's Application Support directory
        // persists across launches, so without this a UI test would
        // accumulate rows from every prior run.
        if ProcessInfo.processInfo.environment["KEEPLING_UITEST_RESET_STORE"] == "1" {
            try? FileManager.default.removeItem(atPath: path)
            try? FileManager.default.removeItem(atPath: path + "-wal")
            try? FileManager.default.removeItem(atPath: path + "-shm")
        }
        // A store that fails to open is a launch-time fatal condition in
        // this tracer -- D-22's "never present a false empty workspace"
        // rule means the app must not silently start with no store at all.
        // swiftlint:disable:next force_try
        let openedStore = try! GRDBLocalStore(path: path)
        store = openedStore
        let builtFacade = WorkspaceFacade(store: openedStore)
        facade = builtFacade

        // UI-test-only fixture hooks (04-10-PLAN.md Task 2): launch
        // deterministically into a fixed synchronization/undo state so
        // `SyncRecoveryTests` can assert accessory/sheet/overflow-menu
        // rendering per state without a real sync pass.
        if let testState = ProcessInfo.processInfo.environment["KEEPLING_UITEST_SYNC_STATE"] {
            builtFacade.applyUITestSyncState(testState)
        }
        if ProcessInfo.processInfo.environment["KEEPLING_UITEST_UNDO_AVAILABLE"] == "1" {
            builtFacade.updateUndoAvailability(UndoAvailabilityPresentation(actionLabel: "Undo Trash"))
        }
        // UI-test-only fixture hook (04-10-PLAN.md Task 3): seeds one REAL
        // per-task conflict through the actual capture -> acknowledge(
        // outcome: .conflict) path `KeeplingApplication.runSyncPass` itself
        // drives (04-06-PLAN.md Task 1) -- never a synthesized/faked
        // `WorkspaceItem`, so `SyncRecoveryTests` exercises the same
        // conflict-recording code a real sync pass exercises.
        if ProcessInfo.processInfo.environment["KEEPLING_UITEST_SEED_CONFLICT"] == "1" {
            Task.detached(priority: .userInitiated) {
                let mutationId = UUID().uuidString
                let taskId = UUID().uuidString
                guard let built = try? OutboundCommands.capture(title: "Conflicted Task", mutationId: mutationId, taskId: taskId) else { return }
                let mutation = LocalMutation(
                    mutationId: built.mutationId,
                    taskId: built.taskId,
                    commandBytes: built.commandBytes,
                    fingerprint: built.fingerprint,
                    acceptedAt: ISO8601DateFormatter().string(from: Date()),
                    resourceKeys: built.resourceKeys,
                    title: built.effect.title,
                    effect: LocalMutation.ProjectionEffect(
                        notes: built.effect.notes, completedAt: built.effect.completedAt, trashedAt: built.effect.trashedAt, planned: false
                    )
                )
                _ = try? openedStore.acceptMutation(mutation)
                let currentJSON = "{\"id\":\"\(taskId)\",\"title\":\"Conflicted Task\",\"revision\":2}"
                _ = try? openedStore.acknowledge(SyncAcknowledgement(
                    mutationId: mutationId, fingerprint: built.fingerprint, outcome: .conflict,
                    snapshotJSON: currentJSON, affectedFields: ["title"]
                ))
                await builtFacade.refresh()
            }
        }

        // UI-test-only fixture hook (04-11-PLAN.md Task 2): seeds one or
        // more REAL undo availabilities through the actual capture ->
        // accept -> acknowledge(undo:) path `GRDBLocalStore.acknowledge`
        // itself drives (04-11-PLAN.md Task 1) -- never a synthesized
        // `UndoAvailabilityPresentation`, so `UndoPersistenceTests` can
        // exercise `WorkspaceFacade.invokeUndo()` end to end and prove a
        // SECOND real settlement replaces the first's label. Comma-
        // separated steps, each `trash` or `complete`; each seeds a fresh
        // task and settles ITS lifecycle command with a server-shaped
        // (but locally fabricated) undo handle -- there is no live server
        // in a UI test, so this is the same "drive the real local
        // machinery, fabricate only the wire answer" technique
        // `KEEPLING_UITEST_SEED_CONFLICT` above already established.
        if let seedUndo = ProcessInfo.processInfo.environment["KEEPLING_UITEST_SEED_UNDO"] {
            Task.detached(priority: .userInitiated) {
                for step in seedUndo.split(separator: ",") {
                    let taskId = UUID().uuidString
                    let captureMutationId = UUID().uuidString
                    guard let captureBuilt = try? OutboundCommands.capture(title: "Seeded \(step)", mutationId: captureMutationId, taskId: taskId) else { continue }
                    _ = try? openedStore.acceptMutation(LocalMutation(
                        mutationId: captureBuilt.mutationId, taskId: captureBuilt.taskId, commandBytes: captureBuilt.commandBytes,
                        fingerprint: captureBuilt.fingerprint, acceptedAt: ISO8601DateFormatter().string(from: Date()),
                        resourceKeys: captureBuilt.resourceKeys, title: captureBuilt.effect.title
                    ))
                    _ = try? openedStore.acknowledge(SyncAcknowledgement(
                        mutationId: captureMutationId, fingerprint: captureBuilt.fingerprint, outcome: .accepted,
                        snapshotJSON: "{\"id\":\"\(taskId)\",\"revision\":1,\"title\":\"Seeded \(step)\"}"
                    ))

                    let transition: OutboundCommands.Lifecycle = step == "complete" ? .complete : .trash
                    let label = step == "complete" ? "Undo Complete" : "Undo Trash"
                    let lifecycleMutationId = UUID().uuidString
                    guard let lifecycleBuilt = try? OutboundCommands.lifecycle(
                        transition, taskId: taskId, basis: .init(baseTitle: "Seeded \(step)", baseNotes: "", expectedRevision: 1),
                        mutationId: lifecycleMutationId, acceptedAt: ISO8601DateFormatter().string(from: Date())
                    ) else { continue }
                    _ = try? openedStore.acceptMutation(LocalMutation(
                        mutationId: lifecycleBuilt.mutationId, taskId: lifecycleBuilt.taskId, commandBytes: lifecycleBuilt.commandBytes,
                        fingerprint: lifecycleBuilt.fingerprint, acceptedAt: ISO8601DateFormatter().string(from: Date()),
                        resourceKeys: lifecycleBuilt.resourceKeys, title: lifecycleBuilt.effect.title,
                        effect: LocalMutation.ProjectionEffect(
                            notes: lifecycleBuilt.effect.notes, completedAt: lifecycleBuilt.effect.completedAt,
                            trashedAt: lifecycleBuilt.effect.trashedAt, planned: lifecycleBuilt.effect.planned
                        )
                    ))
                    _ = try? openedStore.acknowledge(SyncAcknowledgement(
                        mutationId: lifecycleMutationId, fingerprint: lifecycleBuilt.fingerprint, outcome: .accepted,
                        snapshotJSON: "{\"id\":\"\(taskId)\",\"revision\":2,\"title\":\"Seeded \(step)\"}",
                        undo: SyncAcknowledgement.UndoAvailabilityHandle(handle: String(repeating: "h", count: 43), label: label, expiresAt: "2027-01-01T00:00:00Z")
                    ))
                    if let current = try? openedStore.currentUndoAvailability() {
                        await builtFacade.updateUndoAvailability(UndoAvailabilityPresentation(actionLabel: current.label))
                    }
                    await builtFacade.refresh()
                }
            }
        }

        // 04-08-PLAN.md Task 3: the scene-phase driver and background
        // refresh handler both need a `KeeplingApplication`, which needs a
        // `SyncPort`. Server discovery/sign-in wiring the driver reads a
        // REAL base URL from is explicitly Plan 04-10's concern
        // (04-07-SUMMARY.md's own disclosed boundary: `SignInFlow.swift` is
        // not yet wired into root navigation). Until then, `KEEPLING_SERVER_URL`
        // is read directly so the driver/handler are fully constructed and
        // exercised whenever a base URL IS configured (e.g. local
        // development), and are simply absent (never crash, never present
        // a false workspace) when it is not.
        if let urlString = ProcessInfo.processInfo.environment["KEEPLING_SERVER_URL"],
           let baseURL = URL(string: urlString),
           let adapter = try? KeeplingSyncAdapter(baseURL: baseURL) {
            let application = KeeplingApplication(store: openedStore, syncPort: adapter)
            scenePhaseDriver = ScenePhaseDriver(application: application)
            let refresh = BackgroundRefresh(application: application)
            refresh.register()
            backgroundRefresh = refresh
        } else {
            scenePhaseDriver = nil
            backgroundRefresh = nil
        }
    }

    var body: some Scene {
        WindowGroup {
            if let probeMode {
                AccessoryProbeRootView(mode: probeMode)
            } else {
                RootTabView(facade: facade!)
            }
        }
        .onChange(of: scenePhase) { _, newPhase in
            scenePhaseDriver?.scenePhaseChanged(to: newPhase)
        }
    }
}
