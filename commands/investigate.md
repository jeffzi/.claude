---
name: investigate
description: >
  Systematic root cause investigation for bugs, test failures, crashes, or unexpected behavior.
  Diagnosis only — does not fix anything.
argument-hint: "[error message, symptom, or failing test]"
---

# Investigate

Load the investigate skill via `Skill(investigate)` and apply it to the provided symptom or error.

Run all three phases (Root Cause Investigation, Pattern Analysis, Hypothesis Testing) and output a
confirmed root cause statement with evidence. Do not attempt any fix — investigation ends with
diagnosis.
