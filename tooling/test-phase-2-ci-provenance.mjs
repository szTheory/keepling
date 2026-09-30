#!/usr/bin/env node

import assert from "node:assert/strict";
import { createHash } from "node:crypto";
import { deflateRawSync } from "node:zlib";
import { verifyRunProvenance } from "./verify-phase-2-ci-provenance.mjs";

const repository = "keepling/keepling";
const sourceSha = "a".repeat(40);
const treeSha = "b".repeat(40);
const imageId = `sha256:${"c".repeat(64)}`;
const artifactName = "phase-2-gate-b-route-evidence";
const workflowPath = ".github/workflows/repository-integrity.yml";

function sha256(bytes) {
  return createHash("sha256").update(bytes).digest("hex");
}

function crc32(bytes) {
  let crc = 0xffffffff;
  for (const byte of bytes) {
    crc ^= byte;
    for (let bit = 0; bit < 8; bit += 1) crc = (crc >>> 1) ^ (crc & 1 ? 0xedb88320 : 0);
  }
  return (crc ^ 0xffffffff) >>> 0;
}

function zipOne(name, contents) {
  const filename = Buffer.from(name, "utf8");
  const input = Buffer.from(contents);
  const compressed = deflateRawSync(input);
  const checksum = crc32(input);
  const local = Buffer.alloc(30 + filename.length);
  local.writeUInt32LE(0x04034b50, 0);
  local.writeUInt16LE(20, 4);
  local.writeUInt16LE(0x0800, 6);
  local.writeUInt16LE(8, 8);
  local.writeUInt32LE(checksum, 14);
  local.writeUInt32LE(compressed.length, 18);
  local.writeUInt32LE(input.length, 22);
  local.writeUInt16LE(filename.length, 26);
  filename.copy(local, 30);
  const central = Buffer.alloc(46 + filename.length);
  central.writeUInt32LE(0x02014b50, 0);
  central.writeUInt16LE(0x0314, 4);
  central.writeUInt16LE(20, 6);
  central.writeUInt16LE(0x0800, 8);
  central.writeUInt16LE(8, 10);
  central.writeUInt32LE(checksum, 16);
  central.writeUInt32LE(compressed.length, 20);
  central.writeUInt32LE(input.length, 24);
  central.writeUInt16LE(filename.length, 28);
  central.writeUInt32LE(0, 38);
  filename.copy(central, 46);
  const centralOffset = local.length + compressed.length;
  const end = Buffer.alloc(22);
  end.writeUInt32LE(0x06054b50, 0);
  end.writeUInt16LE(1, 8);
  end.writeUInt16LE(1, 10);
  end.writeUInt32LE(central.length, 12);
  end.writeUInt32LE(centralOffset, 16);
  return Buffer.concat([local, compressed, central, end]);
}

function makeProof() {
  return {
    version: 1,
    status: "CI_ROUTE_READY",
    source_commit_sha: sourceSha,
    source_tree_sha: treeSha,
    context_tar_sha256: "d".repeat(64),
    platform: "linux/amd64",
    archive_sha256: "e".repeat(64),
    manifest_digest: `sha256:${"f".repeat(64)}`,
    config_image_id: imageId,
    deployed_image_id: imageId,
    rootfs_diff_ids_sha256: "1".repeat(64),
    synthetic_recovery: true,
  };
}

