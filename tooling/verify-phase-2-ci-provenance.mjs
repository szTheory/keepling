#!/usr/bin/env node

import { createHash } from "node:crypto";
import { chmod, mkdtemp, readFile, realpath, rm, writeFile } from "node:fs/promises";
import os from "node:os";
import path from "node:path";
import { fileURLToPath } from "node:url";
import { inflateRawSync } from "node:zlib";

const API_VERSION = "2026-03-10";
const WORKFLOW_PATH = ".github/workflows/repository-integrity.yml";
const ARTIFACT_NAME = "phase-2-gate-b-route-evidence";
const ARTIFACT_FILE = "phase-2-gate-b.json";
const MAX_ARTIFACT_BYTES = 256 * 1024;
const MAX_PROOF_BYTES = 32 * 1024;
const REQUIRED_JOB_NAMES = [
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
];
const LEGACY_SOURCE_PREFIXES = [
  "aae34ef",
  "b77cfebeb955054b88b7d48cd82bec9a9c7809cf",
  "13de7df",
  "e620054ab6df34f1056133de6a2a3705b55ee9a1",
];

export class ProvenanceError extends Error {
  constructor(code) {
    super(code);
    this.name = "ProvenanceError";
    this.code = code;
  }
}

function refuse(code) {
  throw new ProvenanceError(code);
}

function isObject(value) {
  return value !== null && typeof value === "object" && !Array.isArray(value);
}

function isSha(value) {
  return typeof value === "string" && /^[0-9a-f]{40}$/.test(value);
}

function isHexDigest(value) {
  return typeof value === "string" && /^[0-9a-f]{64}$/.test(value);
}

function isImageId(value) {
  return typeof value === "string" && /^sha256:[0-9a-f]{64}$/.test(value);
}

function isRepositoryName(value) {
  if (typeof value !== "string" || !/^[-A-Za-z0-9_.]+\/[-A-Za-z0-9_.]+$/.test(value)) return false;
  return value.split("/").every((part) => part !== "." && part !== "..");
}

function assertPage(page, rowsKey, code) {
  if (!isObject(page) || !Array.isArray(page[rowsKey])) refuse(code);
  if (!Number.isSafeInteger(page.total_count) || page.total_count !== page[rowsKey].length) refuse(code);
  if (page.total_count > 100) refuse(code);
  return page[rowsKey];
}

function validateRun(run, repository, runId, expectedSha) {
  if (!isObject(run)) refuse("run_metadata_invalid");
  if (run.id !== runId) refuse("run_id_mismatch");
  if (run.event !== "push" || run.head_branch !== "main") refuse("run_not_trusted_main_push");
  if (run.status !== "completed" || run.conclusion !== "success") refuse("run_not_successful");
  if (run.run_attempt !== 1) refuse("run_attempt_not_first");
  if (!isSha(expectedSha) || run.head_sha !== expectedSha) refuse("run_source_sha_mismatch");
  if (LEGACY_SOURCE_PREFIXES.some((prefix) => run.head_sha.startsWith(prefix))) refuse("consumed_source_rejected");
  if (!Array.isArray(run.pull_requests) || run.pull_requests.length !== 0) refuse("run_pull_request_association_present");
  if (!isObject(run.repository) || run.repository.full_name !== repository || run.repository.fork === true) {
    refuse("run_repository_mismatch");
  }
  if (!Number.isSafeInteger(run.repository.id) || run.repository.id <= 0) refuse("run_repository_identity_missing");
  if (!isObject(run.head_repository) || run.head_repository.full_name !== repository || run.head_repository.id !== run.repository.id) {
    refuse("run_head_repository_mismatch");
  }
  if (!Number.isSafeInteger(run.workflow_id) || run.workflow_id <= 0) refuse("run_workflow_id_missing");
  if (![`${WORKFLOW_PATH}@main`, `${WORKFLOW_PATH}@refs/heads/main`].includes(run.path)) {
    refuse("run_workflow_path_mismatch");
  }
}

function validateWorkflow(workflow, run) {
  if (!isObject(workflow) || workflow.id !== run.workflow_id || workflow.path !== WORKFLOW_PATH) {
    refuse("workflow_identity_mismatch");
  }
}

