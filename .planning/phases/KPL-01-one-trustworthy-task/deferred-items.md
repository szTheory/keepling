# Deferred Items

## KPL-01-20

- `apps/web/src/features/lists/TaskList.tsx:190` — repository-wide ESLint reports the pre-existing `react-hooks/set-state-in-effect` violation. The file was unchanged by this plan; changed-file lint and the complete Phase 1 gate pass.
- `apps/web/src/features/lists/TrashList.tsx:91` — repository-wide ESLint reports the pre-existing `react-hooks/set-state-in-effect` violation. The file was unchanged by this plan; changed-file lint and the complete Phase 1 gate pass.

## KPL-01-25

- `apps/web/src/app/AuthProvider.tsx:259` — repository-wide ESLint reports the pre-existing `react-refresh/only-export-components` violation (plus an obsolete adjacent disable warning). Plan 25 did not modify this module.
- `apps/web/src/features/lists/TaskList.tsx:224` and `apps/web/src/features/lists/TrashList.tsx:91` — repository-wide ESLint continues to report the previously recorded `react-hooks/set-state-in-effect` violations. Plan 25 did not introduce either effect pattern.
