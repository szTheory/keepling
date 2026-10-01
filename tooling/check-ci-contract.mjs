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

for (const [name, args] of [
  ["PR impact classifier", ["tooling/classify-pr-impact.mjs", "--self-test"]],
  ["CI result summary", ["tooling/check-ci-results.mjs", "--self-test"]],
]) {
  const selfTest = spawnSync(process.execPath, args, {
    cwd: repositoryRoot,
    encoding: "utf8",
  });
  if (selfTest.status !== 0) {
    fail(`${name} self-test failed: ${selfTest.stderr || selfTest.stdout}`);
  }
}

const summaryCliSelfTest = spawnSync(process.execPath, [
  "tooling/check-ci-results.mjs",
  "--impact-job=pr-impact",
  "--always=cheap",
  "--conditional=heavy",
], {
  cwd: repositoryRoot,
  encoding: "utf8",
  env: {
    ...process.env,
    NEEDS_CONTEXT: JSON.stringify({
      "pr-impact": { result: "success", outputs: { run_heavy: "true" } },
      cheap: { result: "success" },
      heavy: { result: "success" },
    }),
  },
});
if (summaryCliSelfTest.status !== 0) {
  fail(`CI result summary CLI self-test failed: ${summaryCliSelfTest.stderr || summaryCliSelfTest.stdout}`);
}

const requiredWorkflowPath = path.join(
  repositoryRoot,
  ".github/workflows/repository-integrity.yml",
);
const desktopWorkflowPath = path.join(repositoryRoot, ".github/workflows/desktop.yml");
const iosWorkflowPath = path.join(repositoryRoot, ".github/workflows/ios.yml");
const recoveryWorkflowPath = path.join(
  repositoryRoot,
  ".github/workflows/recovery-drills.yml",
);
let requiredWorkflow;
let desktopWorkflow;
let iosWorkflow;
let recoveryWorkflow;
try {
  requiredWorkflow = readFileSync(requiredWorkflowPath, "utf8");
  desktopWorkflow = readFileSync(desktopWorkflowPath, "utf8");
  iosWorkflow = readFileSync(iosWorkflowPath, "utf8");
  recoveryWorkflow = readFileSync(recoveryWorkflowPath, "utf8");
} catch {
  fail("required, desktop, iOS, or scheduled workflow is missing");
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

// A skipped job reads to GitHub branch protection as satisfied. Only the
// fail-closed impact gates may skip expensive lanes, and each workflow's
// always-run summary must prove the skip was caused by the docs-only classifier.
const AGGREGATOR_JOB_NAME = "all-required-passed";
const IMPACT_GATE = "always() && (needs.pr-impact.result != 'success' || needs.pr-impact.outputs.run_heavy != 'false')";
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
  if (["phase2-linux", "phase2-runtime", "phase2-verified-image", "image-compose-deploy"].includes(jobName)) {
    const normalized = block.replace(/\s+/g, " ");
    if (!block.includes("needs: [pr-impact]")) {
      fail(`required job ${jobName} must depend on pr-impact`);
    }
    if (!normalized.includes(IMPACT_GATE)) {
      fail(`required job ${jobName} must run full checks unless docs-only impact succeeded`);
    }
    continue;
  }
  if (/\n {4}if:\s*/.test(block)) {
    fail(`required job ${jobName} carries a job-level if: key -- a skipped required job must never read as satisfied`);
  }
}
if (!foundAggregator) fail(`required workflow is missing the ${AGGREGATOR_JOB_NAME} aggregator job`);

function workflowJobBlock(workflow, name) {
  const start = workflow.indexOf(`\n  ${name}:\n`);
  if (start < 0) return "";
  const rest = workflow.slice(start);
  const nextJob = rest.slice(1).search(/\n  [A-Za-z0-9_-]+:\n/);
  return nextJob < 0 ? rest : rest.slice(0, nextJob + 1);
}

function workflowNamedStepBlocks(workflow, jobName, stepName) {
  const job = workflowJobBlock(workflow, jobName);
  if (!job) return [];
  const lines = job.split(/\r?\n/);
  const blocks = [];
  for (let start = 0; start < lines.length; start += 1) {
    const match = lines[start].match(/^ {6}- name: (.*)$/);
    if (!match || match[1].trim() !== stepName) continue;
    let end = start + 1;
    while (end < lines.length && !/^ {6}- /.test(lines[end])) end += 1;
    blocks.push(lines.slice(start, end).join("\n"));
  }
  return blocks;
}