function validateJobs(page, run, runId, expectedSha) {
  const jobs = assertPage(page, "jobs", "job_listing_incomplete");
  const byName = new Map();
  const ids = new Set();
  for (const job of jobs) {
    if (!isObject(job) || !Number.isSafeInteger(job.id) || job.id <= 0 || ids.has(job.id)) {
      refuse("job_identity_invalid");
    }
    ids.add(job.id);
    if (REQUIRED_JOB_NAMES.includes(job.name)) {
      if (byName.has(job.name)) refuse("required_job_ambiguous");
      byName.set(job.name, job);
    }
  }
  for (const name of REQUIRED_JOB_NAMES) {
    const job = byName.get(name);
    if (!job) refuse("required_job_missing");
    if (job.run_id !== runId || job.head_sha !== expectedSha || job.head_branch !== "main") {
      refuse("required_job_source_mismatch");
    }
    if (job.status !== "completed" || job.conclusion !== "success") refuse("required_job_not_successful");
  }
  const imageJob = byName.get("image-compose-deploy");
  const labels = Array.isArray(imageJob.labels) ? imageJob.labels.map((label) => String(label).toLowerCase()) : [];
  if (!labels.includes("ubuntu-24.04") || labels.includes("self-hosted")) refuse("image_job_runner_not_hosted_x64");
  return REQUIRED_JOB_NAMES.map((name) => ({
    id: byName.get(name).id,
    name,
    conclusion: "success",
  }));
}

function validateCommit(commit, expectedSha) {
  if (!isObject(commit) || commit.sha !== expectedSha || !isObject(commit.tree) || !isSha(commit.tree.sha)) {
    refuse("source_commit_metadata_invalid");
  }
  return commit.tree.sha;
}

function validateArtifactList(page, run, runId, expectedSha) {
  const artifacts = assertPage(page, "artifacts", "artifact_listing_incomplete");
  const matches = artifacts.filter((artifact) => isObject(artifact) && artifact.name === ARTIFACT_NAME);
  if (matches.length !== 1) refuse("sanitized_artifact_not_unique");
  const artifact = matches[0];
  if (!Number.isSafeInteger(artifact.id) || artifact.id <= 0) refuse("artifact_id_invalid");
  if (artifact.expired !== false) refuse("artifact_expired");
  if (!Number.isSafeInteger(artifact.size_in_bytes) || artifact.size_in_bytes <= 0 || artifact.size_in_bytes > MAX_ARTIFACT_BYTES) {
    refuse("artifact_size_invalid");
  }
  if (typeof artifact.digest !== "string" || !/^sha256:[0-9a-f]{64}$/.test(artifact.digest)) {
    refuse("artifact_digest_invalid");
  }
  const link = artifact.workflow_run;
  if (!isObject(link) || link.id !== runId || link.repository_id !== run.repository.id ||
      link.head_repository_id !== run.repository.id || link.head_branch !== "main" || link.head_sha !== expectedSha) {
    refuse("artifact_run_association_mismatch");
  }
  return artifact;
}

function crc32(bytes) {
  let crc = 0xffffffff;
  for (const byte of bytes) {
    crc ^= byte;
    for (let bit = 0; bit < 8; bit += 1) crc = (crc >>> 1) ^ (crc & 1 ? 0xedb88320 : 0);
  }
  return (crc ^ 0xffffffff) >>> 0;
}

function findEndOfCentralDirectory(zip) {
  const lower = Math.max(0, zip.length - 65_557);
  for (let offset = zip.length - 22; offset >= lower; offset -= 1) {
    if (zip.readUInt32LE(offset) === 0x06054b50) {
      const commentLength = zip.readUInt16LE(offset + 20);
      if (offset + 22 + commentLength === zip.length) return offset;
    }
  }
  refuse("artifact_zip_invalid");
}

