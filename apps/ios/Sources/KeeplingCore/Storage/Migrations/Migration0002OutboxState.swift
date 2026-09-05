import Foundation

/// Mirrors `apps/desktop/migrations/0002_outbox_state.sql` verbatim
/// (04-PATTERNS.md "exact (same monotonic 3-state outbox column)"): the
/// explicit outbox transmission state that lets undo distinguish "never
/// transmitted" (droppable) from "transmitted or uncertain" (not
/// droppable, but safely retransmittable because a retry carries the same
/// immutable bytes under the same mutation identity and fingerprint).
enum Migration0002OutboxState {
    static let version = 2

    static let sql = """
    -- WHY THIS EXISTS
    --   queued     The bytes have never been handed to the transport. This is
    --              the ONLY state an undo may drop.
    --   in_flight  The bytes have been handed to the transport in this process
    --              and no outcome is known yet. Not droppable, and not
    --              re-selected for push while a request is live.
    --   uncertain  The bytes were handed to the transport and no outcome ever
    --              arrived -- a transport failure, or a process that ended
    --              while the row was in_flight. Not droppable, but still
    --              pushable: a retransmission carries the SAME immutable
    --              bytes under the same mutation identity and fingerprint,
    --              and the server answers `already_satisfied` if the first
    --              attempt landed. Retransmitting is safe; dropping is not.
    --
    -- The transitions are deliberately MONOTONIC. A row that leaves `queued`
    -- never returns to it, not even when the transport fails: a transport
    -- failure cannot distinguish "the request never left" from "it left and
    -- the answer was lost", so a transport failure is ambiguous, and
    -- ambiguity is a refusal rather than an assumed `queued`.
    ALTER TABLE outbox
      ADD COLUMN state TEXT NOT NULL DEFAULT 'queued'
      CHECK (state IN ('queued', 'in_flight', 'uncertain'));

    UPDATE outbox SET state = 'uncertain';
    """
}
