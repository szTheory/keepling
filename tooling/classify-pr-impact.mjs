#!/usr/bin/env node

import { appendFileSync, readFileSync } from "node:fs";

const API_VERSION = "2026-03-10";
const PAGE_SIZE = 100;
const MAX_FILES = 3000;

export function isDocumentationPath(value) {
  if (typeof value !== "string" || value.length === 0) return false;
  if (value.startsWith("/") || value.includes("\\") || value.includes("\0")) return false;

  const segments = value.split("/");
  if (segments.some((segment) => segment === "" || segment === "." || segment === "..")) return false;
  if (segments[0] === ".github") return false;
  if (value.startsWith(".planning/releases/")) return false;

  if (/^[^/]+\.md$/.test(value)) return true;
  if (value.startsWith("docs/") && value.endsWith(".md")) return true;
  if (value.startsWith(".planning/") && value.endsWith(".md")) return true;
  return /^\.planning\/knowledge\/templates\/[^/]+\.prompt\.txt$/.test(value);
}

export function isDocumentationOnly(paths) {
  return Array.isArray(paths) && paths.length > 0 && paths.every(isDocumentationPath);
}

function runSelfTest() {
  const cases = [
    ["root markdown", ["README.md"], true],
    ["docs markdown", ["docs/operations/phase-2-host-replacement.md"], true],
    ["planning markdown", [".planning/phases/KPL-02/02-CONTEXT.md"], true],
    ["prompt template", [".planning/knowledge/templates/PROJECT-DNA-FANOUT.prompt.txt"], true],
    ["mixed rename includes source", ["docs/new.md", "apps/server/lib/task.ex"], false],
    ["workflow", [".github/workflows/desktop.yml"], false],
    ["tooling", ["tooling/check-ci-contract.mjs"], false],
    ["release evidence", [".planning/releases/candidate-5/README.md"], false],
    ["unknown extension", ["docs/reference.json"], false],
    ["path traversal", ["docs/../apps/server/lib/task.ex"], false],
    ["empty changeset", [], false],
  ];

  for (const [name, paths, expected] of cases) {
    const actual = isDocumentationOnly(paths);
    if (actual !== expected) throw new Error(`${name}: expected ${expected}, received ${actual}`);
  }
  console.log(`PR impact classifier self-test passed: cases=${cases.length}`);
}

function writeOutput(runHeavy, reason) {
  const outputPath = process.env.GITHUB_OUTPUT;
  if (!outputPath) throw new Error("GITHUB_OUTPUT is missing");
  appendFileSync(outputPath, `run_heavy=${runHeavy}\nreason=${reason}\n`);
}

function fullSuite(reason) {
  console.log(`PR impact: running full checks (${reason})`);
  writeOutput("true", reason);
}