export function extractExpectedJsonFromZip(zip) {
  if (!Buffer.isBuffer(zip) || zip.length < 22 || zip.length > MAX_ARTIFACT_BYTES) refuse("artifact_zip_size_invalid");
  const eocdOffset = findEndOfCentralDirectory(zip);
  const disk = zip.readUInt16LE(eocdOffset + 4);
  const centralDisk = zip.readUInt16LE(eocdOffset + 6);
  const entriesOnDisk = zip.readUInt16LE(eocdOffset + 8);
  const entryCount = zip.readUInt16LE(eocdOffset + 10);
  const centralSize = zip.readUInt32LE(eocdOffset + 12);
  const centralOffset = zip.readUInt32LE(eocdOffset + 16);
  if (disk !== 0 || centralDisk !== 0 || entriesOnDisk !== 1 || entryCount !== 1 ||
      centralOffset + centralSize !== eocdOffset || centralOffset >= zip.length) {
    refuse("artifact_zip_layout_invalid");
  }
  if (zip.readUInt32LE(centralOffset) !== 0x02014b50) refuse("artifact_zip_entry_invalid");

  const flags = zip.readUInt16LE(centralOffset + 8);
  const method = zip.readUInt16LE(centralOffset + 10);
  const expectedCrc = zip.readUInt32LE(centralOffset + 16);
  const compressedSize = zip.readUInt32LE(centralOffset + 20);
  const uncompressedSize = zip.readUInt32LE(centralOffset + 24);
  const nameLength = zip.readUInt16LE(centralOffset + 28);
  const extraLength = zip.readUInt16LE(centralOffset + 30);
  const commentLength = zip.readUInt16LE(centralOffset + 32);
  const startDisk = zip.readUInt16LE(centralOffset + 34);
  const localOffset = zip.readUInt32LE(centralOffset + 42);
  const centralEntryEnd = centralOffset + 46 + nameLength + extraLength + commentLength;
  if (centralEntryEnd !== eocdOffset || startDisk !== 0 || nameLength === 0 ||
      (flags & ~0x0808) !== 0 || ![0, 8].includes(method) ||
      compressedSize > MAX_PROOF_BYTES || uncompressedSize <= 0 || uncompressedSize > MAX_PROOF_BYTES) {
    refuse("artifact_zip_entry_invalid");
  }
  const entryName = zip.subarray(centralOffset + 46, centralOffset + 46 + nameLength).toString("utf8");
  if (entryName !== ARTIFACT_FILE) refuse("artifact_zip_unexpected_entry");
  if (localOffset + 30 > centralOffset || zip.readUInt32LE(localOffset) !== 0x04034b50) {
    refuse("artifact_zip_local_header_invalid");
  }
  const localFlags = zip.readUInt16LE(localOffset + 6);
  const localMethod = zip.readUInt16LE(localOffset + 8);
  const localCrc = zip.readUInt32LE(localOffset + 14);
  const localCompressed = zip.readUInt32LE(localOffset + 18);
  const localUncompressed = zip.readUInt32LE(localOffset + 22);
  const localNameLength = zip.readUInt16LE(localOffset + 26);
  const localExtraLength = zip.readUInt16LE(localOffset + 28);
  const dataOffset = localOffset + 30 + localNameLength + localExtraLength;
  const dataEnd = dataOffset + compressedSize;
  if (localFlags !== flags || localMethod !== method || localNameLength !== nameLength ||
      zip.subarray(localOffset + 30, localOffset + 30 + localNameLength).toString("utf8") !== entryName ||
      dataEnd > centralOffset ||
      (!(flags & 0x0008) && (localCrc !== expectedCrc || localCompressed !== compressedSize || localUncompressed !== uncompressedSize))) {
    refuse("artifact_zip_local_header_invalid");
  }
  const compressed = zip.subarray(dataOffset, dataEnd);
  let contents;
  try {
    contents = method === 0 ? Buffer.from(compressed) : inflateRawSync(compressed, { maxOutputLength: MAX_PROOF_BYTES });
  } catch {
    refuse("artifact_zip_deflate_invalid");
  }
  if (contents.length !== uncompressedSize || crc32(contents) !== expectedCrc) refuse("artifact_zip_crc_mismatch");
  return contents;
}

function parseAndValidateProof(bytes, expectedSha, expectedTree) {
  if (!Buffer.isBuffer(bytes) || bytes.length === 0 || bytes.length > MAX_PROOF_BYTES) refuse("artifact_proof_size_invalid");
  let proof;
  try {
    proof = JSON.parse(bytes.toString("utf8"));
  } catch {
    refuse("artifact_proof_json_invalid");
  }
  const expectedKeys = [
    "archive_sha256", "config_image_id", "context_tar_sha256", "deployed_image_id",
    "manifest_digest", "platform", "rootfs_diff_ids_sha256", "source_commit_sha",
    "source_tree_sha", "status", "synthetic_recovery", "version",
  ];
  if (!isObject(proof) || JSON.stringify(Object.keys(proof).sort()) !== JSON.stringify(expectedKeys)) {
    refuse("artifact_proof_schema_invalid");
  }
  if (proof.version !== 1 || proof.status !== "CI_ROUTE_READY" || proof.platform !== "linux/amd64" ||
      proof.synthetic_recovery !== true) refuse("artifact_proof_not_route_ready");
  if (proof.source_commit_sha !== expectedSha || proof.source_tree_sha !== expectedTree) {
    refuse("artifact_proof_source_mismatch");
  }
  if (!isHexDigest(proof.context_tar_sha256) || !isHexDigest(proof.archive_sha256) ||
      !isHexDigest(proof.rootfs_diff_ids_sha256) || !/^sha256:[0-9a-f]{64}$/.test(proof.manifest_digest) ||
      !isImageId(proof.config_image_id) || !isImageId(proof.deployed_image_id) ||
      proof.config_image_id !== proof.deployed_image_id) {
    refuse("artifact_proof_image_identity_invalid");
  }
  return proof;
}

