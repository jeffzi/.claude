import { readdirSync, statSync } from "node:fs";
import { join, relative, resolve, sep } from "node:path";
import { fileURLToPath } from "node:url";

const COVERAGE_REPORT = "coverage/coverage-final.json";

function isSourceFile(name: string): boolean {
  return name.endsWith(".ts") && !name.endsWith(".d.ts");
}

/**
 * Verify that `coverage/coverage-final.json` is at least as recent as every `.ts` source under
 * `src/` (declaration files excluded).
 *
 * A missing coverage report passes so a clean checkout that has not run `npm test` is not blocked;
 * fallow estimates coverage itself in that case. Throwing here would fail the hook before fallow
 * runs.
 *
 * @param projectRoot - Directory holding `src/` and `coverage/`; the CLI passes `process.cwd()`.
 * @throws Error naming every source file modified after the coverage report was written, each as
 * a path relative to `projectRoot` with forward slashes on every platform; a missing `src/`
 * directory or any other filesystem failure propagates as the filesystem error itself.
 */
export function checkCoverageFresh(projectRoot: string): void {
  const coverage = statSync(join(projectRoot, COVERAGE_REPORT), { throwIfNoEntry: false });
  if (coverage === undefined) {
    return;
  }

  const stale: string[] = [];
  const entries = readdirSync(join(projectRoot, "src"), { recursive: true, withFileTypes: true });
  for (const entry of entries) {
    if (!entry.isFile() || !isSourceFile(entry.name)) {
      continue;
    }
    const path = join(entry.parentPath, entry.name);
    if (statSync(path).mtimeMs > coverage.mtimeMs) {
      stale.push(relative(projectRoot, path).replaceAll(sep, "/"));
    }
  }

  if (stale.length > 0) {
    stale.sort();
    throw new Error(
      `${COVERAGE_REPORT} is older than ${stale.join(", ")} — run: npm test, then npm run check`,
    );
  }
}

if (resolve(process.argv[1] ?? "") === fileURLToPath(import.meta.url)) {
  checkCoverageFresh(process.cwd());
}
