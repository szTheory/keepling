#!/usr/bin/env node
// Generates KNOWN-LIMITATIONS.md from the open rows of .planning/WINDOWS.md.
//
// This is deliberately a generator, not a hand-written document (D-42): the public limitations
// list can never disagree with the internal ledger, because it is never edited independently of
// it. A ledger row with an empty owner is a generator failure, not an entry -- the anti-"unowned"
// clause (D-35) made that state illegal, and this generator enforces it by refusing to run.

import { existsSync, readFileSync, writeFileSync } from "node:fs";
import { fileURLToPath } from "node:url";
import path from "node:path";

function parseArgs(argv) {
  const args = { ledger: null, out: null, selfTest: false };
  for (let i = 0; i < argv.length; i += 1) {
    const arg = argv[i];
    if (arg === "--ledger") {
      args.ledger = argv[(i += 1)];
    } else if (arg === "--out") {
      args.out = argv[(i += 1)];
    } else if (arg === "--self-test") {
      args.selfTest = true;
    } else {
      throw new Error(`Unknown argument: ${arg}`);
    }
  }
  return args;
}

// Splits one markdown table row into its cell values, honoring `\|` as an escaped literal pipe
// rather than a column separator (the ledger uses this for descriptions that quote other tables).
function splitRow(line) {
  const inner = line.trim().replace(/^\|/, "").replace(/\|$/, "");
  const cells = [];
  let current = "";
  for (let i = 0; i < inner.length; i += 1) {
    const char = inner[i];
    if (char === "\\" && inner[i + 1] === "|") {
      current += "|";
      i += 1;
    } else if (char === "|") {
      cells.push(current.trim());
      current = "";
    } else {
      current += char;
    }
  }
  cells.push(current.trim());
  return cells;
}

function parseLedger(text) {
  const lines = text.split("\n");
  const headerIndex = lines.findIndex((line) => line.trim().startsWith("| id "));
  if (headerIndex === -1) {
    throw new Error(
      'generator failure: could not locate the WINDOWS.md table header ("| id | ...") -- is the ledger readable and in its expected shape?',
    );
  }
  const header = splitRow(lines[headerIndex]);
  const rows = [];
  for (let i = headerIndex + 2; i < lines.length; i += 1) {
    const line = lines[i];
    if (!line.trim().startsWith("|")) {
      break;
    }
    const cells = splitRow(line);
    if (cells.length !== header.length) {
      throw new Error(
        `generator failure: WINDOWS.md row at line ${i + 1} has ${cells.length} cells, expected ${header.length} to match the header`,
      );
    }
    const row = {};
    header.forEach((key, index) => {
      row[key] = cells[index];
    });
    rows.push(row);
  }
  return rows;
}

function openLimitations(rows) {
  const openRows = rows.filter((row) => row.status === "open");
  for (const row of openRows) {
    if (!row.owner || row.owner.trim() === "") {
      throw new Error(
        `generator failure: WINDOWS.md row id=${row.id} (phase=${row.phase}) is open with an empty owner -- an unowned open row is illegal, not a silent entry`,
      );
    }
  }
  return openRows;
}

function renderKnownLimitations(openRows) {
  const lines = [];
  lines.push("# Known Limitations");
  lines.push("");
  lines.push(
    "This file is generated from the open rows of `.planning/WINDOWS.md` by " +
      "`tooling/generate-known-limitations.mjs`. Do not hand-edit it. Edit the ledger and " +
      "regenerate this file, or it will disagree with the ledger and fail the governance lane " +
      "the next time it is checked.",
  );
  lines.push("");
  if (openRows.length === 0) {
    lines.push("No known limitations are currently open.");
    lines.push("");
  } else {
    for (const row of openRows) {
      const location = row.file ? (row.line ? `${row.file}:${row.line}` : row.file) : null;
      const locationSuffix = location ? ` (\`${location}\`)` : "";
      lines.push(
        `- **[${row.phase}-${row.id}]**${locationSuffix} ${row.description} (owner: ${row.owner})`,
      );
    }
    lines.push("");
  }
  return lines.join("\n");
}

function selfTest() {
  const header =
    "| id | phase | kind | file | line | description | status | reason | recorded_at | resolved_at | owner |";
  const separator =
    "|----|-------|------|------|------|-------------|--------|--------|-------------|-------------| ------- |";
  const goodRow =
    "| 1 | 01 | deviation | file.ts |  | a fine, owned limitation | open |  | 2026-01-01T00:00:00.000Z |  | 01 |";
  const badRow =
    "| 2 | 01 | deviation | file.ts |  | a limitation with no owner | open |  | 2026-01-01T00:00:00.000Z |  |  |";

  const goodLedger = `${[header, separator, goodRow].join("\n")}\n`;
  const goodRows = parseLedger(goodLedger);
  const goodOpen = openLimitations(goodRows);
  if (goodOpen.length !== 1) {
    console.error("self-test failed: expected exactly one open row from the well-formed fixture");
    process.exit(1);
  }

  const badLedger = `${[header, separator, goodRow, badRow].join("\n")}\n`;
  let threw = false;
  try {
    openLimitations(parseLedger(badLedger));
  } catch {
    threw = true;
  }
  if (!threw) {
    console.error("self-test failed: an open row with an empty owner did not cause a non-zero exit");
    process.exit(1);
  }

  console.log(
    "Self-test passed: a well-formed open row is accepted, and an open row with an empty owner is rejected",
  );
}

function main() {
  const args = parseArgs(process.argv.slice(2));
  if (args.selfTest) {
    selfTest();
    return;
  }

  const scriptDir = path.dirname(fileURLToPath(import.meta.url));
  const repositoryRoot = path.resolve(scriptDir, "..");
  const ledgerPath = args.ledger
    ? path.resolve(args.ledger)
    : path.join(repositoryRoot, ".planning", "WINDOWS.md");
  const outPath = args.out ? path.resolve(args.out) : path.join(repositoryRoot, "KNOWN-LIMITATIONS.md");

  if (!existsSync(ledgerPath)) {
    console.error(`generator failure: ledger not found at ${ledgerPath}`);
    process.exit(1);
  }

  try {
    const text = readFileSync(ledgerPath, "utf8");
    const rows = parseLedger(text);
    const openRows = openLimitations(rows);
    const rendered = renderKnownLimitations(openRows);
    writeFileSync(outPath, rendered);
    console.log(`Generated ${outPath}: ${openRows.length} open limitation(s)`);
  } catch (error) {
    console.error(error.message);
    process.exit(1);
  }
}

main();
