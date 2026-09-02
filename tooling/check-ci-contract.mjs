#!/usr/bin/env node

import { accessSync, constants, readFileSync } from "node:fs";
import { spawnSync } from "node:child_process";
import { fileURLToPath } from "node:url";
import path from "node:path";

const repositoryRoot = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "..");
const requiredLanes = [
  "repository-integrity",
  "server",
  "sync-property",
  "contracts-compatibility",
  "image-compose-deploy",
  "backup-restore",
  "opentofu-host-fixtures",
  "privacy",
  "live-host-dns-acceptance",
];

function fail(message) {
  console.error(`CI contract check failed: ${message}`);
  process.exit(1);
}

function executable(relativePath) {
  const absolutePath = path.join(repositoryRoot, relativePath);
  try {
    accessSync(absolutePath, constants.R_OK | constants.X_OK);
  } catch {
    fail(`${relativePath} is missing or not executable`);
  }
  return absolutePath;
}

const runnerPath = executable("tooling/test-phase-2.sh");
const privacyPath = executable("tooling/verify-privacy.sh");

const listed = spawnSync(runnerPath, ["--list"], {
  cwd: repositoryRoot,
  encoding: "utf8",
});
if (listed.status !== 0) fail("Phase 2 lane listing failed");

const laneNames = listed.stdout
  .trim()
  .split("\n")
  .filter(Boolean)
  .map((line) => line.trim().split(/\s+/, 1)[0]);
if (JSON.stringify(laneNames) !== JSON.stringify(requiredLanes)) {
  fail(`lane inventory drifted: ${laneNames.join(",")}`);
}

const runnerSource = readFileSync(runnerPath, "utf8");
for (const marker of [
  "command=",
  "cases=",
  "elapsed_ms=",
  "inputs_sha256=",
  "seed=",
  "LIVE_ACCEPTANCE_STATUS=NON_PASSING",
  ".planning/phases/KPL-02-synchronization-and-replaceable-server/deferred-items.md",
]) {
  if (!runnerSource.includes(marker)) fail(`Phase 2 runner omits ${marker}`);
}

if (!runnerSource.includes('if [ "$case_count" -le 0 ]')) {
  fail("Phase 2 runner does not reject zero-work lanes");
}

const privacySelfTest = spawnSync(privacyPath, ["--self-test"], {
  cwd: repositoryRoot,
  encoding: "utf8",
});
if (privacySelfTest.status !== 0) fail("privacy verifier self-test failed");

const requiredWorkflowPath = path.join(
  repositoryRoot,
  ".github/workflows/repository-integrity.yml",
);
const recoveryWorkflowPath = path.join(
  repositoryRoot,
  ".github/workflows/recovery-drills.yml",
);
let requiredWorkflow;
let recoveryWorkflow;
try {
  requiredWorkflow = readFileSync(requiredWorkflowPath, "utf8");
  recoveryWorkflow = readFileSync(recoveryWorkflowPath, "utf8");
} catch {
  fail("required or scheduled workflow is missing");
}

for (const lane of requiredLanes.slice(0, -1)) {
  if (!requiredWorkflow.includes(`--lane ${lane}`) && !requiredWorkflow.includes("matrix.lane")) {
    fail(`required workflow omits exact ${lane} lane command`);
  }
}
for (const lane of ["server", "sync-property", "contracts-compatibility", "backup-restore", "privacy"]) {
  if (!requiredWorkflow.includes(lane)) fail(`required matrix omits ${lane}`);
}

if (!requiredWorkflow.includes("pull_request:") || !requiredWorkflow.includes("push:")) {
  fail("required jobs do not fan out on every repository change");
}
if (requiredWorkflow.includes("paths-ignore:") || requiredWorkflow.includes("paths:")) {
  fail("shared-input fan-out is narrowed by a path filter");
}

for (const [name, source] of [
  ["required", requiredWorkflow],
  ["recovery", recoveryWorkflow],
]) {
  for (const line of source.split("\n").filter((value) => value.includes("uses:"))) {
    if (!/@[0-9a-f]{40}(?:\s|#|$)/.test(line)) {
      fail(`${name} workflow contains an action that is not pinned by full commit SHA`);
    }
  }
  if (/continue-on-error\s*:|max-attempts\s*:|\bretry\s*:/i.test(source)) {
    fail(`${name} workflow contains blind retry or ignored-failure behavior`);
  }
}

for (const marker of [
  "tooling/runtime-versions.env",
  "apps/server/mix.lock",
  "pnpm-lock.yaml",
  "actions/cache@0400d5f644dc74513175e3cd8d07132dd4860809",
  "actions/upload-artifact@ea165f8d65b6e75b540449e92b4886f43607fa02",
  "-timing",
  "if-no-files-found: error",
  "no-retry; quarantine-requires-owner-issue-expiry",
]) {
  if (!requiredWorkflow.includes(marker)) fail(`required workflow omits ${marker}`);
}

for (const marker of [
  'cron: "15 5 * * *"',
  'cron: "45 5 * * 0"',
  'cron: "30 6 1 1,4,7,10 *"',
  "environment: recovery-protected",
  "environment: recovery-live",
  "missing_protected_credentials",
  "result:\"NON_PASSING\"",
  "exit 1",
  "KEEPLING_RESTORE_SEED",
  "change_trigger",
  "attempts:0",
  "dns_reached:false",
  "verify-privacy.sh",
]) {
  if (!recoveryWorkflow.includes(marker)) fail(`recovery workflow omits ${marker}`);
}

console.log(
  `CI contract passed: lanes=${requiredLanes.length} pins=full-sha caches=exact scheduled=non-vacuous privacy_self_test=passed`,
);
