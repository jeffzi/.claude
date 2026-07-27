/**
 * Snapshot/restore CLI for the preflight pipeline.
 *
 * Run directly with node (>= 22.18 for native type stripping), no build step and no dependencies:
 *
 * ```bash
 * node snapshot.ts save <snapDir> <file...>
 * node snapshot.ts restore <snapDir> [--only <file...>] [--edited <file...>]
 * ```
 *
 * `save` archives the named files (relative to the current directory) into
 * `<snapDir>/files.tar` and records the list in `<snapDir>/manifest.json`.
 * `restore` extracts the archive back over the current directory. `--only` narrows the
 * restore to the listed files; `--edited` additionally deletes files that were created
 * after the snapshot was taken (present in the edited list, absent from the manifest).
 *
 * All paths are handled relative to the process working directory, which must be the same
 * directory the snapshot was saved from.
 *
 * CommonJS `require` is deliberate: ~/.claude/package.json declares {"type":"commonjs"},
 * so every .ts file under it loads as CJS.
 */

const { spawnSync }: typeof import("node:child_process") = require("node:child_process");
const fs: typeof import("node:fs") = require("node:fs");
const path: typeof import("node:path") = require("node:path");

const TAR_NAME = "files.tar";
const MANIFEST_NAME = "manifest.json";

interface RestoreArgs {
  snapDir: string;
  only: string[] | null;
  edited: string[];
}

function fail(message: string): never {
  process.stderr.write(`${message}\n`);
  process.exit(1);
}

function plural(count: number): string {
  return count === 1 ? "file" : "files";
}

function runTar(args: string[]): void {
  const result = spawnSync("tar", args, { encoding: "utf8" });
  if (result.error !== undefined) {
    fail(`tar failed: ${result.error.message}`);
  }
  if (result.status !== 0) {
    fail(`tar failed (exit ${result.status}): ${result.stderr.trim()}`);
  }
}

function isStringArray(value: unknown): value is string[] {
  return Array.isArray(value) && value.every((entry) => typeof entry === "string");
}

function readManifest(snapDir: string): string[] {
  const manifestPath = path.join(snapDir, MANIFEST_NAME);
  if (!fs.existsSync(manifestPath)) {
    fail(`snapshot manifest not found: ${manifestPath}`);
  }
  const parsed: unknown = JSON.parse(fs.readFileSync(manifestPath, "utf8"));
  if (!isStringArray(parsed)) {
    fail(`snapshot manifest is not a list of file paths: ${manifestPath}`);
  }
  return parsed;
}

function save(snapDir: string, files: string[]): void {
  if (files.length === 0) {
    fail("save requires at least one file");
  }

  // Validate before creating anything: a failed save must leave no partial snapshot.
  const missing = files.filter((file) => !fs.existsSync(file));
  if (missing.length > 0) {
    fail(`cannot snapshot missing ${plural(missing.length)}: ${missing.join(", ")}`);
  }

  fs.mkdirSync(snapDir, { recursive: true });
  runTar(["cf", path.join(snapDir, TAR_NAME), "--", ...files]);
  fs.writeFileSync(path.join(snapDir, MANIFEST_NAME), `${JSON.stringify(files, null, 2)}\n`);

  process.stdout.write(`Saved ${files.length} ${plural(files.length)} to ${snapDir}\n`);
}

function restore(args: RestoreArgs): void {
  const { snapDir, only, edited } = args;
  if (!fs.existsSync(snapDir)) {
    fail(`snapshot directory not found: ${snapDir}`);
  }
  const tarPath = path.join(snapDir, TAR_NAME);
  if (!fs.existsSync(tarPath)) {
    fail(`snapshot archive not found: ${tarPath}`);
  }

  const manifest = new Set(readManifest(snapDir));
  const scope = only ?? [...manifest];
  const toRestore = scope.filter((file) => manifest.has(file));
  const toDelete = edited.filter(
    (file) => !manifest.has(file) && (only === null || only.includes(file)),
  );

  // Validate before touching the tree: an explicitly named file that can neither be
  // restored nor deleted means the caller's expectation is wrong, and silently doing
  // nothing is the worst outcome for a recovery tool. All-or-nothing.
  if (only !== null) {
    const deletable = new Set(toDelete);
    const unrecoverable = only.filter((file) => !manifest.has(file) && !deletable.has(file));
    if (unrecoverable.length > 0) {
      fail(
        `cannot restore ${plural(unrecoverable.length)} absent from the snapshot manifest ` +
          `and not marked as created: ${unrecoverable.join(", ")}`,
      );
    }
  }

  if (toRestore.length > 0) {
    runTar(["xf", tarPath, "--", ...toRestore]);
  }
  for (const file of toDelete) {
    fs.rmSync(file, { force: true });
  }

  process.stdout.write(
    `Restored ${toRestore.length} ${plural(toRestore.length)}, ` +
      `deleted ${toDelete.length} ${plural(toDelete.length)}\n`,
  );
}

function parseRestoreArgs(rest: string[]): RestoreArgs {
  const [snapDir, ...flags] = rest;
  if (snapDir === undefined) {
    fail("restore requires a snapshot directory");
  }

  let only: string[] | null = null;
  const edited: string[] = [];
  let current: string[] | null = null;

  for (const token of flags) {
    if (token === "--only") {
      only = only ?? [];
      current = only;
    } else if (token === "--edited") {
      current = edited;
    } else if (current === null) {
      fail(`unexpected argument: ${token}`);
    } else {
      current.push(token);
    }
  }

  // An empty --only would restore nothing and delete nothing while still reporting success,
  // which for a recovery tool is indistinguishable from a completed restore.
  if (only !== null && only.length === 0) {
    fail("--only requires at least one file");
  }

  return { snapDir, only, edited };
}

function main(argv: string[]): void {
  const [command, ...rest] = argv;
  switch (command) {
    case "save": {
      const [snapDir, ...files] = rest;
      if (snapDir === undefined) {
        fail("save requires a snapshot directory");
      }
      save(snapDir, files);
      break;
    }
    case "restore":
      restore(parseRestoreArgs(rest));
      break;
    default:
      fail(
        "usage: node snapshot.ts save <snapDir> <file...>\n" +
          "       node snapshot.ts restore <snapDir> [--only <file...>] [--edited <file...>]",
      );
  }
}

main(process.argv.slice(2));
