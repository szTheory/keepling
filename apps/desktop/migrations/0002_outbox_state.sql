-- 0002: explicit outbox transmission state (O-51, D-52).
--
-- WHY THIS EXISTS
--
-- Undo of a mutation the server never received may drop that mutation from
-- the outbox, because bytes that never left this Mac have nothing to
-- reconcile with. Undo of a mutation the server HAS seen may not: dropping
-- it would leave the server holding a command this client deleted, which is
-- the divergence the whole phase has been removing.
--
-- `outbox` was `(mutation_id, sequence)` and could not tell those apart. A
-- row sits there unchanged while its POST is in flight, so "still in the
-- outbox" is NOT evidence that a command was never transmitted. This column
-- is that evidence, and nothing else in the schema can stand in for it.
--
-- THE VOCABULARY, AND WHY EACH VALUE EXISTS
--
--   queued     The bytes have never been handed to the transport. This is
--              the ONLY state an undo may drop.
--   in_flight  The bytes have been handed to the transport in this process
--              and no outcome is known yet. Not droppable, and not
--              re-selected for push while a request is live.
--   uncertain  The bytes were handed to the transport and no outcome ever
--              arrived -- a transport failure, or a process that ended
--              while the row was in_flight. Not droppable, but still
--              pushable: a retransmission carries the SAME immutable bytes
--              under the same mutation identity and fingerprint, and the
--              server answers `already_satisfied` if the first attempt
--              landed. Retransmitting is safe; dropping is not.
--
-- The transitions are deliberately MONOTONIC. A row that leaves `queued`
-- never returns to it, not even when the transport fails: `fetch` rejecting
-- cannot distinguish "the request never left" from "it left and the answer
-- was lost" (O-47), so a transport failure is ambiguous, and ambiguity is a
-- refusal rather than an assumed `queued`. That one-way rule is what makes
-- the drop provably safe rather than probably safe.
--
-- EXISTING ROWS BECOME `uncertain`, NOT `queued`
--
-- The column DEFAULT is `queued` so commands enqueued from here on start in
-- the only state that describes them. But every row that ALREADY exists in
-- a database written before this migration was enqueued by a client that
-- did not record transmission state, so its history is unknown -- it may
-- have been pushed and its answer lost. Absent state is ambiguous state,
-- and the rule above admits no exception for age, so the UPDATE below moves
-- pre-existing rows to `uncertain`. They keep their exact bytes, their
-- sequence and their place in the queue; they are still pushed; only undo
-- refuses them.
--
-- The table is ALTERed, never dropped and recreated: a queued command from
-- an existing install is a person's unsent work.

ALTER TABLE outbox
  ADD COLUMN state TEXT NOT NULL DEFAULT 'queued'
  CHECK (state IN ('queued', 'in_flight', 'uncertain'));

UPDATE outbox SET state = 'uncertain';
