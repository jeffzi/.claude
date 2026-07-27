// CommonJS `require` is deliberate: ~/.claude/package.json declares
// {"type":"commonjs"}, so every .ts file under it loads as CJS.
const { spawnSync }: typeof import("node:child_process") = require("node:child_process");
const fs: typeof import("node:fs") = require("node:fs");
const os: typeof import("node:os") = require("node:os");
const path: typeof import("node:path") = require("node:path");
const assert: typeof import("node:assert/strict") = require("node:assert/strict");
const { afterEach, beforeEach, describe, it }: typeof import("node:test") = require("node:test");

const SCRIPT = path.join(__dirname, "gate.ts");

interface CliResult {
  status: number;
  stdout: string;
  stderr: string;
}

let root: string;
let captureDir: string;

beforeEach(() => {
  root = fs.mkdtempSync(path.join(os.tmpdir(), "gate-test-"));
  // Nested under a non-existent parent: the gate must create the whole chain.
  captureDir = path.join(root, "scratch", "captures");
});

afterEach(() => {
  fs.rmSync(root, { recursive: true, force: true });
});

function runGate(args: string[]): CliResult {
  const result = spawnSync(process.execPath, [SCRIPT, ...args], {
    cwd: root,
    encoding: "utf8",
  });
  if (result.error !== undefined) {
    throw result.error;
  }
  return {
    status: result.status ?? -1,
    stdout: result.stdout,
    stderr: result.stderr,
  };
}

function capturePath(name: string): string {
  return path.join(captureDir, name);
}

function capture(name: string): string {
  return fs.readFileSync(capturePath(name), "utf8");
}

function captureExists(name: string): boolean {
  return fs.existsSync(capturePath(name));
}

function lines(stdout: string): string[] {
  return stdout.trim().split("\n");
}

