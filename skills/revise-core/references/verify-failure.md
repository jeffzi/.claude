# Verify Failure — Step 5

Read this when a leaf check fails in step 5, before touching any file.

1. **Find the culprits.** Every revert below is a trial: re-run the failing check after it.
   - **The failure output names files.** Suspect the findings that edited them. One suspect → it is
     the culprit. Several → revert one at a time; the one whose revert turns the check green is the
     culprit, and each other suspect is re-applied.
   - **It names none, or the suspects are innocent.** Revert one transitive file group at a time;
     the group whose revert turns the check green holds the culprit. Narrow the same way to the
     finding inside it, and re-apply every group and finding that turned out innocent.
   - **No single revert turns it green.** Revert every fix in the run. Still red → the failure
     predates the run: re-apply every fix, report the check as already failing, and stop looping.
     Green → the fixes interact: re-apply groups one at a time, re-running after each. A group whose
     re-application turns the check red holds a culprit: revert it again, narrow to its finding the
     same way, and carry on with the remaining groups.
2. **Revert only the culprits, with inverse edits.** Never `git restore`, `git checkout` or `git
   stash`: they discard the user's unrelated uncommitted work, even in a file that looks like it
   holds only this run's change.
3. **Mark each culprit** `report-only: verify failed — <failing check>` in the checkpoint.
4. **Re-run every leaf check** until all pass. Step 5 is done when every check passes and every
   finding still `fixed` survived that passing run — or when the failure predates the run, as above.