function makeBase() {
  const proofBytes = Buffer.from(`${JSON.stringify(makeProof())}\n`);
  const archive = zipOne("phase-2-gate-b.json", proofBytes);
  const repositoryInfo = { id: 778899, full_name: repository, fork: false };
  const jobs = [
    "ci-contract",
    "repository-integrity",
    "phase2-server",
    "phase2-sync-property",
    "phase2-backup-restore",
    "phase2-contracts-compatibility",
    "phase2-privacy",
    "image-compose-deploy",
    "opentofu-host-fixtures",
    "export-reader",
    "All required checks passed",
  ].map((name, index) => ({
    id: 9000 + index,
    run_id: 12345,
    head_sha: sourceSha,
    head_branch: "main",
    name,
    status: "completed",
    conclusion: "success",
    labels: name === "image-compose-deploy" ? ["ubuntu-24.04", "X64"] : ["ubuntu-24.04"],
  }));
  const artifact = {
    id: 4567,
    name: artifactName,
    digest: `sha256:${sha256(archive)}`,
    size_in_bytes: archive.length,
    expired: false,
    workflow_run: {
      id: 12345,
      repository_id: repositoryInfo.id,
      head_repository_id: repositoryInfo.id,
      head_branch: "main",
      head_sha: sourceSha,
    },
  };
  const scenario = {
    run: {
      id: 12345,
      run_attempt: 1,
      event: "push",
      head_branch: "main",
      head_sha: sourceSha,
      head_repository: repositoryInfo,
      repository: repositoryInfo,
      status: "completed",
      conclusion: "success",
      workflow_id: 3344,
      path: `${workflowPath}@main`,
      pull_requests: [],
    },
    workflow: { id: 3344, path: workflowPath, state: "active" },
    jobs: { total_count: jobs.length, jobs },
    commit: { sha: sourceSha, tree: { sha: treeSha } },
    artifacts: { total_count: 1, artifacts: [artifact] },
    artifactZip: archive,
  };
  return scenario;
}

function makeGithub(scenario, ledger) {
  const get = (label, fn) => async (...args) => {
    ledger.push(`GET ${label}`);
    return fn(...args);
  };
  return {
    getRun: get("run", async () => scenario.run),
    getWorkflow: get("workflow", async () => scenario.workflow),
    listJobs: get("jobs", async () => scenario.jobs),
    getCommit: get("commit", async () => scenario.commit),
    listArtifacts: get("artifacts", async () => scenario.artifacts),
    downloadArtifact: get("artifact-zip", async () => scenario.artifactZip),
  };
}

async function verify(scenario, expectedSha = sourceSha) {
  const ledger = [];
  const result = await verifyRunProvenance({
    github: makeGithub(scenario, ledger),
    repository,
    runId: 12345,
    expectedSourceSha: expectedSha,
  });
  return { result, ledger };
}

const { result, ledger } = await verify(makeBase());
assert.equal(result.version, 1);
assert.equal(result.status, "VERIFIED_NATIVE_X64");
assert.equal(result.repository, repository);
assert.equal(result.workflow_path, workflowPath);
assert.equal(result.run_id, 12345);
assert.equal(result.run_attempt, 1);
assert.equal(result.source_commit_sha, sourceSha);
assert.equal(result.source_tree_sha, treeSha);
assert.equal(result.artifact_id, 4567);
assert.equal(result.artifact_name, artifactName);
assert.equal(result.platform, "linux/amd64");
assert.equal(result.synthetic_recovery, true);
assert.deepEqual(Object.keys(result).sort(), [
  "archive_sha256", "artifact_digest", "artifact_id", "artifact_name", "artifact_zip_sha256",
  "config_image_id", "context_tar_sha256", "deployed_image_id", "manifest_digest", "platform",
  "repository", "required_jobs", "rootfs_diff_ids_sha256", "run_attempt", "run_id",
  "source_commit_sha", "source_tree_sha", "status", "synthetic_recovery", "version", "workflow_path",
].sort());
assert.equal(result.required_jobs.length, 11);
assert.deepEqual(ledger, [
  "GET run",
  "GET workflow",
  "GET jobs",
  "GET commit",
  "GET artifacts",
  "GET artifact-zip",
]);

