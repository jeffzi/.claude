# Vision Document Exemplars

## Contents

- [Curated examples](#curated-examples) — Nushell, Redis, SQLite, Python, FastAPI, Go, htmx
- [Other strong examples](#other-strong-examples)
- [Vision vs mission vs principles](#vision-vs-mission-vs-principles)
- [Evidence and caveats](#evidence-and-caveats)

---

## Curated examples

| Project                                                 | Form                             | What it does well                                                                                                                                                                                                                                                                                    |
| ------------------------------------------------------- | -------------------------------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| **Nushell** — Philosophy page (Contributor Book)        | Core value + beliefs + non-goals | One warm core value ("working in a shell should be fun"), then four cold non-goals: optimal performance, strictness, POSIX-compliance, paradigm adherence. Each non-goal pre-empts a category of debate. Older versions kept ("Philosophy (0.80)") so the document is visibly versioned.             |
| **Redis** — MANIFESTO                                   | Ten numbered principles          | Each principle is a self-contained rule mixing a value with an engineering consequence: "Memory storage is #1", "We're against complexity" (one programmer should understand the source in a couple of weeks), "Threading is not a silver bullet". Numbering makes them citable: "this violates #6". |
| **SQLite** — About + Appropriate Uses                   | Positioning + timescale          | "Small. Fast. Reliable. Choose any three." "SQLite does not compete with client/server databases. SQLite competes with fopen()." A two-column where-it-works / where-a-client-server-RDBMS-is-better aid, and a rare time horizon: supported through 2050, design decisions made with that in mind.  |
| **Python** — PEP 20, The Zen of Python                  | Aphorisms as tiebreakers         | Extreme brevity, embedded in the language (`import this`). Weakness worth copying against: aphorisms only adjudicate with shared context and can be cited on both sides ("practicality beats purity").                                                                                               |
| **FastAPI** — Alternatives, Inspiration and Comparisons | Vision by comparison             | First-person walk through predecessors, each with a boxed "Inspired FastAPI to…" takeaway (DRF → automatic docs; Flask → micro-framework; Marshmallow → code-defined schemas; APIStar → "Exist"). Tools with no box mark what was left behind. The model for entering a crowded niche.               |
| **Go** — "Go at Google" (Rob Pike, SPLASH 2012)         | Solve one specific problem well  | "Go's purpose is not to do research into programming language design; it is to improve the working environment for its designers and their coworkers." Enumerates concrete pain (slow builds, dependency skew) and derives features from it, down to unused-import-as-error.                         |
| **htmx** — Essays (Locality of Behaviour, HOWL, etc.)   | Named principles as essays       | Each principle gets a name, a crisp statement, and an honest weighing against competing principles (LoB vs DRY vs Separation of Concerns). Naming makes a principle referenceable in review; essays let the canon grow without rewriting a monolith.                                                 |

## Other strong examples

- **Unix philosophy** (McIlroy, 1978): "Make each program do one thing well… Expect the output of
  every program to become the input to another." Archetype of the composable-tools vision.
- **Django — Design philosophies**: named principles (Loose coupling, Less code, Quick development,
  DRY, Explicit is better than implicit, Consistency) meant "to explain the past and guide the
  future". Imports a Zen of Python line to justify avoiding magic: one project's vision propagating
  into another's.
- **"The Rise of Worse is Better"** (Richard Gabriel): a ranked value system (simplicity of
  implementation > correctness > consistency > completeness) explaining why "worse" designs win.
- **Kubernetes design principles** (in-repo): terse rules — "All APIs should be declarative", "API
  objects should be complementary and composable, not opaque wrappers".
- **Rust — "Stability as a Deliverable"** (2014): "stability without stagnation" justified the
  six-week release train, which has run since 1.0.
- **Svelte — Tenets** (Rich Harris): "Optimise for vibes" — "People use Svelte because they _like_
  Svelte. They like it because it aligns with their aesthetic sensibilities." A distinctive,
  non-technical value can be a legitimate anchor.
- **principles.design** (Ben Brignell): curated library of real-world design-principle sets, a
  pattern catalogue.

## Vision vs mission vs principles

Ben Cotton (former Fedora Program Manager): a **vision** "describes the world you want to see, not
how you'll get there… not something you can achieve in a year or five or ten"; a **mission**
"describes what your project does in support of that vision" and is never done. Between them the
community gets "implicit permission to not try to fix everything because the mission clearly defines
the scope."

The OSAOS handbook frames four parts — mission (why), vision (what future), values (what
principles), goals (SMART) — and the questions a good statement answers: "Do we need to add this
feature? Should we build this ourselves or use an existing library? Have we accomplished our
mission?"

Fedora's process: three people wrote the first draft, then the full Council went through "almost
every word", including how non-native English speakers would read it. Draft small, socialize outward
— handing the community a blank page is the worst way to start.

Formal IEEE/RUP-style vision templates (~11 sections: positioning, problem statement, stakeholder
profiles, features, constraints) suit product organizations. Their one reusable piece is the
problem-statement fill-in: "The problem of [X] affects [whom], the impact of which is [Y]; a
successful solution would be [Z]."

## Evidence and caveats

- Maintainers and contributors misalign on priorities: maintainers weigh alignment with the
  project's direction, contributors overvalue innovation (Alebachew, Ko & Brown, "Are We on the Same
  Page?", arXiv:2504.18407). A written direction is the cheapest way to close that gap before code
  exists.
- Narrow, well-defined scope is repeatedly linked to survivable maintenance and less burnout; scope
  creep ("new code additions evaluated incrementally rather than holistically") to debt and
  abandonment (Coelho & Valente, "Why Modern Open Source Projects Fail", arXiv:1707.02327).
- No evidence that documentation _causes_ growth: CONTRIBUTING files tend to follow contribution
  activity rather than precede it (arXiv:2502.18440). A vision doc is an alignment and decision
  tool, not a growth lever.
- "Vision document" is not a standardized artifact; treat the anatomy as a menu matched to the
  project's stage, not a mandate.