function workflowStepRunLines(stepBlock) {
  if (!stepBlock) return [];
  const lines = stepBlock.split(/\r?\n/);
  const runStart = lines.findIndex((line) => /^ {8}run:\s*\|\s*$/.test(line));
  if (runStart < 0) return [];
  const commands = [];
  for (const line of lines.slice(runStart + 1)) {
    if (!line.trim()) continue;
    if (!/^ {10}\S/.test(line)) break;
    commands.push(line.slice(10).trimEnd());
  }
  return commands;
}

function dependabotPolicyWorkflowProblem(workflow) {
  const job = workflowJobBlock(workflow, "ci-contract");
  if (!job) return "ci-contract job is missing";
  if (/^ {4}continue-on-error\s*:/m.test(job)) {
    return "ci-contract job must propagate policy-check failures";
  }

  const steps = workflowNamedStepBlocks(
    workflow,
    "ci-contract",
    "Validate bounded Dependabot update policy",
  );
  if (steps.length !== 1) return "ci-contract must contain exactly one Dependabot policy step";
  const [step] = steps;
  if (/^ {8}if\s*:/m.test(step)) return "Dependabot policy step must run unconditionally";
  if (/^ {8}continue-on-error\s*:/m.test(step)) {
    return "Dependabot policy step must propagate command failures";
  }
  if (!/^ {8}shell:\s*bash\s*$/m.test(step)) {
    return "Dependabot policy step must use bash failure propagation";
  }

  const commands = workflowStepRunLines(step);
  for (const command of [
    "ruby tooling/check-dependabot-config.rb --self-test",
    "ruby tooling/check-dependabot-config.rb",
  ]) {
    if (!commands.includes(command)) return `ci-contract must execute ${command} in its Dependabot policy step`;
  }
  return "";
}

const dependabotPolicyProblem = dependabotPolicyWorkflowProblem(requiredWorkflow);
if (dependabotPolicyProblem) fail(dependabotPolicyProblem);

const commentOnlyDependabotStep = [
  "jobs:",
  "  ci-contract:",
  "    steps:",
  "      # - name: Validate bounded Dependabot update policy",
  "      #   run: |",
  "      #     ruby tooling/check-dependabot-config.rb --self-test",
].join("\n");
if (workflowNamedStepBlocks(
  commentOnlyDependabotStep,
  "ci-contract",
  "Validate bounded Dependabot update policy",
).length !== 0) {
  fail("Dependabot policy workflow contract must ignore comments");
}

const conditionalDependabotPolicyStep = requiredWorkflow.replace(
  "      - name: Validate bounded Dependabot update policy\n        shell: bash\n",
  "      - name: Validate bounded Dependabot update policy\n        if: false\n        shell: bash\n",
);
if (!dependabotPolicyWorkflowProblem(conditionalDependabotPolicyStep).includes("unconditionally")) {
  fail("Dependabot policy mutation self-test did not reject a conditional step");
}
const nonBlockingDependabotPolicyStep = requiredWorkflow.replace(
  "      - name: Validate bounded Dependabot update policy\n        shell: bash\n",
  "      - name: Validate bounded Dependabot update policy\n        continue-on-error: true\n        shell: bash\n",
);
if (!dependabotPolicyWorkflowProblem(nonBlockingDependabotPolicyStep).includes("propagate command failures")) {
  fail("Dependabot policy mutation self-test did not reject continue-on-error");
}
const nonBlockingCiContractJob = requiredWorkflow.replace(
  "  ci-contract:\n",
  "  ci-contract:\n    continue-on-error: true\n",
);
if (!dependabotPolicyWorkflowProblem(nonBlockingCiContractJob).includes("propagate policy-check failures")) {
  fail("Dependabot policy mutation self-test did not reject a non-blocking ci-contract job");
}
const duplicateDependabotPolicyStep = requiredWorkflow.replace(
  "      # The release manifest for a revision is NOT written here.",
  "      - name: Validate bounded Dependabot update policy\n        shell: bash\n        run: |\n          ruby tooling/check-dependabot-config.rb --self-test\n          ruby tooling/check-dependabot-config.rb\n      # The release manifest for a revision is NOT written here.",
);
if (!dependabotPolicyWorkflowProblem(duplicateDependabotPolicyStep).includes("exactly one")) {
  fail("Dependabot policy mutation self-test did not reject duplicate steps");
}