function digest(bytes) {
  return createHash("sha256").update(bytes).digest("hex");
}

export async function verifyRunProvenance({ github, repository, runId, expectedSourceSha, tempDirectory = os.tmpdir() }) {
  if (!github || !isRepositoryName(repository) ||
      !Number.isSafeInteger(runId) || runId <= 0 || !isSha(expectedSourceSha) ||
      LEGACY_SOURCE_PREFIXES.some((prefix) => expectedSourceSha.startsWith(prefix))) {
    refuse("input_invalid");
  }
  const run = await github.getRun(repository, runId);
  validateRun(run, repository, runId, expectedSourceSha);
  const workflow = await github.getWorkflow(repository, run.workflow_id);
  validateWorkflow(workflow, run);
  const jobs = await github.listJobs(repository, runId);
  const requiredJobs = validateJobs(jobs, run, runId, expectedSourceSha);
  const commit = await github.getCommit(repository, expectedSourceSha);
  const sourceTreeSha = validateCommit(commit, expectedSourceSha);
  const artifactList = await github.listArtifacts(repository, runId);
  const artifact = validateArtifactList(artifactList, run, runId, expectedSourceSha);

  const privateDirectory = await mkdtemp(path.join(tempDirectory, "keepling-phase-2-provenance-"));
  try {
    await chmod(privateDirectory, 0o700);
    const zip = await github.downloadArtifact(repository, artifact.id);
    if (!Buffer.isBuffer(zip) || zip.length !== artifact.size_in_bytes || zip.length > MAX_ARTIFACT_BYTES) {
      refuse("artifact_download_size_mismatch");
    }
    const archiveSha = digest(zip);
    if (artifact.digest !== `sha256:${archiveSha}`) refuse("artifact_download_digest_mismatch");
    const zipPath = path.join(privateDirectory, "artifact.zip");
    await writeFile(zipPath, zip, { mode: 0o600, flag: "wx" });
    const proofBytes = extractExpectedJsonFromZip(await readFile(zipPath));
    const proofPath = path.join(privateDirectory, ARTIFACT_FILE);
    await writeFile(proofPath, proofBytes, { mode: 0o600, flag: "wx" });
    const proof = parseAndValidateProof(await readFile(proofPath), expectedSourceSha, sourceTreeSha);

    return {
      version: 1,
      status: "VERIFIED_NATIVE_X64",
      repository,
      workflow_path: WORKFLOW_PATH,
      run_id: run.id,
      run_attempt: run.run_attempt,
      required_jobs: requiredJobs,
      source_commit_sha: expectedSourceSha,
      source_tree_sha: sourceTreeSha,
      artifact_id: artifact.id,
      artifact_name: ARTIFACT_NAME,
      artifact_digest: artifact.digest,
      artifact_zip_sha256: archiveSha,
      context_tar_sha256: proof.context_tar_sha256,
      archive_sha256: proof.archive_sha256,
      manifest_digest: proof.manifest_digest,
      config_image_id: proof.config_image_id,
      rootfs_diff_ids_sha256: proof.rootfs_diff_ids_sha256,
      platform: proof.platform,
      deployed_image_id: proof.deployed_image_id,
      synthetic_recovery: proof.synthetic_recovery,
    };
  } finally {
    await rm(privateDirectory, { recursive: true, force: true });
  }
}

class GitHubReadOnlyApi {
  constructor(token) {
    this.token = token;
  }

  async json(pathname) {
    const response = await fetch(`https://api.github.com${pathname}`, {
      method: "GET",
      redirect: "error",
      signal: AbortSignal.timeout(15_000),
      headers: {
        accept: "application/vnd.github+json",
        authorization: `Bearer ${this.token}`,
        "x-github-api-version": API_VERSION,
      },
    });
    if (!response.ok) refuse(`github_api_http_${response.status}`);
    const body = await readResponseBytes(response, 2 * 1024 * 1024, "github_api_response_too_large");
    try {
      return JSON.parse(body.toString("utf8"));
    } catch {
      refuse("github_api_json_invalid");
    }
  }

  getRun(repository, runId) {
    return this.json(`/repos/${repository}/actions/runs/${runId}?exclude_pull_requests=true`);
  }

  getWorkflow(repository, workflowId) {
    return this.json(`/repos/${repository}/actions/workflows/${workflowId}`);
  }

