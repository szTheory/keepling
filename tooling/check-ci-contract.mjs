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
const desktopWorkflowPath = path.join(
  repositoryRoot,
  ".github/workflows/desktop.yml",
);
const recoveryWorkflowPath = path.join(
  repositoryRoot,
  ".github/workflows/recovery-drills.yml",
);
let requiredWorkflow;
let desktopWorkflow;
let recoveryWorkflow;
try {
  requiredWorkflow = readFileSync(requiredWorkflowPath, "utf8");
  desktopWorkflow = readFileSync(desktopWorkflowPath, "utf8");
  recoveryWorkflow = readFileSync(recoveryWorkflowPath, "utf8");
} catch {
  fail("required, desktop, or scheduled workflow is missing");
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

// D-15(a)/(b): a skipped required job reads to GitHub branch protection as
// satisfied, indistinguishable from a passing one. The only required check
// must be a single aggregator (`all-required-passed`) that explicitly
// asserts every dependency's result -- so an `if:` on any OTHER required
// job (which can make that job report "skipped" instead of "success" or
// "failure") is banned outright. The aggregator itself is the sole
// exception: it MUST carry `if: always()` so it still runs -- and can still
// fail the check -- when an upstream job fails.
const AGGREGATOR_JOB_NAME = "all-required-passed";
const jobsBlockStart = requiredWorkflow.indexOf("\njobs:");
if (jobsBlockStart === -1) fail("required workflow has no jobs: block");
const jobsSource = requiredWorkflow.slice(jobsBlockStart);
const jobBlocks = jobsSource.split(/\n(?=  [A-Za-z0-9_-]+:\n)/).filter((block) => /^\n {2}[A-Za-z0-9_-]+:\n/.test(block) || /^ {2}[A-Za-z0-9_-]+:\n/.test(block));
let foundAggregator = false;
for (const block of jobBlocks) {
  const jobNameMatch = block.match(/^\n? {2}([A-Za-z0-9_-]+):/);
  const jobName = jobNameMatch ? jobNameMatch[1] : "unknown";
  if (jobName === AGGREGATOR_JOB_NAME) {
    foundAggregator = true;
    if (!/\n {4}if:\s*always\(\)/.test(block)) {
      fail(`${AGGREGATOR_JOB_NAME} must carry an if: always() job-level key`);
    }
    if (!block.includes("needs")) fail(`${AGGREGATOR_JOB_NAME} must reference the needs context`);
    continue;
  }
  if (/\n {4}if:\s*/.test(block)) {
    fail(`required job ${jobName} carries a job-level if: key -- a skipped required job must never read as satisfied`);
  }
}
if (!foundAggregator) fail(`required workflow is missing the ${AGGREGATOR_JOB_NAME} aggregator job`);

// Caching stays available to test-only lanes; an artifact-producing job
// restoring a cache could serve stale bytes as if they were freshly built.
const ARTIFACT_PRODUCING_JOB_NAMES = ["ci-contract", "image-compose-deploy"];
for (const block of jobBlocks) {
  const jobNameMatch = block.match(/^\n? {2}([A-Za-z0-9_-]+):/);
  const jobName = jobNameMatch ? jobNameMatch[1] : "unknown";
  if (ARTIFACT_PRODUCING_JOB_NAMES.includes(jobName) && block.includes("actions/cache")) {
    fail(`artifact-producing job ${jobName} must not restore a cache`);
  }
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

for (const marker of [
  "signing-available: ${{ steps.signing.outputs.available }}",
  "Require signing for main-branch upgrade evidence",
  "Select the previous successful main package build",
  "id: previous\n        if: github.event_name == 'push'",
  "actions/workflows/desktop.yml/runs",
  "const apiBase = (process.env.GITHUB_API_URL ?? '').replace(/\\/+$/, '')",
  "endpoint.searchParams.set('branch', 'main')",
  "endpoint.searchParams.set('event', 'push')",
  "endpoint.searchParams.set('exclude_pull_requests', 'true')",
  "endpoint.searchParams.set('status', 'success')",
  "run.head_sha !== process.env.CURRENT_SOURCE_REVISION",
  "Authorization: `Bearer ${process.env.GITHUB_TOKEN}`",
  "X-GitHub-Api-Version': '2026-03-10'",
  "run-id: ${{ steps.previous.outputs.run-id }}",
  "Prove credential and namespace continuity across signed packaged builds",
  "node tooling/verify-desktop-upgrade-continuity.mjs",
  "name: kpl03-signed-upgrade-continuity",
  "actions: read",
]) {
  if (!desktopWorkflow.includes(marker)) {
    fail(`desktop workflow omits signed-upgrade continuity contract marker: ${marker}`);
  }
}
if (!desktopWorkflow.includes("if: github.event_name == 'push'")) {
  fail("signed-upgrade continuity must be restricted to main pushes where signing secrets are available");
}
if (!/desktop-promote:\n\s+needs: \[[^\]]*desktop-packaged/.test(desktopWorkflow)) {
  fail("desktop promotion must remain gated on the packaged job that runs upgrade continuity");
}

const upgradeRunnerPath = path.join(repositoryRoot, "tooling/verify-desktop-upgrade-continuity.mjs");
const upgradeTestPath = path.join(repositoryRoot, "apps/desktop/test/packaged-upgrade/continuity.spec.ts");
let upgradeRunner;
let upgradeTest;
try {
  upgradeRunner = readFileSync(upgradeRunnerPath, "utf8");
  upgradeTest = readFileSync(upgradeTestPath, "utf8");
} catch {
  fail("signed-upgrade continuity runner or packaged test is missing");
}
for (const marker of [
  "developerIdSigned !== true",
  'status !== \'Accepted\'',
  "stapled !== true",
  "stapledArchiveDigestSha256",
  "stapler",
  "codesign",
  "spctl",
  "previous.designatedRequirement !== current.designatedRequirement",
  "KEEPLING_PREVIOUS_PACKAGE_MANIFEST",
]) {
  if (!upgradeRunner.includes(marker)) {
    fail(`signed-upgrade runner omits fail-closed package evidence marker: ${marker}`);
  }
}
for (const marker of [
  "synthetic:access:kpl03-upgrade",
  "synthetic:refresh:kpl03-upgrade",
  "BrowserDelegatedAuthorization",
  "KeeplingSyncAdapter",
  "const serverResponse =",
  "handleCallback",
  "outcome.kind !== 'authorized'",
  "server_instance",
  "__keeplingTestCredentials",
  "activateNamespace",
  "readNamespaceBinding",
  "encryptedCredential.includes",
]) {
  if (!upgradeTest.includes(marker)) {
    fail(`packaged-upgrade test omits continuity/privacy marker: ${marker}`);
  }
}
if (upgradeTest.includes("secrets.")) {
  fail("packaged-upgrade test must not read or depend on real credential secrets");
}

console.log(
  `CI contract passed: lanes=${requiredLanes.length} pins=full-sha caches=exact scheduled=non-vacuous desktop_upgrade=main-only privacy_self_test=passed`,
);