async function listPullRequestFiles() {
  const eventName = process.env.GITHUB_EVENT_NAME;
  if (eventName !== "pull_request" && eventName !== "pull_request_target") {
    return { runHeavy: true, reason: "non_pull_request_event" };
  }

  const eventPath = process.env.GITHUB_EVENT_PATH;
  const event = JSON.parse(readFileSync(eventPath, "utf8"));
  const pullRequest = event.pull_request;
  const pullNumber = pullRequest?.number;
  const eventHeadSha = pullRequest?.head?.sha;
  const eventBaseSha = pullRequest?.base?.sha;
  if (
    !Number.isInteger(pullNumber) ||
    !/^[0-9a-f]{40,64}$/i.test(eventHeadSha ?? "") ||
    !/^[0-9a-f]{40,64}$/i.test(eventBaseSha ?? "")
  ) {
    return { runHeavy: true, reason: "pull_request_metadata_unavailable" };
  }

  const token = process.env.GITHUB_TOKEN;
  const repository = process.env.GITHUB_REPOSITORY;
  const apiBase = (process.env.GITHUB_API_URL ?? "https://api.github.com").replace(/\/+$/, "");
  if (!token || !repository || !/^[^/]+\/[^/]+$/.test(repository)) {
    return { runHeavy: true, reason: "api_credentials_unavailable" };
  }

  async function fetchPullRequestMetadata() {
    const endpoint = `${apiBase}/repos/${repository}/pulls/${pullNumber}`;
    const response = await fetch(endpoint, {
      headers: {
        Accept: "application/vnd.github+json",
        Authorization: `Bearer ${token}`,
        "X-GitHub-Api-Version": API_VERSION,
      },
    });
    if (!response.ok) return null;
    return response.json();
  }

  const initialMetadata = await fetchPullRequestMetadata();
  if (!initialMetadata) return { runHeavy: true, reason: "api_response_unavailable" };
  if (
    initialMetadata.head?.sha !== eventHeadSha ||
    initialMetadata.base?.sha !== eventBaseSha
  ) {
    return { runHeavy: true, reason: "pull_request_revision_moved" };
  }

  const expectedCount = initialMetadata.changed_files;
  if (!Number.isInteger(expectedCount) || expectedCount < 1) {
    return { runHeavy: true, reason: "changed_file_count_unavailable" };
  }
  if (expectedCount > MAX_FILES) {
    return { runHeavy: true, reason: "file_limit_exceeded" };
  }

  const files = [];
  const pageLimit = Math.ceil(MAX_FILES / PAGE_SIZE);
  for (let page = 1; page <= pageLimit; page += 1) {
    const endpoint = new URL(
      `${apiBase}/repos/${repository}/pulls/${pullNumber}/files`,
    );
    endpoint.searchParams.set("per_page", String(PAGE_SIZE));
    endpoint.searchParams.set("page", String(page));

    const response = await fetch(endpoint, {
      headers: {
        Accept: "application/vnd.github+json",
        Authorization: `Bearer ${token}`,
        "X-GitHub-Api-Version": API_VERSION,
      },
    });
    if (!response.ok) return { runHeavy: true, reason: "api_response_unavailable" };

    const batch = await response.json();
    if (!Array.isArray(batch)) return { runHeavy: true, reason: "api_response_invalid" };
    files.push(...batch);
    if (batch.length < PAGE_SIZE) break;
  }

  if (files.length !== expectedCount) {
    return { runHeavy: true, reason: "changed_file_count_mismatch" };
  }

  const finalMetadata = await fetchPullRequestMetadata();
  if (
    !finalMetadata ||
    finalMetadata.head?.sha !== eventHeadSha ||
    finalMetadata.base?.sha !== eventBaseSha ||
    finalMetadata.changed_files !== expectedCount
  ) {
    return { runHeavy: true, reason: "pull_request_revision_moved" };
  }

  const paths = [];
  for (const file of files) {
    if (typeof file?.filename !== "string") {
      return { runHeavy: true, reason: "file_path_unavailable" };
    }
    paths.push(file.filename);
    if (file.status === "renamed") {
      if (typeof file.previous_filename !== "string") {
        return { runHeavy: true, reason: "rename_source_unavailable" };
      }
      paths.push(file.previous_filename);
    }
  }

  return isDocumentationOnly(paths)
    ? { runHeavy: false, reason: "documentation_only" }
    : { runHeavy: true, reason: "product_or_unknown_path" };
}

async function main() {
  if (process.argv.includes("--self-test")) {
    runSelfTest();
    return;
  }

  let result;
  try {
    result = await listPullRequestFiles();
  } catch {
    result = { runHeavy: true, reason: "classifier_unavailable" };
  }

  console.log(
    `PR impact: ${result.runHeavy ? "full checks" : "documentation-only checks"} (${result.reason})`,
  );
  writeOutput(String(result.runHeavy), result.reason);
}

main().catch((error) => {
  console.error(`PR impact classifier could not emit a result: ${error.message}`);
  process.exitCode = 1;
});