function impactWorkflowProblem(workflow, {
  name,
  conditionalJobs,
  summaryConditionalJobs = conditionalJobs,
  summaryJob,
  summaryName,
}) {
  const trigger = workflow.slice(0, workflow.indexOf("\njobs:"));
  if (!trigger.includes("pull_request:") || !trigger.includes("push:")) {
    return `${name} workflow must run on pull requests and main pushes`;
  }
  if (/^\s{2}paths(?:-ignore)?\s*:/m.test(trigger)) {
    return `${name} workflow triggers must remain unfiltered`;
  }

  const classifier = workflowJobBlock(workflow, "pr-impact");
  if (!classifier.includes("pull-requests: read") || !classifier.includes("classify-pr-impact.mjs")) {
    return `${name} workflow must classify PR paths with read-only pull request access`;
  }

  for (const jobName of conditionalJobs) {
    const block = workflowJobBlock(workflow, jobName);
    const normalized = block.replace(/\s+/g, " ");
    if (!block.includes("needs: [pr-impact") || !normalized.includes(IMPACT_GATE)) {
      return `${name} job ${jobName} must run unless a successful classifier proves docs-only impact`;
    }
  }

  const summary = workflowJobBlock(workflow, summaryJob);
  if (
    !summary.includes(`name: ${summaryName}`) ||
    !/\n {4}if:\s*always\(\)/.test(summary) ||
    !summary.includes("check-ci-results.mjs") ||
    !summary.includes("needs:") ||
    !summary.includes("pr-impact")
  ) {
    return `${name} workflow is missing its always-run fail-closed summary check (${summaryName})`;
  }
  for (const jobName of summaryConditionalJobs) {
    if (!summary.includes(jobName)) return `${summaryJob} must account for ${jobName}`;
  }
  return "";
}

const impactWorkflowProblems = [
  impactWorkflowProblem(requiredWorkflow, {
    name: "repository-integrity",
    conditionalJobs: ["phase2-linux", "phase2-runtime", "phase2-verified-image", "image-compose-deploy"],
    summaryJob: "all-required-passed",
    summaryName: "All required checks passed",
  }),
  impactWorkflowProblem(desktopWorkflow, {
    name: "desktop",
    conditionalJobs: ["desktop-units", "desktop-package", "desktop-packaged", "desktop-e2e", "desktop-macos-integration", "mcp-phase-non-model"],
    summaryConditionalJobs: ["desktop-units", "desktop-package", "desktop-packaged", "desktop-e2e", "desktop-macos-integration", "mcp-phase-non-model", "desktop-promote"],
    summaryJob: "desktop-required",
    summaryName: "Desktop checks passed",
  }),
  impactWorkflowProblem(iosWorkflow, {
    name: "iOS",
    conditionalJobs: ["ios-simulator"],
    summaryJob: "ios-required-passed",
    summaryName: "iOS simulator checks passed",
  }),
].filter(Boolean);
for (const problem of impactWorkflowProblems) fail(problem);

const ungatedRequiredWorkflow = requiredWorkflow.replace(IMPACT_GATE, "always()");
if (
  !impactWorkflowProblem(ungatedRequiredWorkflow, {
    name: "repository-integrity",
    conditionalJobs: ["phase2-linux", "phase2-runtime", "phase2-verified-image", "image-compose-deploy"],
    summaryJob: "all-required-passed",
    summaryName: "All required checks passed",
  }).includes("phase2-linux")
) {
  fail("impact-gate mutation self-test did not reject an ungated expensive lane");
}

const missingDesktopSummary = desktopWorkflow.replace(
  "name: Desktop checks passed",
  "name: Desktop summary renamed",
);
if (
  !impactWorkflowProblem(missingDesktopSummary, {
    name: "desktop",
    conditionalJobs: ["desktop-units", "desktop-package", "desktop-packaged", "desktop-e2e", "desktop-macos-integration", "mcp-phase-non-model"],
    summaryConditionalJobs: ["desktop-units", "desktop-package", "desktop-packaged", "desktop-e2e", "desktop-macos-integration", "mcp-phase-non-model", "desktop-promote"],
    summaryJob: "desktop-required",
    summaryName: "Desktop checks passed",
  }).includes("always-run fail-closed summary")
) {
  fail("desktop summary mutation self-test did not reject a missing required context");
}

