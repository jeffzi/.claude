/**
 * Quality-gate runner for the preflight pipeline.
 *
 * Run directly with node (>= 22.18 for native type stripping), no build step and no dependencies:
 *
 * ```bash
 * node gate.ts <captureDir> <name> <checkerCmd> <testCmd>
 * ```
 *
 * Runs the checker half and the test half through `sh -c`, capturing each command's full
 * output (stdout and stderr, interleaved) into `<captureDir>/gate-<name>-checkers.txt` and
 * `<captureDir>/gate-<name>-tests.txt`. Both halves always run: a red checker half never
 * skips the tests. Re-runs under the same name are numbered (`-2`, `-3`, …) rather than
 * overwriting earlier captures, and both halves always share one run number. Either command
 * may be empty, which reports that half as skipped and leaves it out of the verdict.
 *
 * The verdict goes to stdout, one line each:
 *
 * ```text
 * CHECKERS: PASS|FAIL (exit <code>) -> <capture path>
 * TESTS: PASS|FAIL (exit <code>) -> <capture path>
 * GATE: GREEN|RED
 * FAILING: <sub-check names>          # red gates only
 * ```
 *
 * Exit code: 0 for a green gate, 1 for a red one, 2 for a usage or setup error.
 *
 * CommonJS `require` is deliberate: ~/.claude/package.json declares {"type":"commonjs"},
 * so every .ts file under it loads as CJS.
 */

const { spawnSync }: typeof import("node:child_process") = require("node:child_process");
const fs: typeof import("node:fs") = require("node:fs");
const path: typeof import("node:path") = require("node:path");

const USAGE = "usage: node gate.ts <captureDir> <name> <checkerCmd> <testCmd>";

/** npm-run-s prints one of these per failed sub-check. */
const SUBCHECK_PATTERN = /^ERROR: "(.+)" exited with \d+/gm;

type HalfOutcome =
  | { kind: "skipped" }
  | { kind: "ran"; code: number; capturePath: string; failing: string[] };

function failSetup(message: string): never {
  process.stderr.write(`${message}\n`);
  process.exit(2);
}

function captureName(name: string, half: string, run: number): string {
  const suffix = run === 1 ? "" : `-${run}`;
  return `gate-${name}-${half}${suffix}.txt`;
}

/** Lowest run number whose captures are both free, so no earlier run is overwritten. */
function nextRun(captureDir: string, name: string): number {
  let run = 1;
  while (
    fs.existsSync(path.join(captureDir, captureName(name, "checkers", run))) ||
    fs.existsSync(path.join(captureDir, captureName(name, "tests", run)))
  ) {
    run += 1;
  }
  return run;
}

function parseFailing(capture: string): string[] {
  const names: string[] = [];
  for (const [, subcheck] of capture.matchAll(SUBCHECK_PATTERN)) {
    if (subcheck !== undefined) {
      names.push(subcheck);
    }
  }
  return names;
}

function runHalf(command: string, capturePath: string): HalfOutcome {
  if (command.trim() === "") {
    return { kind: "skipped" };
  }

  // The child writes straight into the capture file: no buffer ceiling on the output, and
  // stdout and stderr stay interleaved in the order the command produced them.
  let handle: number | null = null;
  try {
    handle = fs.openSync(capturePath, "w");
    const result = spawnSync("sh", ["-c", command], { stdio: ["ignore", handle, handle] });
    if (result.error !== undefined) {
      failSetup(`cannot run command: ${result.error.message}`);
    }
    // A signal-killed command has no exit code; report it as a plain failure.
    const code: number = result.status ?? 1;
    const failing = code === 0 ? [] : parseFailing(fs.readFileSync(capturePath, "utf8"));
    return { kind: "ran", code, capturePath, failing };
  } catch (error) {
    // A capture file that cannot be opened or read is an infrastructure failure, not a
    // verdict: exiting 1 here would tell the caller the gate is red.
    const reason = error instanceof Error ? error.message : String(error);
    failSetup(`cannot write capture file ${capturePath}: ${reason}`);
  } finally {
    if (handle !== null) {
      fs.closeSync(handle);
    }
  }
}

function verdictLine(label: string, outcome: HalfOutcome): string {
  if (outcome.kind === "skipped") {
    return `${label}: SKIPPED (no command)`;
  }
  const status = outcome.code === 0 ? "PASS" : "FAIL";
  return `${label}: ${status} (exit ${outcome.code}) -> ${outcome.capturePath}`;
}

function main(argv: string[]): void {
  const [captureDir, name, checkerCmd, testCmd] = argv;
  if (
    argv.length !== 4 ||
    captureDir === undefined ||
    name === undefined ||
    checkerCmd === undefined ||
    testCmd === undefined
  ) {
    failSetup(USAGE);
  }

  try {
    fs.mkdirSync(captureDir, { recursive: true });
  } catch (error) {
    const reason = error instanceof Error ? error.message : String(error);
    failSetup(`cannot create capture directory ${captureDir}: ${reason}`);
  }

  const run = nextRun(captureDir, name);
  const checkers = runHalf(checkerCmd, path.join(captureDir, captureName(name, "checkers", run)));
  const tests = runHalf(testCmd, path.join(captureDir, captureName(name, "tests", run)));

  const halves = [checkers, tests];
  const red = halves.some((half) => half.kind === "ran" && half.code !== 0);
  const lines = [
    verdictLine("CHECKERS", checkers),
    verdictLine("TESTS", tests),
    `GATE: ${red ? "RED" : "GREEN"}`,
  ];
  if (red) {
    const failing = [
      ...new Set(halves.flatMap((half) => (half.kind === "ran" ? half.failing : []))),
    ];
    lines.push(`FAILING: ${failing.length > 0 ? failing.join(", ") : "(unparsed — see captures)"}`);
  }

  process.stdout.write(`${lines.join("\n")}\n`);
  process.exit(red ? 1 : 0);
}

main(process.argv.slice(2));