describe("gate", () => {
  it("reports a green verdict with both halves captured in full", () => {
    const result = runGate([
      captureDir,
      "entry",
      "echo checker-out; echo checker-err >&2",
      "echo test-out",
    ]);

    assert.equal(result.status, 0, result.stderr);
    assert.deepEqual(lines(result.stdout), [
      `CHECKERS: PASS (exit 0) -> ${capturePath("gate-entry-checkers.txt")}`,
      `TESTS: PASS (exit 0) -> ${capturePath("gate-entry-tests.txt")}`,
      "GATE: GREEN",
    ]);
    assert.match(capture("gate-entry-checkers.txt"), /checker-out/);
    assert.match(capture("gate-entry-checkers.txt"), /checker-err/);
    assert.equal(capture("gate-entry-tests.txt").trim(), "test-out");
  });

  describe("when the checker half fails", () => {
    it("reports a red verdict without skipping the test half", () => {
      const marker = path.join(root, "tests-ran");

      const result = runGate([captureDir, "entry", "echo boom; exit 3", `echo ran > "${marker}"`]);

      assert.equal(result.status, 1);
      assert.deepEqual(lines(result.stdout), [
        `CHECKERS: FAIL (exit 3) -> ${capturePath("gate-entry-checkers.txt")}`,
        `TESTS: PASS (exit 0) -> ${capturePath("gate-entry-tests.txt")}`,
        "GATE: RED",
        "FAILING: (unparsed — see captures)",
      ]);
      assert.equal(fs.existsSync(marker), true);
    });
  });

  describe("when the captures name failing sub-checks", () => {
    it("lists them deduplicated across both halves", () => {
      const checkerCmd = `printf 'ERROR: "lint" exited with 1\\nERROR: "lint" exited with 1\\n'; exit 1`;
      const testCmd = `printf 'ERROR: "lint" exited with 1\\nERROR: "unit" exited with 2\\n'; exit 1`;

      const result = runGate([captureDir, "exit", checkerCmd, testCmd]);

      assert.equal(result.status, 1);
      assert.deepEqual(lines(result.stdout), [
        `CHECKERS: FAIL (exit 1) -> ${capturePath("gate-exit-checkers.txt")}`,
        `TESTS: FAIL (exit 1) -> ${capturePath("gate-exit-tests.txt")}`,
        "GATE: RED",
        "FAILING: lint, unit",
      ]);
    });
  });

  describe("when captures for the name already exist", () => {
    it("numbers the re-run instead of overwriting them", () => {
      runGate([captureDir, "fix", "echo first-checkers", "echo first-tests"]);
      runGate([captureDir, "fix", "echo second-checkers", "echo second-tests"]);

      const result = runGate([captureDir, "fix", "echo third-checkers", "echo third-tests"]);

      assert.equal(result.status, 0, result.stderr);
      assert.deepEqual(lines(result.stdout).slice(0, 2), [
        `CHECKERS: PASS (exit 0) -> ${capturePath("gate-fix-checkers-3.txt")}`,
        `TESTS: PASS (exit 0) -> ${capturePath("gate-fix-tests-3.txt")}`,
      ]);
      assert.equal(capture("gate-fix-checkers.txt").trim(), "first-checkers");
      assert.equal(capture("gate-fix-checkers-2.txt").trim(), "second-checkers");
      assert.equal(capture("gate-fix-tests-3.txt").trim(), "third-tests");
    });

    it("keeps both halves on the same run number when an earlier run skipped one", () => {
      runGate([captureDir, "entry", "", "echo first-tests"]);

      const result = runGate([captureDir, "entry", "echo checkers", "echo second-tests"]);

      assert.equal(result.status, 0, result.stderr);
      assert.deepEqual(lines(result.stdout).slice(0, 2), [
        `CHECKERS: PASS (exit 0) -> ${capturePath("gate-entry-checkers-2.txt")}`,
        `TESTS: PASS (exit 0) -> ${capturePath("gate-entry-tests-2.txt")}`,
      ]);
      assert.equal(captureExists("gate-entry-checkers.txt"), false);
    });
  });

  describe("when a command is empty", () => {
    it("skips that half and gates on the other alone", () => {
      const result = runGate([captureDir, "entry", "echo ok", ""]);

      assert.equal(result.status, 0, result.stderr);
      assert.deepEqual(lines(result.stdout), [
        `CHECKERS: PASS (exit 0) -> ${capturePath("gate-entry-checkers.txt")}`,
        "TESTS: SKIPPED (no command)",
        "GATE: GREEN",
      ]);
      assert.equal(captureExists("gate-entry-tests.txt"), false);
    });
  });

  const setupErrors = [
    {
      name: "arguments are missing",
      prepare: (): void => {},
      args: (): string[] => [captureDir, "entry"],
      stderrPattern: /usage/i,
    },
    {
      name: "the capture directory cannot be created",
      prepare: (): void => {
        fs.mkdirSync(path.dirname(captureDir), { recursive: true });
        fs.writeFileSync(captureDir, "not a directory");
      },
      args: (): string[] => [captureDir, "entry", "echo ok", "echo ok"],
      stderrPattern: /captures/,
    },
  ];

  for (const setupCase of setupErrors) {
    describe(`when ${setupCase.name}`, () => {
      it("exits 2 with a message on stderr", () => {
        setupCase.prepare();

        const result = runGate(setupCase.args());

        assert.equal(result.status, 2);
        assert.match(result.stderr, setupCase.stderrPattern);
      });
    });
  }

  describe("when a capture file cannot be written", () => {
    afterEach(() => {
      if (fs.existsSync(captureDir)) {
        fs.chmodSync(captureDir, 0o755);
      }
    });

    it("exits 2 rather than reporting a red gate", () => {
      fs.mkdirSync(captureDir, { recursive: true });
      fs.chmodSync(captureDir, 0o555);

      const result = runGate([captureDir, "entry", "echo ok", "echo ok"]);

      assert.equal(result.status, 2);
      assert.match(result.stderr, /captures/);
      assert.doesNotMatch(result.stdout, /GATE:/);
    });
  });
});
