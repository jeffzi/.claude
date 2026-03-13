---
name: upgrade-ts
description: Use when upgrading TypeScript dependencies in package.json and lock file
allowed-tools: Read, Grep, Edit, Bash(npm update:*), Bash(npm outdated:*), Bash(npm install:*), Bash(npm list:*), Bash(npx tsc:*), Bash(npx biome:*), Bash(npx vitest:*)
---

# Upgrade All TypeScript Dependencies

Upgrade all project dependencies while keeping package.json version ranges current.

## Task Tracking

**Create task list at start** using TaskCreate for progress tracking:

| Task subject                    | activeForm (spinner text)    |
| ------------------------------- | ---------------------------- |
| Upgrade lock file               | Upgrading dependencies       |
| Update package.json constraints | Updating version constraints |
| Run type checks                 | Running type checks          |
| Run lint and format checks      | Running lint checks          |
| Run tests                       | Running tests                |

Update tasks with TaskUpdate as you progress:

- Set `status: in_progress` when starting each phase (shows spinner with activeForm text)
- Set `status: completed` when done (shows checkmark)
- If a conditional step is skipped (e.g., no changes needed), mark it completed immediately

## Pinning Strategy

- **Caret** (`^MAJOR.MINOR.0`) — default for all dependencies. Lower bound is the installed
  major.minor with patch set to 0 (e.g., installed 2.4.4 → `^2.4.0`). This avoids noise from patch
  bumps while documenting the minimum minor version required. For 0.x, same rule applies: installed
  0.5.3 → `^0.5.0`.
- **Exact** (no prefix, `X.Y.Z`) — only for tools that must match exact versions across config files
  (e.g., biome version pinned in both package.json and biome.json).
- **Floor** (`>=X.Y.Z`) — for peerDependencies only. No upper bound, since peer deps should be
  permissive and let the consumer choose the version.

## Steps

1. Run `npm update` to upgrade all packages within existing `^` ranges (updates lock file only, does
   not modify package.json)

2. Run `npm outdated` to check for packages where the latest version falls outside the current range
   (typically major version bumps, or minor bumps for 0.x packages)

3. For packages shown as outdated: update the version range in package.json using caret with patch
   dropped — `^MAJOR.MINOR.0` (e.g., latest is 3.2.1 → `^3.2.0`). Skip exact pins — those are for
   tools shared across config files. If no packages are outdated, skip to step 6.

4. Run `npm install` to regenerate the lock file with the updated constraints

5. Find all dependencies explicitly mentioned in package.json. Use `npm list --depth=0` to show the
   packages that are now installed. Update caret ranges to `^MAJOR.MINOR.0` based on the installed
   version. This covers two cases: raising the minor floor (e.g., `^2.0.0` with 2.4.4 installed →
   `^2.4.0`) and normalizing stale patch pins (e.g., `^2.4.4` → `^2.4.0`). Leave ranges alone when
   they already match the `^MAJOR.MINOR.0` pattern and the minor hasn't changed. Skip exact pins. If
   no changes needed, skip to step 7.

6. Run `npm install` again to ensure the updated constraints work (skip if no changes were made)

7. Run `npx tsc --noEmit` to verify type checking passes. Fix any type errors introduced by upgraded
   packages.

8. Run `npx biome check --write .` and fix any remaining issues (run again if files were modified by
   auto-fixes)

9. Run `npx vitest run` to verify all tests still pass (if test files exist)

## Important Notes

- DO NOT upgrade to pre-release or alpha versions. Upgrade only to stable versions.
- For major version bumps, check the library's migration guide before accepting the upgrade
- If type errors arise from upgraded `@types` packages, ensure the `@types` version aligns with the
  corresponding library version
- Preserve all comments in package.json

## Files Included in Context

@package.json
