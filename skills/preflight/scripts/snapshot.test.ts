// CommonJS `require` is deliberate: ~/.claude/package.json declares
// {"type":"commonjs"}, so every .ts file under it loads as CJS.
const { spawnSync }: typeof import("node:child_process") = require("node:child_process");
const fs: typeof import("node:fs") = require("node:fs");
const os: typeof import("node:os") = require("node:os");
const path: typeof import("node:path") = require("node:path");
const assert: typeof import("node:assert/strict") = require("node:assert/strict");
const { afterEach, beforeEach, describe, it }: typeof import("node:test") = require("node:test");

const SCRIPT = path.join(__dirname, "snapshot.ts");

interface CliResult {
  status: number;
  stdout: string;
  stderr: string;
}

let root: string;
let repo: string;
let snapDir: string;

beforeEach(() => {
  root = fs.mkdtempSync(path.join(os.tmpdir(), "snapshot-test-"));
  repo = path.join(root, "repo");
  // Nested under a non-existent parent: `save` must create the whole chain.
  snapDir = path.join(root, "scratch", "preflight-snap-1");
  fs.mkdirSync(repo, { recursive: true });
});

afterEach(() => {
  fs.rmSync(root, { recursive: true, force: true });
});

function runCli(args: string[]): CliResult {
  const result = spawnSync(process.execPath, [SCRIPT, ...args], {
    cwd: repo,
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

function write(relative: string, contents: string): void {
  const target = path.join(repo, relative);
  fs.mkdirSync(path.dirname(target), { recursive: true });
  fs.writeFileSync(target, contents);
}

function read(relative: string): string {
  return fs.readFileSync(path.join(repo, relative), "utf8");
}

function exists(relative: string): boolean {
  return fs.existsSync(path.join(repo, relative));
}

function saveFiles(files: Record<string, string>): CliResult {
  for (const [relative, contents] of Object.entries(files)) {
    write(relative, contents);
  }
  return runCli(["save", snapDir, ...Object.keys(files)]);
}

function tarEntries(): string[] {
  const listing = spawnSync("tar", ["tf", path.join(snapDir, "files.tar")], {
    encoding: "utf8",
  });
  if (listing.error !== undefined) {
    throw listing.error;
  }
  assert.equal(listing.status, 0, listing.stderr);
  return listing.stdout
    .split("\n")
    .filter((line) => line !== "")
    .sort();
}

function manifest(): unknown {
  return JSON.parse(fs.readFileSync(path.join(snapDir, "manifest.json"), "utf8"));
}

function singleLine(output: string): string {
  const trimmed = output.trim();
  assert.ok(trimmed !== "", "expected a summary line on stdout");
  assert.equal(trimmed.includes("\n"), false, `expected one summary line, got: ${trimmed}`);
  return trimmed;
}

describe("snapshot save", () => {
  it("writes a snapshot of the named files", () => {
    const result = saveFiles({ "a.txt": "A", "sub/b.txt": "B" });

    assert.equal(result.status, 0, result.stderr);
    assert.deepEqual(manifest(), ["a.txt", "sub/b.txt"]);
    assert.deepEqual(tarEntries(), ["a.txt", "sub/b.txt"]);
    assert.match(singleLine(result.stdout), /saved\D*2\D+files/i);
  });

  describe("when a named file is missing", () => {
    it("fails without writing a partial snapshot", () => {
      write("a.txt", "A");

      const result = runCli(["save", snapDir, "a.txt", "missing.txt"]);

      assert.equal(result.status, 1);
      assert.match(result.stderr, /missing\.txt/);
      assert.equal(fs.existsSync(path.join(snapDir, "files.tar")), false);
      assert.equal(fs.existsSync(path.join(snapDir, "manifest.json")), false);
    });
  });
});

describe("snapshot restore", () => {
  it("overwrites current contents with the snapshotted versions", () => {
    saveFiles({ "a.txt": "A", "sub/b.txt": "B" });
    write("a.txt", "edited A");
    write("sub/b.txt", "edited B");

    const result = runCli(["restore", snapDir]);

    assert.equal(result.status, 0, result.stderr);
    assert.equal(read("a.txt"), "A");
    assert.equal(read("sub/b.txt"), "B");
    assert.match(singleLine(result.stdout), /restored\D*2/i);
  });

  const brokenSnapshots = [
    {
      name: "the snapshot directory does not exist",
      prepare: (): void => {},
      stderrPattern: /preflight-snap-1/,
    },
    {
      name: "the snapshot directory has no archive",
      prepare: (): void => fs.mkdirSync(snapDir, { recursive: true }),
      stderrPattern: /files\.tar/,
    },
  ];

  for (const snapshotCase of brokenSnapshots) {
    describe(`when ${snapshotCase.name}`, () => {
      it("fails with a message on stderr", () => {
        snapshotCase.prepare();

        const result = runCli(["restore", snapDir]);

        assert.equal(result.status, 1);
        assert.match(result.stderr, snapshotCase.stderrPattern);
      });
    });
  }

  describe("with --edited", () => {
    it("returns the tree to its snapshotted state", () => {
      saveFiles({ "a.txt": "A" });
      write("a.txt", "edited A");
      write("created.txt", "new");

      const result = runCli(["restore", snapDir, "--edited", "a.txt", "created.txt"]);

      assert.equal(result.status, 0, result.stderr);
      assert.equal(read("a.txt"), "A");
      assert.equal(exists("created.txt"), false);
      assert.match(singleLine(result.stdout), /restored\D*1\D+deleted\D*1/i);
    });
  });

  describe("with --only", () => {
    it("restores only the files listed", () => {
      saveFiles({ "a.txt": "A", "b.txt": "B" });
      write("a.txt", "edited A");
      write("b.txt", "edited B");

      const result = runCli(["restore", snapDir, "--only", "a.txt"]);

      assert.equal(result.status, 0, result.stderr);
      assert.equal(read("a.txt"), "A");
      assert.equal(read("b.txt"), "edited B");
    });

    describe("when no files are listed", () => {
      it("fails instead of silently restoring nothing", () => {
        saveFiles({ "a.txt": "A" });
        write("a.txt", "edited A");

        const result = runCli(["restore", snapDir, "--only"]);

        assert.equal(result.status, 1);
        assert.match(result.stderr, /--only/);
        assert.match(result.stderr, /at least one file/i);
        assert.equal(read("a.txt"), "edited A");
      });
    });

    describe("when --edited is also given", () => {
      it("deletes only the listed created files", () => {
        saveFiles({ "a.txt": "A" });
        write("created-listed.txt", "new");
        write("created-other.txt", "new");

        const result = runCli([
          "restore",
          snapDir,
          "--only",
          "created-listed.txt",
          "--edited",
          "created-listed.txt",
          "created-other.txt",
        ]);

        assert.equal(result.status, 0, result.stderr);
        assert.equal(exists("created-listed.txt"), false);
        assert.equal(exists("created-other.txt"), true);
      });
    });

    const unrecoverableCases: { name: string; editedArgs: string[] }[] = [
      { name: "no --edited is given", editedArgs: [] },
      { name: "--edited does not list it", editedArgs: ["--edited", "a.txt"] },
    ];

    for (const unrecoverableCase of unrecoverableCases) {
      describe(`when a listed file is absent from the manifest and ${unrecoverableCase.name}`, () => {
        it("fails without restoring the other listed files", () => {
          saveFiles({ "a.txt": "A" });
          write("a.txt", "edited A");

          const result = runCli([
            "restore",
            snapDir,
            "--only",
            "a.txt",
            "unknown.txt",
            ...unrecoverableCase.editedArgs,
          ]);

          assert.equal(result.status, 1);
          assert.match(result.stderr, /unknown\.txt/);
          assert.equal(read("a.txt"), "edited A");
          assert.equal(exists("unknown.txt"), false);
        });
      });
    }
  });
});
