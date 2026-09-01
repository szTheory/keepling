---
phase: "01"
name: "one-trustworthy-task"
created: 2026-08-31
status: pending
---

# Phase 1: one-trustworthy-task — User Acceptance Testing

## Test Results

| # | Test | Status | Notes |
|---|------|--------|-------|
| 1 | VoiceOver and keyboard continuity | pending | Exercise the complete daily and recovery loop without a pointer. |
| 2 | Perceptual and reflow matrix | pending | Review all specified widths/themes/modes, including the 1024px scrollbar check. |
| 3 | Password-manager and OS recovery | pending | Exercise real AutoFill/paste/recovery and authentication-expiry behavior. |

### 1. VoiceOver and keyboard continuity

Use keyboard and VoiceOver to traverse capture, validation, conflict resolution, authentication expiry, uncertain delivery, pagination, lifecycle changes, undo, and Sessions.

Expected: announcements are concise, focus is predictable, drafts and route context survive recovery, and every recovery control is reachable.

### 2. Perceptual and reflow matrix

Review the UI at 320, 768, 1024, 1064, and 1440px in light and dark themes, at 200% zoom, with forced colors, and with Reduce Motion. Explicitly inspect Inbox at 1024px for a horizontal scrollbar.

Expected: the interface remains calm and readable, focus is visible, nothing clips, there is no page-level horizontal overflow, and motion is not required for correctness.

### 3. Password-manager and OS recovery

Use a real password manager to test login, reveal, paste/AutoFill, one-use recovery, and authentication expiry both before and after submitting a task change.

Expected: credentials remain private and the original route, draft, request bytes, and mutation identity resume without ambiguous replay.

## Summary

- Passed: 0
- Issues: 0
- Pending: 3

Automated verification is complete at 74/74 must-haves, 13/13 Phase 1 requirements, 109 ExUnit tests, 147 Vitest tests, and 25 Playwright tests. This phase remains `human_needed` until all three tests above are recorded.
