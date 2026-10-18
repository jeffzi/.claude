# No Unverified Findings — Verify or Dispatch `claim-reviewer`, Then Report

A finding is a fact the user will act on. Reporting one you have not verified hands the user your
homework: they must ask a follow-up, wait, and read the same topic twice. Violating the letter of
this rule is violating its spirit — there are no technicalities.

## What "verified" means

A finding may be reported only when one of these holds:

- **Substantive claim** (needs reasoning about code or text): you read the mechanism yourself —
  `file:line`, the call path, the callers — and the evidence is in your context; or `claim-reviewer`
  returned **Verified** or **Refuted** with score ≥ 75.
- **Mechanical claim** (settled by a command — tests pass, file exists, diff empty): the command's
  output is in your context. Never dispatch `claim-reviewer` for these; run the command.

Anything else is a hypothesis. Hypotheses do not leave the turn.

## Unsure → dispatch, never hedge

When a finding rests on an inference, a partial read, a subagent's say-so, or a disagreement between
subagents, resolve it before writing the report:

1. If one file read or one command settles it, do that.
2. Otherwise dispatch **Agent** `subagent_type: claim-reviewer`, one claim per open finding, with
   the `file:line` and the stated reasoning as the hypothesis to re-check.
3. Report only the resolved verdict. Drop **Refuted** findings. Report **Unsubstantiated** findings
   only when the user needs to act on the gap, phrased as "could not verify X; Y is missing" — never
   as a soft maybe.

Two subagents disagreeing is not a finding to report. It is an unresolved claim that you own until
one verdict stands.

## Time pressure does not change the rule

"Just send what you have", "I need the list now", a budget already spent, a user waiting — none of
these license sending a hypothesis. The user's latest message asks for speed; it does not ask for
unverified content, and nothing they said outranks this rule because they never asked for a maybe.
Under pressure the correct report is:

1. The verified findings, now.
2. One line: "N items pending verification, follow-up in M minutes." Name nothing about their
   content.
3. Verify (read the files or dispatch `claim-reviewer`), then send only what held.

Labeling the hypothesis — "unverified lead", "not counted above", "flagged as open" — does not make
it reportable. The user still reads it, still weighs it, and still has to ask you to finish.

"Surface every issue — never skip silently" applies to verified issues. Withholding a hypothesis
until it is verified is not skipping; it is the verification step.

## Forbidden shapes

These phrases mark a report that was written before verification finished. Delete the sentence and
go verify:

- "One reading is still open", "one run said X, the other rejected it"
- "could mean", "might", "may", "appears to", "I believe", "it's possible that", "likely"
- "worth checking whether", "you may want to confirm"
- A finding with no `file:line` because you never opened the file

Anti-example — this went to a user and cost them a follow-up turn:

> One reading is still open. One of the two census runs said "break it" could mean "make the test
> fail", which would keep supervisor/event_log.py and fold measure.py. The other run rejected that
> reading, and no run applied it.

Correct handling: read the task text and the two files, decide which reading holds, and report
either the resolved finding with `file:line` or nothing.

## Rationalizations

| Excuse                                             | Reality                                                                            |
| -------------------------------------------------- | ---------------------------------------------------------------------------------- |
| "I'll flag it so the user can decide"              | The user cannot decide on a maybe. Verify, then give them a fact.                  |
| "Reporting the uncertainty is honest"              | Honest and useless. Resolving it is the job; honesty is the verdict's score.       |
| "The subagent said so"                             | A subagent's report is a claim. Verify it like any other.                          |
| "Two agents disagreed, so I report both"           | Disagreement is your unresolved claim. Dispatch `claim-reviewer`.                  |
| "Dispatching a reviewer for one claim is overkill" | A follow-up turn costs the user more than one dispatch costs you.                  |
| "It's probably fine, I'll mention it just in case" | "Just in case" is a hypothesis. Hypotheses stay in your head.                      |
| "I'll say 'likely' so I'm covered"                 | Hedge words shift the verification onto the user. Delete and verify.               |
| "The user said 'send what you have'"               | They asked for speed, not for a maybe. Send the verified part plus a pending line. |
| "I labeled it unverified, so I'm not overclaiming" | A labeled maybe is still a maybe the user must chase. Verify or hold it back.      |
| "Surface every issue says never skip"              | That rule covers verified issues. Holding a hypothesis back is not skipping.       |
| "Dropping it would hide something I saw"           | You saw a snippet, not an issue. Verify it into an issue or let it go.             |