const desktopPromotion = workflowJobBlock(desktopWorkflow, "desktop-promote").replace(/\s+/g, " ");
for (const marker of [
  "needs: [pr-impact, desktop-units, desktop-package, desktop-packaged, desktop-e2e, desktop-macos-integration, mcp-phase-non-model]",
  "needs.pr-impact.result == 'success'",
  "needs.pr-impact.outputs.run_heavy != 'false'",
  "needs.desktop-units.result == 'success'",
  "needs.desktop-package.result == 'success'",
  "needs.desktop-packaged.result == 'success'",
  "needs.desktop-e2e.result == 'success'",
  "needs.desktop-macos-integration.result == 'success'",
  "needs.mcp-phase-non-model.result == 'success'",
]) {
  if (!desktopPromotion.includes(marker)) {
    fail(`desktop promotion must remain success-gated: missing ${marker}`);
  }
}

function gateBJobBlock(workflow) {
  return workflowJobBlock(workflow, "image-compose-deploy");
}

function gateBWorkflowProblem(workflow) {
  const block = gateBJobBlock(workflow);
  if (!block) return "required image-compose-deploy job is missing";
  for (const marker of [
    "runs-on: ubuntu-24.04",
    "KEEPLING_IMAGE_PLATFORM: linux/amd64",
    'tooling/verify-phase-2-gate-b.sh "$RUNNER_TEMP/phase-2-gate-b.json"',
    "actions/upload-artifact@ea165f8d65b6e75b540449e92b4886f43607fa02",
    "name: phase-2-gate-b-route-evidence",
    "path: ${{ runner.temp }}/phase-2-gate-b.json",
    "if-no-files-found: error",
  ]) {
    if (!block.includes(marker)) return `image-compose-deploy omits required Gate B route marker: ${marker}`;
  }
  if (!workflow.includes("permissions:\n  contents: read")) {
    return "repository-integrity workflow must grant only read-only contents permission";
  }
  if (/actions\/cache|\bcache\s*:|--cache(?:-from|-to)?\b/.test(block)) {
    return "image-compose-deploy must not restore or write build caches";
  }
  if (/secrets\.|(?:^|\s)(?:ssh|tofu|terraform|hcloud|cloudflare)(?:\s|$)/i.test(block)) {
    return "image-compose-deploy must not access protected credentials or infrastructure";
  }
  if (/^\s{4}continue-on-error\s*:/m.test(block)) {
    return "image-compose-deploy must not ignore a failed route";
  }
  const normalized = block.replace(/\s+/g, " ");
  if (!block.includes("needs: [pr-impact]") || !normalized.includes(IMPACT_GATE)) {
    return "image-compose-deploy must use the fail-closed docs-only impact gate";
  }
  const uploads = block.match(/uses: actions\/upload-artifact@/g) ?? [];
  if (uploads.length !== 1) return "image-compose-deploy must upload exactly one sanitized artifact";
  const paths = block.match(/^\s+path:\s*(.*)$/gm) ?? [];
  if (paths.length !== 1 || !paths[0].includes("${{ runner.temp }}/phase-2-gate-b.json")) {
    return "image-compose-deploy upload path must be the single sanitized result file";
  }
  if (/\*|\.\.\/|(?:archive|dump|credential|manifest|log)/i.test(paths[0])) {
    return "image-compose-deploy upload path can select private material";
  }
  if (!/all-required-passed:[\s\S]*?needs:[\s\S]*?image-compose-deploy/.test(workflow)) {
    return "all-required-passed must continue requiring image-compose-deploy";
  }
  return "";
}

const gateBJobProblem = gateBWorkflowProblem(requiredWorkflow);
if (gateBJobProblem) fail(gateBJobProblem);

const withoutGateBInvocation = requiredWorkflow.replace(
  'tooling/verify-phase-2-gate-b.sh "$RUNNER_TEMP/phase-2-gate-b.json"',
  "echo route omitted",
);
if (!gateBWorkflowProblem(withoutGateBInvocation).includes("omits required Gate B route marker")) {
  fail("Gate B workflow mutation self-test did not reject a missing route invocation");
}
const widenedGateBUpload = requiredWorkflow.replace(
  "path: ${{ runner.temp }}/phase-2-gate-b.json",
  "path: ${{ runner.temp }}/**",
);
if (!gateBWorkflowProblem(widenedGateBUpload).includes("omits required Gate B route marker")) {
  fail("Gate B workflow mutation self-test did not reject an expanded artifact path");
}