const refusals = [
  ["pull-request event", (s) => { s.run.event = "pull_request"; }],
  ["non-main branch", (s) => { s.run.head_branch = "feature/retry"; }],
  ["fork repository", (s) => { s.run.head_repository.full_name = "fork/keepling"; }],
  ["wrong repository", (s) => { s.run.repository.full_name = "other/keepling"; }],
  ["wrong workflow path", (s) => { s.workflow.path = ".github/workflows/other.yml"; }],
  ["wrong workflow run path", (s) => { s.run.path = ".github/workflows/other.yml@main"; }],
  ["failed workflow", (s) => { s.run.conclusion = "failure"; }],
  ["incomplete workflow", (s) => { s.run.status = "in_progress"; }],
  ["rerun attempt", (s) => { s.run.run_attempt = 2; }],
  ["unexpected source revision", (s) => { s.run.head_sha = "9".repeat(40); }],
  ["consumed old source", (s) => { s.run.head_sha = "aae34ef"; }],
  ["missing required job", (s) => { s.jobs.jobs = s.jobs.jobs.filter((j) => j.name !== "phase2-server"); s.jobs.total_count -= 1; }],
  ["failed image job", (s) => { s.jobs.jobs.find((j) => j.name === "image-compose-deploy").conclusion = "failure"; }],
  ["failed required aggregator", (s) => { s.jobs.jobs.find((j) => j.name === "All required checks passed").conclusion = "failure"; }],
  ["job from another run", (s) => { s.jobs.jobs[0].run_id += 1; }],
  ["job from another source", (s) => { s.jobs.jobs[0].head_sha = "9".repeat(40); }],
  ["emulated runner label", (s) => { s.jobs.jobs.find((j) => j.name === "image-compose-deploy").labels = ["self-hosted", "ubuntu-24.04"]; }],
  ["commit tree mismatch", (s) => { s.commit.tree.sha = "9".repeat(40); }],
  ["ambiguous artifact", (s) => { s.artifacts.artifacts.push({ ...s.artifacts.artifacts[0], id: 4568 }); s.artifacts.total_count += 1; }],
  ["expired artifact", (s) => { s.artifacts.artifacts[0].expired = true; }],
  ["wrong artifact name", (s) => { s.artifacts.artifacts[0].name = "binary-image-archive"; }],
  ["invalid API artifact digest", (s) => { s.artifacts.artifacts[0].digest = "sha256:bad"; }],
  ["artifact run association mismatch", (s) => { s.artifacts.artifacts[0].workflow_run.id += 1; }],
  ["artifact repository association mismatch", (s) => { s.artifacts.artifacts[0].workflow_run.head_repository_id += 1; }],
  ["artifact source mismatch", (s) => { s.artifacts.artifacts[0].workflow_run.head_sha = "9".repeat(40); }],
  ["artifact branch mismatch", (s) => { s.artifacts.artifacts[0].workflow_run.head_branch = "release"; }],
  ["zip digest mismatch", (s) => { s.artifactZip = Buffer.concat([s.artifactZip, Buffer.from("x")]); }],
  ["artifact content source mismatch", (s) => { const p = makeProof(); p.source_commit_sha = "9".repeat(40); s.artifactZip = zipOne("phase-2-gate-b.json", JSON.stringify(p)); s.artifacts.artifacts[0].digest = `sha256:${sha256(s.artifactZip)}`; s.artifacts.artifacts[0].size_in_bytes = s.artifactZip.length; }],
  ["artifact content tree mismatch", (s) => { const p = makeProof(); p.source_tree_sha = "9".repeat(40); s.artifactZip = zipOne("phase-2-gate-b.json", JSON.stringify(p)); s.artifacts.artifacts[0].digest = `sha256:${sha256(s.artifactZip)}`; s.artifacts.artifacts[0].size_in_bytes = s.artifactZip.length; }],
  ["emulated image platform", (s) => { const p = makeProof(); p.platform = "linux/arm64"; s.artifactZip = zipOne("phase-2-gate-b.json", JSON.stringify(p)); s.artifacts.artifacts[0].digest = `sha256:${sha256(s.artifactZip)}`; s.artifacts.artifacts[0].size_in_bytes = s.artifactZip.length; }],
  ["mismatched deployed image", (s) => { const p = makeProof(); p.deployed_image_id = `sha256:${"9".repeat(64)}`; s.artifactZip = zipOne("phase-2-gate-b.json", JSON.stringify(p)); s.artifacts.artifacts[0].digest = `sha256:${sha256(s.artifactZip)}`; s.artifacts.artifacts[0].size_in_bytes = s.artifactZip.length; }],
  ["missing context tar identity", (s) => { const p = makeProof(); p.context_tar_sha256 = ""; s.artifactZip = zipOne("phase-2-gate-b.json", JSON.stringify(p)); s.artifacts.artifacts[0].digest = `sha256:${sha256(s.artifactZip)}`; s.artifacts.artifacts[0].size_in_bytes = s.artifactZip.length; }],
  ["missing final archive identity", (s) => { const p = makeProof(); p.archive_sha256 = ""; s.artifactZip = zipOne("phase-2-gate-b.json", JSON.stringify(p)); s.artifacts.artifacts[0].digest = `sha256:${sha256(s.artifactZip)}`; s.artifacts.artifacts[0].size_in_bytes = s.artifactZip.length; }],
  ["missing OCI manifest identity", (s) => { const p = makeProof(); p.manifest_digest = "sha256:bad"; s.artifactZip = zipOne("phase-2-gate-b.json", JSON.stringify(p)); s.artifacts.artifacts[0].digest = `sha256:${sha256(s.artifactZip)}`; s.artifacts.artifacts[0].size_in_bytes = s.artifactZip.length; }],
  ["missing config identity", (s) => { const p = makeProof(); p.config_image_id = "sha256:bad"; s.artifactZip = zipOne("phase-2-gate-b.json", JSON.stringify(p)); s.artifacts.artifacts[0].digest = `sha256:${sha256(s.artifactZip)}`; s.artifacts.artifacts[0].size_in_bytes = s.artifactZip.length; }],
  ["missing rootfs identity", (s) => { const p = makeProof(); p.rootfs_diff_ids_sha256 = ""; s.artifactZip = zipOne("phase-2-gate-b.json", JSON.stringify(p)); s.artifacts.artifacts[0].digest = `sha256:${sha256(s.artifactZip)}`; s.artifacts.artifacts[0].size_in_bytes = s.artifactZip.length; }],
  ["route-ready label cannot claim acceptance", (s) => { const p = makeProof(); p.status = "GATE_B_PASSED"; s.artifactZip = zipOne("phase-2-gate-b.json", JSON.stringify(p)); s.artifacts.artifacts[0].digest = `sha256:${sha256(s.artifactZip)}`; s.artifacts.artifacts[0].size_in_bytes = s.artifactZip.length; }],
  ["ZIP path traversal", (s) => { s.artifactZip = zipOne("../phase-2-gate-b.json", JSON.stringify(makeProof())); s.artifacts.artifacts[0].digest = `sha256:${sha256(s.artifactZip)}`; s.artifacts.artifacts[0].size_in_bytes = s.artifactZip.length; }],
  ["multiple ZIP entries", (s) => { s.artifactZip = Buffer.from(s.artifactZip); s.artifactZip.writeUInt16LE(2, 8); s.artifactZip.writeUInt16LE(2, 10); s.artifacts.artifacts[0].digest = `sha256:${sha256(s.artifactZip)}`; }],
  ["invalid proof JSON", (s) => { s.artifactZip = zipOne("phase-2-gate-b.json", "{not-json"); s.artifacts.artifacts[0].digest = `sha256:${sha256(s.artifactZip)}`; s.artifacts.artifacts[0].size_in_bytes = s.artifactZip.length; }],
  ["missing synthetic recovery", (s) => { const p = makeProof(); p.synthetic_recovery = false; s.artifactZip = zipOne("phase-2-gate-b.json", JSON.stringify(p)); s.artifacts.artifacts[0].digest = `sha256:${sha256(s.artifactZip)}`; s.artifacts.artifacts[0].size_in_bytes = s.artifactZip.length; }],
  ["unrecognized schema key", (s) => { const p = { ...makeProof(), task_title: "private title" }; s.artifactZip = zipOne("phase-2-gate-b.json", JSON.stringify(p)); s.artifacts.artifacts[0].digest = `sha256:${sha256(s.artifactZip)}`; s.artifacts.artifacts[0].size_in_bytes = s.artifactZip.length; }],
  ["incomplete artifact listing", (s) => { s.artifacts.total_count += 1; }],
  ["duplicate required job", (s) => { s.jobs.jobs.push({ ...s.jobs.jobs.find((j) => j.name === "image-compose-deploy"), id: 99999 }); s.jobs.total_count += 1; }],
];

for (const [label, mutate] of refusals) {
  const scenario = makeBase();
  mutate(scenario);
  await assert.rejects(() => verify(scenario), undefined, `${label} must refuse`);
}

await assert.rejects(
  () => verify(makeBase(), "9".repeat(40)),
  undefined,
  "caller expected-source mismatch must refuse",
);
await assert.rejects(
  () => verify(makeBase(), "13de7df" + "0".repeat(33)),
  undefined,
  "consumed Plan 02-20 source must refuse",
);

console.log(`phase-2-ci-provenance fixtures passed: positive=1 refused=${refusals.length + 2} external_calls=0`);
