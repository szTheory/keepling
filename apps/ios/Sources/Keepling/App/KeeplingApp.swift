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

        // `IntentStoreAccess.storePath()` (04-12-PLAN.md) is the single
        // source of truth for this path -- shared with `CaptureTaskIntent`/
        // `CompleteTaskIntent` so the app and every intent open the SAME
        // process-wide store handle (D-37), never a second one.
        let path = IntentStoreAccess.storePath()

        // 04-14-PLAN.md Task 1 (T-04-14-01): every UI-test-only
        // state-injection hook in this `init` is enclosed in `#if DEBUG`
        // blocks, compiled OUT of a Release build entirely -- not merely
        // gated by an environment variable a Release binary would still
        // contain the code path to read. This IS the deterministic
        // state-injection seam every one of the twelve presentation states
        // plus the zero/one/many/partial-data shapes is reached through
        // (`StateInjection.swift`, `SyncStateMatrixTests.swift`); its
        // absence from a Release build is this task's own acceptance
        // criterion, checked structurally by this plan's own `<verify>`
        // node script (a `#if DEBUG`/`#if TESTING` condition must wrap
        // this read) and confirmed by inspecting the compiled Release
        // configuration's preprocessor output.
        //
        // MUST run BEFORE `IntentStoreAccess.sharedStore()` opens the
        // process-wide handle below -- deleting the on-disk file out from
        // under an already-open GRDB connection is undefined (WAL/SHM
        // files left dangling against a stale file handle), which is
        // exactly the bug this comment now documents rather than silently
        // reintroduces: an earlier revision of this file opened the store
        // FIRST and reset second, which corrupted every UI-test run that
        // set `KEEPLING_UITEST_RESET_STORE`.
        #if DEBUG
        // UI-test-only reset hook: XCUITest launches a fresh app process
        // each run but the simulator's Application Support directory
        // persists across launches, so without this a UI test would
        // accumulate rows from every prior run.
        if ProcessInfo.processInfo.environment["KEEPLING_UITEST_RESET_STORE"] == "1" {
            try? FileManager.default.removeItem(atPath: path)
            try? FileManager.default.removeItem(atPath: path + "-wal")
            try? FileManager.default.removeItem(atPath: path + "-shm")
        }
        #endif

        // A store that fails to open is a launch-time fatal condition in
        // this tracer -- D-22's "never present a false empty workspace"
        // rule means the app must not silently start with no store at all.
        // swiftlint:disable:next force_try
        let openedStore = try! IntentStoreAccess.sharedStore()
        store = openedStore
        let builtFacade = WorkspaceFacade(store: openedStore)
        facade = builtFacade

        #if DEBUG
        // 04-14-PLAN.md Task 1: pre-seeds a durable capture draft (D-35)
        // through the SAME `saveDraft` round trip `CaptureDraftTests`
        // exercises -- AFTER the reset-store wipe above (so a fresh store
        // has nothing stale in it) and using the SAME process-wide
        // `openedStore` handle every other command in this file uses,
        // never a second connection racing the wipe above. `saveDraft`
        // asserts `assertNotOnMainThread()` (mirrors every other
        // `GRDBLocalStore` write) -- `init()` runs on the main thread, so
        // this MUST be dispatched off it, exactly like every other seed
        // hook in this file already does via `Task.detached`.
        if let draftTitle = ProcessInfo.processInfo.environment["KEEPLING_UITEST_SEED_DRAFT"] {
            Task.detached(priority: .userInitiated) {
                try? openedStore.saveDraft(CaptureDraft(title: draftTitle, addToToday: false))
            }
        }

        // UI-test-only fixture hooks (04-10-PLAN.md Task 2): launch
        // deterministically into a fixed synchronization/undo state so
        // `SyncRecoveryTests` can assert accessory/sheet/overflow-menu
        // rendering per state without a real sync pass.
        if let testState = ProcessInfo.processInfo.environment["KEEPLING_UITEST_SYNC_STATE"] {
            // 04-14-PLAN.md Task 1: `KEEPLING_UITEST_SYNC_STATE_COUNT`
            // overrides the hardcoded `pendingCount`/`affectedCount: 1`
            // every state carried before -- proving the "many" case is
            // genuinely bounded (`SyncPresentation.boundedCount`'s
            // existing 99 ceiling), not merely reachable at count 1.
            let count = ProcessInfo.processInfo.environment["KEEPLING_UITEST_SYNC_STATE_COUNT"].flatMap(Int.init)
            builtFacade.applyUITestSyncState(testState, count: count)
        }
        if ProcessInfo.processInfo.environment["KEEPLING_UITEST_UNDO_AVAILABLE"] == "1" {
            builtFacade.updateUndoAvailability(UndoAvailabilityPresentation(actionLabel: "Undo Trash"))
        }
        // 04-14-PLAN.md Task 1: seeds `count` real tasks through the SAME
        // `capture -> acceptMutation -> acknowledge(accepted)` path every
        // other seed hook in this file uses -- never a synthesized
        // `WorkspaceItem` -- so `SyncStateMatrixTests` can drive the zero
        // (item count 0, the store's own untouched empty state), one, and
        // many item-count shapes deterministically. Titles are numbered so
        // a "many" run's rows are individually distinguishable.
        if let rawCount = ProcessInfo.processInfo.environment["KEEPLING_UITEST_SEED_ITEM_COUNT"], let count = Int(rawCount), count > 0 {
            Task.detached(priority: .userInitiated) {
                for index in 0..<count {
                    let mutationId = UUID().uuidString
                    let taskId = UUID().uuidString
                    guard let built = try? OutboundCommands.capture(title: "Seeded item \(index + 1)", mutationId: mutationId, taskId: taskId) else { continue }
                    let mutation = LocalMutation(
                        mutationId: built.mutationId, taskId: built.taskId, commandBytes: built.commandBytes,
                        fingerprint: built.fingerprint, acceptedAt: ISO8601DateFormatter().string(from: Date()),
                        resourceKeys: built.resourceKeys, title: built.effect.title
                    )
                    _ = try? openedStore.acceptMutation(mutation)
                    _ = try? openedStore.acknowledge(SyncAcknowledgement(
                        mutationId: mutationId, fingerprint: built.fingerprint, outcome: .accepted,
                        snapshotJSON: "{\"id\":\"\(taskId)\",\"revision\":1,\"title\":\"Seeded item \(index + 1)\"}"
                    ))
                }
                await builtFacade.refresh()
            }
        }
        // 04-14-PLAN.md Task 2: seeds ONE real task whose title and notes
        // come from the held-out `Fixtures/long-text.json` values, passed
        // through by `OverflowAndLongTextTests` rather than read from the
        // fixture file a second time by this app-target process --
        // `capture` carries the title (bounded at 512 scalars, the same
        // client-side bound `OutboundCommands.capture` itself enforces),
        // then a real `edit` command touches ONLY `notes` (bounded at
        // 50000 scalars) so the resulting row exercises the identical
        // outbound path every other command in this app uses -- never a
        // synthesized `WorkspaceItem` with fabricated field values.
        if let longTitle = ProcessInfo.processInfo.environment["KEEPLING_UITEST_SEED_LONGTEXT_TITLE"] {
            let longNotes = ProcessInfo.processInfo.environment["KEEPLING_UITEST_SEED_LONGTEXT_NOTES"] ?? ""
            Task.detached(priority: .userInitiated) {
                let taskId = UUID().uuidString
                let captureMutationId = UUID().uuidString
                guard let captureBuilt = try? OutboundCommands.capture(title: longTitle, mutationId: captureMutationId, taskId: taskId) else { return }
                _ = try? openedStore.acceptMutation(LocalMutation(
                    mutationId: captureBuilt.mutationId, taskId: captureBuilt.taskId, commandBytes: captureBuilt.commandBytes,
                    fingerprint: captureBuilt.fingerprint, acceptedAt: ISO8601DateFormatter().string(from: Date()),
                    resourceKeys: captureBuilt.resourceKeys, title: captureBuilt.effect.title
                ))
                _ = try? openedStore.acknowledge(SyncAcknowledgement(
                    mutationId: captureMutationId, fingerprint: captureBuilt.fingerprint, outcome: .accepted,
                    snapshotJSON: uitestSnapshotJSON(id: taskId, revision: 1, title: captureBuilt.effect.title)
                ))
                // The edit(notes) mutation's OWN settlement is the FINAL
                // one on this Inbox task -- a CONFLICT, not an acceptance
                // (mirrors `KEEPLING_UITEST_SEED_CONFLICT`'s established
                // technique: acknowledge the mutation you just accepted,
                // with `.conflict` instead of `.accepted`) -- so this task
                // covers the "Inbox", "Task detail and editor", "Sync &
                // Recovery sheet", "Conflict resolver", and "Bottom
                // accessory" elements. The accessory's rendered copy for
                // `.conflict` is `SyncCopy.conflict`, the exact string
                // `long-text.json`'s own `recoveryCopyLongest` records.
                // A mutation can only be acknowledged ONCE -- acknowledging
                // the ALREADY-SETTLED capture mutation a second time (an
                // earlier revision of this hook tried exactly that) is a
                // no-op against an outbox row that is no longer pending.
                //
                // Deliberately NOT planned for Today: `WorkspaceFacade
                // .inboxItems`/`.todayItems` partition on the SAME
                // `planned` boolean (`!$0.planned` / `$0.planned`) -- a
                // task planned for Today disappears from `inboxItems`
                // entirely in this client's projection, so the "Today"
                // and "Inbox" elements need genuinely SEPARATE tasks, not
                // one task assumed to satisfy both (an earlier revision
                // of this hook made exactly that wrong assumption and
                // `testInboxRenders...` failed as a direct result).
                if !longNotes.isEmpty, let editBuilt = try? OutboundCommands.edit(
                    taskId: taskId, touched: .init(notes: longNotes),
                    basis: .init(baseTitle: captureBuilt.effect.title, baseNotes: "", expectedRevision: 1),
                    mutationId: UUID().uuidString
                ) {
                    // `effect:` MUST be passed explicitly -- the default
                    // `LocalMutation.ProjectionEffect()` is `notes: ""`,
                    // which would silently overwrite `visible_projection
                    // .notes` back to EMPTY at `acceptMutation`'s own
                    // UPSERT (an earlier revision of this hook omitted
                    // this and `testTaskDetailRenders...` failed as a
                    // direct result: the Show Full Value disclosure never
                    // appeared because the optimistic local projection
                    // never actually held the long notes text at all).
                    _ = try? openedStore.acceptMutation(LocalMutation(
                        mutationId: editBuilt.mutationId, taskId: editBuilt.taskId, commandBytes: editBuilt.commandBytes,
                        fingerprint: editBuilt.fingerprint, acceptedAt: ISO8601DateFormatter().string(from: Date()),
                        resourceKeys: editBuilt.resourceKeys, title: editBuilt.effect.title,
                        effect: LocalMutation.ProjectionEffect(notes: editBuilt.effect.notes, completedAt: nil, trashedAt: nil, planned: false)
                    ))
                    _ = try? openedStore.acknowledge(SyncAcknowledgement(
                        mutationId: editBuilt.mutationId, fingerprint: editBuilt.fingerprint, outcome: .conflict,
                        snapshotJSON: uitestSnapshotJSON(id: taskId, revision: 2, title: editBuilt.effect.title),
                        affectedFields: ["title"]
                    ))
                }

                // A SECOND, separately seeded task -- planned for Today,
                // never conflicted -- covers the "Today" element on its
                // own terms (Today's own overflow/clipping considerations
                // do not require an active exception).
                let todayTaskId = UUID().uuidString
                let todayMutationId = UUID().uuidString
                if let todayBuilt = try? OutboundCommands.capture(title: longTitle, mutationId: todayMutationId, taskId: todayTaskId) {
                    _ = try? openedStore.acceptMutation(LocalMutation(
                        mutationId: todayBuilt.mutationId, taskId: todayBuilt.taskId, commandBytes: todayBuilt.commandBytes,
                        fingerprint: todayBuilt.fingerprint, acceptedAt: ISO8601DateFormatter().string(from: Date()),
                        resourceKeys: todayBuilt.resourceKeys, title: todayBuilt.effect.title
                    ))
                    _ = try? openedStore.acknowledge(SyncAcknowledgement(
                        mutationId: todayMutationId, fingerprint: todayBuilt.fingerprint, outcome: .accepted,
                        snapshotJSON: uitestSnapshotJSON(id: todayTaskId, revision: 1, title: todayBuilt.effect.title)
                    ))
                    if let planBuilt = try? OutboundCommands.planForToday(
                        true, taskId: todayTaskId,
                        basis: .init(baseTitle: todayBuilt.effect.title, baseNotes: "", expectedRevision: 1),
                        mutationId: UUID().uuidString
                    ) {
                        _ = try? openedStore.acceptMutation(LocalMutation(
                            mutationId: planBuilt.mutationId, taskId: planBuilt.taskId, commandBytes: planBuilt.commandBytes,
                            fingerprint: planBuilt.fingerprint, acceptedAt: ISO8601DateFormatter().string(from: Date()),
                            resourceKeys: planBuilt.resourceKeys, title: planBuilt.effect.title,
                            effect: LocalMutation.ProjectionEffect(notes: planBuilt.effect.notes, completedAt: nil, trashedAt: nil, planned: true)
                        ))
                        _ = try? openedStore.acknowledge(SyncAcknowledgement(
                            mutationId: planBuilt.mutationId, fingerprint: planBuilt.fingerprint, outcome: .accepted,
                            snapshotJSON: uitestSnapshotJSON(id: todayTaskId, revision: 2, title: planBuilt.effect.title)
                        ))
                    }
                }
                await builtFacade.refresh()
                // The bottom accessory reads `facade.syncPresentation`
                // (a SEPARATE published value from `items`, per D-41 --
                // never auto-derived from a per-task conflict) -- setting
                // it explicitly here is this fixture hook's job, exactly
                // as `KEEPLING_UITEST_SYNC_STATE` does for every other
                // accessory-driven UI test in this codebase; the real
                // production wiring from a live conflict into this same
                // value is 04-10-SUMMARY.md's own disclosed remaining gap
                // (`runSyncPass` -> `updateSyncPresentation`), not
                // something this test-only hook can or should fill in.
                await builtFacade.updateSyncPresentation(.conflict(affectedCount: 1))
            }
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
        #endif // DEBUG -- 04-14-PLAN.md Task 1 (T-04-14-01)

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

#if DEBUG
/// 04-14-PLAN.md Task 2: builds a valid `snapshotJSON` value via
/// `JSONSerialization` rather than hand-interpolating a string literal (the
/// established pattern every OTHER seed hook in this file uses) --
/// hand-interpolation is unsafe for the long-text fixture specifically,
/// since an arbitrary Unicode title could itself contain an unescaped `"`
/// or `\` and silently corrupt the surrounding hand-built JSON.
private func uitestSnapshotJSON(id: String, revision: Int, title: String) -> String {
    let object: [String: Any] = ["id": id, "revision": revision, "title": title]
    guard let data = try? JSONSerialization.data(withJSONObject: object),
          let json = String(data: data, encoding: .utf8) else {
        return "{\"id\":\"\(id)\",\"revision\":\(revision)}"
    }
    return json
}
#endif
