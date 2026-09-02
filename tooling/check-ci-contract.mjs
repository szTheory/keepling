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

console.log(
  `CI local contract passed: lanes=${requiredLanes.length} anti_vacuity=required privacy_self_test=passed`,
);
