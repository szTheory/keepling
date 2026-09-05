import KeeplingCore
import SwiftUI

/// One inline per-task exception indicator (04-10-PLAN.md Task 3, D-39):
/// renders beside the affected task's own row ONLY -- never mirrored into
/// a separate global list of healthy state. Reads the SAME derived
/// `SyncPresentationSummary` the accessory and the `Sync & Recovery` sheet
/// read (D-41); this view computes no synchronization truth of its own,
/// and renders nothing at all when the summary it is handed is not an
/// actionable exception.
struct TaskExceptionRow: View {
    let summary: SyncPresentationSummary
    let taskTitle: String
    let onTap: () -> Void

    var body: some View {
        if summary.isActionableException, let copy = summary.copy {
            Button(action: onTap) {
                Text(copy)
                    .font(TokenSemantics.Typography.label)
                    .foregroundStyle(TokenSemantics.accent)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("\(copy) Open Sync & Recovery for \"\(taskTitle)\"")
            .accessibilityIdentifier("task-exception-\(taskTitle)")
        }
    }
}