const gateBScriptPath = executable("tooling/verify-phase-2-gate-b.sh");
const gateBScript = readFileSync(gateBScriptPath, "utf8");
for (const marker of [
  "git archive --format=tar",
  "HEAD^{tree}",
  "KEEPLING_BUILD_CONTEXT_ARCHIVE",
  "KEEPLING_EXPECTED_IMAGE_ID",
  "CI_ROUTE_READY",
  "source_commit_sha",
  "source_tree_sha",
  "context_tar_sha256",
  "archive_sha256",
  "manifest_digest",
  "config_image_id",
  "deployed_image_id",
  "rootfs_diff_ids_sha256",
  "synthetic_recovery",
  "verify-privacy.sh",
]) {
  if (!gateBScript.includes(marker)) fail(`Gate B chain omits source/archive/deploy/privacy evidence marker: ${marker}`);
}
if (gateBScript.includes("GATE_B_PASSED")) fail("local route readiness must not be labelled as passed Gate B acceptance");

// Caching stays available to test-only lanes; an artifact-producing job
// restoring a cache could serve stale bytes as if they were freshly built.
const ARTIFACT_PRODUCING_JOB_NAMES = ["ci-contract", "image-compose-deploy", "phase2-verified-image"];
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

const imageArtifactJob = jobBlocks.find((block) => /^\n? {2}phase2-verified-image:/.test(block));
if (!imageArtifactJob) fail("required workflow is missing the phase2-verified-image job");
for (const marker of [
  "KEEPLING_IMAGE_TAG: keepling-server:plan-02-09-amd64",
  "Export exact tested Phase 2 image and contract",
  "source_revision=$(git rev-parse HEAD)",
  "[ \"$source_revision\" = \"$GITHUB_SHA\" ]",
  "export-verified-image-archive.sh",
  "--resolve-image-archive",
  "if [ \"$archive_bytes\" -le 0 ] || [ \"$archive_bytes\" -gt 1073741824 ]; then",
  "image_manifest_digest",
  "run_attempt",
  "name: phase2-verified-image",
  "image-contract.json",
  "run-binding.json",
  "if-no-files-found: error",
  "retention-days: 14",
  "compression-level: 0",
]) {
  if (!imageArtifactJob.includes(marker)) {
    fail(`image CI artifact job omits exact tested-image binding marker: ${marker}`);
  }
}
const imageTestIndex = imageArtifactJob.indexOf("Run exact image, Compose, and deploy lane");
const exportImageIndex = imageArtifactJob.indexOf("Export exact tested Phase 2 image and contract");
const uploadImageIndex = imageArtifactJob.indexOf("name: phase2-verified-image");
if (!(imageTestIndex >= 0 && imageTestIndex < exportImageIndex && exportImageIndex < uploadImageIndex)) {
  fail("verified image artifact must be exported and uploaded only after the exact image lane");
}
if (!/all-required-passed:[\s\S]*?needs:[\s\S]*?phase2-verified-image/.test(requiredWorkflow)) {
  fail("all-required-passed must continue requiring phase2-verified-image");
}

for (const marker of [
  "tooling/runtime-versions.env",
  "apps/server/mix.lock",
  "pnpm-lock.yaml",
  "version=1.7.12",
  "actionlint_${version}_linux_amd64.tar.gz",
  "8aca8db96f1b94770f1b0d72b6dddcb1ebb8123cb3712530b08cc387b349a3d8",
  "run: actionlint -color",
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

if (
  !recoveryWorkflow.includes(
    "if: github.event_name == 'workflow_dispatch' && inputs.drill == 'host-replacement'",
  )
) {
  fail("protected host replacement must require explicit workflow_dispatch");
}
if (recoveryWorkflow.includes('cron: "30 6 1 1,4,7,10 *"')) {
  fail("protected host replacement must not run on a recurring schedule");
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
  `CI contract passed: lanes=${requiredLanes.length} pins=full-sha caches=exact scheduled=non-vacuous desktop_upgrade=main-only privacy_self_test=passed pr_impact=fail-closed dependabot_policy=required actionlint=1.7.12`,
);
