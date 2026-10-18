import { mkdirSync, mkdtempSync, rmSync, utimesSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { dirname, join } from "node:path";

import { afterEach, describe, expect, it } from "vitest";

import { checkCoverageFresh } from "../scripts/check-coverage-fresh.js";

const COVERAGE_MTIME = 1_700_000_000;
const OLDER = COVERAGE_MTIME - 100;
const NEWER = COVERAGE_MTIME + 100;

const projects: string[] = [];

afterEach(() => {
  for (const dir of projects.splice(0)) {
    rmSync(dir, { recursive: true, force: true });
  }
});

/** Writes a file, creating parent directories, and sets its mtime (seconds). */
function writeFileWithMtime(path: string, content: string, mtime: number): void {
  mkdirSync(dirname(path), { recursive: true });
  writeFileSync(path, content);
  utimesSync(path, mtime, mtime);
}

/** Builds a throwaway project with the given files (relative path → mtime in seconds) and an optional coverage report. */
function createProject(files: Record<string, number>, coverageMtime?: number): string {
  const dir = mkdtempSync(join(tmpdir(), "ecstatic-coverage-"));
  projects.push(dir);
  for (const [relative, mtime] of Object.entries(files)) {
    writeFileWithMtime(join(dir, relative), "", mtime);
  }
  if (coverageMtime !== undefined) {
    writeFileWithMtime(join(dir, "coverage", "coverage-final.json"), "{}", coverageMtime);
  }
  return dir;
}

describe("checkCoverageFresh", () => {
  describe("when no coverage report exists", () => {
    it("returns without throwing", () => {
      const dir = createProject({ "src/world.ts": NEWER });

      expect(() => {
        checkCoverageFresh(dir);
      }).not.toThrow();
    });
  });

  describe("when no source file is newer than the coverage report", () => {
    it("returns without throwing", () => {
      const dir = createProject(
        {
          "src/world.ts": OLDER,
          "src/entity/spawn.ts": OLDER,
          "src/query.ts": COVERAGE_MTIME,
        },
        COVERAGE_MTIME,
      );

      expect(() => {
        checkCoverageFresh(dir);
      }).not.toThrow();
    });
  });

  describe("when a source file is newer than the coverage report", () => {
    it.each(["src/query.ts", "src/entity/spawn.ts"])("throws naming %s", (stale) => {
      const dir = createProject({ "src/world.ts": OLDER, [stale]: NEWER }, COVERAGE_MTIME);

      expect(() => {
        checkCoverageFresh(dir);
      }).toThrow(stale);
    });

    it("tells the user to run npm test before npm run check", () => {
      const dir = createProject({ "src/world.ts": NEWER }, COVERAGE_MTIME);

      expect(() => {
        checkCoverageFresh(dir);
      }).toThrow(/npm test.*npm run check/s);
    });
  });

  describe("when only files that are not TypeScript sources are newer", () => {
    it.each(["src/notes.md", "src/types.d.ts"])("ignores %s", (ignored) => {
      const dir = createProject({ "src/world.ts": OLDER, [ignored]: NEWER }, COVERAGE_MTIME);

      expect(() => {
        checkCoverageFresh(dir);
      }).not.toThrow();
    });
  });
});
