#!/usr/bin/env node

function fail(message) {
  console.error(`CI result summary failed: ${message}`);
  return false;
}

export function verifyJobResults({ needs, impactJob, alwaysJobs, conditionalJobs }) {
  const impact = needs?.[impactJob];
  if (!impact) return fail(`impact job ${impactJob} is missing from needs`);
  if (impact.result !== "success") {
    return fail(`impact job ${impactJob} did not succeed (result=${impact.result})`);
  }

  const runHeavy = impact.outputs?.run_heavy !== "false";
  const expectedJobs = [impactJob, ...alwaysJobs, ...conditionalJobs].sort();
  const actualJobs = Object.keys(needs ?? {}).sort();
  if (JSON.stringify(expectedJobs) !== JSON.stringify(actualJobs)) {
    return fail(
      `needs job set differs from the declared summary contract (expected=${expectedJobs.join(",")} actual=${actualJobs.join(",")})`,
    );
  }

  let passed = true;
  for (const job of alwaysJobs) {
    const result = needs[job]?.result;
    console.log(`summary job=${job} class=always result=${result}`);
    if (result !== "success") {
      fail(`always-run job ${job} did not succeed (result=${result})`);
      passed = false;
    }
  }

  const expectedConditionalResult = runHeavy ? "success" : "skipped";
  for (const job of conditionalJobs) {
    const result = needs[job]?.result;
    console.log(
      `summary job=${job} class=${runHeavy ? "full" : "docs-only"} result=${result}`,
    );
    if (result !== expectedConditionalResult) {
      fail(
        `conditional job ${job} must be ${expectedConditionalResult} when run_heavy=${String(runHeavy)} (result=${result})`,
      );
      passed = false;
    }
  }

  if (passed) {
    console.log(`CI result summary passed: full_checks=${String(runHeavy)}`);
  }
  return passed;
}

function makeNeeds({ runHeavy, impactResult = "success", override = {} }) {
  const needs = {
    "pr-impact": { result: impactResult, outputs: { run_heavy: String(runHeavy) } },
    cheap: { result: "success" },
    heavy: { result: runHeavy ? "success" : "skipped" },
    ...override,
  };
  return needs;
}

function runSelfTest() {
  const base = { impactJob: "pr-impact", alwaysJobs: ["cheap"], conditionalJobs: ["heavy"] };
  const cases = [
    ["docs-only skips heavy work", makeNeeds({ runHeavy: false }), true],
    ["full suite succeeds", makeNeeds({ runHeavy: true }), true],
    ["full suite cannot skip", makeNeeds({ runHeavy: true, override: { heavy: { result: "skipped" } } }), false],
    ["docs skip cannot fail", makeNeeds({ runHeavy: false, override: { heavy: { result: "failure" } } }), false],
    ["cheap check cannot skip", makeNeeds({ runHeavy: false, override: { cheap: { result: "skipped" } } }), false],
    ["classifier failure cannot pass", makeNeeds({ runHeavy: true, impactResult: "failure" }), false],
    ["missing impact output runs full checks", makeNeeds({ runHeavy: true, override: { "pr-impact": { result: "success", outputs: {} } } }), true],
    ["undeclared dependency fails contract", { ...makeNeeds({ runHeavy: true }), surprise: { result: "success" } }, false],
  ];

  const originalLog = console.log;
  const originalError = console.error;
  console.log = () => {};
  console.error = () => {};
  try {
    for (const [name, needs, expected] of cases) {
      const actual = verifyJobResults({ needs, ...base });
      if (actual !== expected) throw new Error(`${name}: expected ${expected}, received ${actual}`);
    }
  } finally {
    console.log = originalLog;
    console.error = originalError;
  }
  console.log(`CI result summary self-test passed: cases=${cases.length}`);
}

function parseListArgument(name) {
  const prefix = `${name}=`;
  const value = process.argv.find((argument) => argument.startsWith(prefix))?.slice(prefix.length);
  if (value === undefined || value.length === 0) return [];
  return value.split(",").filter(Boolean);
}

if (process.argv.includes("--self-test")) {
  runSelfTest();
} else {
  try {
    const needs = JSON.parse(process.env.NEEDS_CONTEXT ?? "null");
    const impactJob = process.argv.find((argument) => argument.startsWith("--impact-job="))?.slice("--impact-job=".length);
    if (!needs || typeof needs !== "object" || !impactJob) {
      throw new Error("NEEDS_CONTEXT or --impact-job is missing");
    }
    const passed = verifyJobResults({
      needs,
      impactJob,
      alwaysJobs: parseListArgument("--always"),
      conditionalJobs: parseListArgument("--conditional"),
    });
    if (!passed) process.exitCode = 1;
  } catch (error) {
    console.error(`CI result summary could not verify results: ${error.message}`);
    process.exitCode = 1;
  }
}
