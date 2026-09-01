# Deferred Items

- `mix deps.get --check-locked` reports existing security advisories for transitive `hackney 1.25.0` (including CVE-2026-47071). Plan 02-01 adds only test-scoped `stream_data 1.4.0`; changing the existing `tzdata`/`hackney` dependency path is outside this plan and requires separate dependency review.