  listJobs(repository, runId) {
    return this.json(`/repos/${repository}/actions/runs/${runId}/jobs?filter=latest&per_page=100&page=1`);
  }

  getCommit(repository, sha) {
    return this.json(`/repos/${repository}/git/commits/${sha}`);
  }

  listArtifacts(repository, runId) {
    return this.json(`/repos/${repository}/actions/runs/${runId}/artifacts?per_page=100&page=1`);
  }

  async downloadArtifact(repository, artifactId) {
    const download = await fetch(`https://api.github.com/repos/${repository}/actions/artifacts/${artifactId}/zip`, {
      method: "GET",
      redirect: "manual",
      signal: AbortSignal.timeout(15_000),
      headers: {
        accept: "application/vnd.github+json",
        authorization: `Bearer ${this.token}`,
        "x-github-api-version": API_VERSION,
      },
    });
    if (download.status !== 302) refuse("artifact_download_redirect_missing");
    const location = download.headers.get("location");
    if (!location) refuse("artifact_download_location_missing");
    let target;
    try {
      target = new URL(location);
    } catch {
      refuse("artifact_download_location_invalid");
    }
    const host = target.hostname.toLowerCase();
    const allowedHost = host === "github.com" || host.endsWith(".githubusercontent.com") || host.endsWith(".blob.core.windows.net");
    if (target.protocol !== "https:" || target.username || target.password || !allowedHost) {
      refuse("artifact_download_host_invalid");
    }
    const response = await fetch(target, {
      method: "GET",
      redirect: "error",
      signal: AbortSignal.timeout(30_000),
      headers: { accept: "application/zip" },
    });
    if (!response.ok) refuse(`artifact_download_http_${response.status}`);
    return readResponseBytes(response, MAX_ARTIFACT_BYTES, "artifact_download_too_large");
  }
}

async function readResponseBytes(response, maximum, tooLargeCode) {
  if (!response.body) refuse("github_response_body_missing");
  const reader = response.body.getReader();
  const chunks = [];
  let length = 0;
  try {
    while (true) {
      const { done, value } = await reader.read();
      if (done) break;
      length += value.byteLength;
      if (length > maximum) {
        await reader.cancel();
        refuse(tooLargeCode);
      }
      chunks.push(Buffer.from(value));
    }
  } finally {
    reader.releaseLock();
  }
  return Buffer.concat(chunks, length);
}

function parseArgs(args) {
  const values = new Map();
  for (let index = 0; index < args.length; index += 1) {
    const key = args[index];
    if (!["--repo", "--run-id", "--expected-sha", "--output"].includes(key) || values.has(key) || !args[index + 1]) {
      refuse("usage");
    }
    values.set(key, args[++index]);
  }
  const repository = values.get("--repo") ?? process.env.GITHUB_REPOSITORY;
  const token = process.env.GITHUB_TOKEN;
  const runText = values.get("--run-id");
  const output = values.get("--output");
  const expectedSourceSha = values.get("--expected-sha");
  const runId = /^\d+$/.test(runText ?? "") ? Number(runText) : NaN;
  if (!isRepositoryName(repository) || !output || !path.isAbsolute(output) || !token || !isSha(expectedSourceSha) || !Number.isSafeInteger(runId)) {
    refuse("usage");
  }
  return { repository, token, runId, expectedSourceSha, output: path.resolve(output) };
}

async function writeOutputSafely(output, result) {
  const repositoryRoot = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "..");
  const realRoot = await realpath(repositoryRoot);
  const realParent = await realpath(path.dirname(output));
  if (realParent === realRoot || realParent.startsWith(`${realRoot}${path.sep}`)) refuse("output_must_be_outside_repository");
  const serialized = `${JSON.stringify(result, null, 2)}\n`;
  await writeFile(output, serialized, { mode: 0o600, flag: "wx" });
  await chmod(output, 0o600);
}

async function main() {
  const input = parseArgs(process.argv.slice(2));
  const result = await verifyRunProvenance({
    github: new GitHubReadOnlyApi(input.token),
    repository: input.repository,
    runId: input.runId,
    expectedSourceSha: input.expectedSourceSha,
  });
  await writeOutputSafely(input.output, result);
  process.stdout.write("phase-2-ci-provenance status=VERIFIED_NATIVE_X64\n");
}

if (process.argv[1] && path.resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  main().catch((error) => {
    const reason = error instanceof ProvenanceError ? error.code : "unexpected_error";
    process.stderr.write(`phase-2-ci-provenance status=NON_PASSING reason=${reason}\n`);
    process.exitCode = 1;
  });
}
