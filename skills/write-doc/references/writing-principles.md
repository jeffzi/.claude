# Writing Principles for Documentation

## Contents

- [Content principles](#content-principles) — ARID, SKIMMABLE, EXEMPLARY, CONSISTENT, CURRENT
- [Structure principles](#structure-principles) — CUMULATIVE, COMPLETE, DISCOVERABLE, ADDRESSABLE
- [Source principles](#source-principles) — NEARBY, UNIQUE
- [Documentation prose rules](#documentation-prose-rules) — second person, present tense,
  readability
- [Accessibility and inclusivity](#accessibility-and-inclusivity) — content accessibility,
  screenshots, reducing bias
- [Structure and formatting](#structure-and-formatting) — headings, visual devices, code examples,
  admonitions

---

## Content principles

**ARID (Accept some Repetition In Documentation).** DRY applies to code, not documentation. Readers
land on a single page — they shouldn't chase cross-references to understand a concept. Repeat
context where needed. The cost of a lost reader outweighs restating a paragraph.

**SKIMMABLE.** Most readers scan, not read linearly. Structure for scanning:

- **Headings**: Descriptive, not clever. "Configuring authentication" beats "Getting started." A
  reader scanning the table of contents should find the right section without guessing.
- **First sentence of each paragraph**: State the point. Explanation follows.
- **Lists and tables**: Use them for sets of items, options, or comparisons. Prose is for reasoning
  and context — not for enumerating things.
- **Code examples**: Put them where the reader needs them, not in an appendix. Show the common case
  first, edge cases after.
- **Links**: Describe what the link leads to. "See the authentication guide" — not "click here."

**EXEMPLARY.** Include examples for common use cases, but not everything. Many readers jump to
examples first. Show the simplest realistic example, not a minimal toy. Separate examples from dense
reference information — each serves a different reader in a different mode.

**CONSISTENT.** Use the same term for the same concept throughout. If you call it a "workspace" in
the tutorial, don't switch to "project" in the reference. Pick one capitalization style for
headings, one way to format commands, and stick to it. Inconsistency erodes trust.

**CURRENT.** Incorrect documentation is worse than missing documentation. A reader who follows
outdated instructions wastes hours and loses trust. Write version-agnostic where possible — "Run the
install script" ages better than "Download v2.3.1."

## Structure principles

**CUMULATIVE.** Order content so prerequisite concepts come first. A reader should follow the
documentation linearly without encountering unexplained concepts.

**COMPLETE.** Cover concepts in full, or not at all. A map showing 50 of 100 fire hydrants is worse
than one showing none — the reader assumes comprehensiveness and acts on incomplete data. If
publishing partial docs, state this upfront.

**DISCOVERABLE.** Funnel users toward documentation through every likely pathway — in-app links,
README pointers, search optimization. Documentation that can't be found doesn't exist.

**ADDRESSABLE.** Provide direct links to specific sections. Readers need to bookmark, share, and
reference precise content — not just "see the docs."

## Source principles

**NEARBY.** Store documentation as close to the code it describes as possible — co-located text
files, comment blocks, or docs in the same repository. Merge development and documentation
workflows.

**UNIQUE.** Each documentation source should have a clearly defined, non-overlapping scope. Parallel
maintenance of the same information across sources leads to inconsistency and rot.

**Scope note.** This skill covers documentation content and structure. For tooling decisions
(Markdown vs RST, static site generators, docs-as-code CI), follow the project's existing
conventions.

## Documentation prose rules

For sentence-level clarity (active voice, omitting needless words, concrete language), load
`Skill(write-prose)` and apply its rules before writing or editing prose. The rules below are
specific to documentation writing:

- **Second person for instructions.** "You can configure..." or imperative "Configure..." — not "The
  user can configure..." You are talking to the reader.
- **Present tense by default.** "The function returns..." — not "The function will return..."
- **Never say "simply," "easy," or "easily."** If the reader needed documentation, the task is not
  simple. These words show a lack of empathy and make the reader feel inadequate when they struggle.
- **Define abbreviations before use.** Spell out on first use, even common ones. You don't know who
  is reading your docs.
- **Aim for high-school readability.** Prefer common words. "Use" over "utilize." "Start" over
  "initiate." Short sentences for instructions, longer for explanation.
- **Sentence case for headings.** "Configuring the database" — not "Configuring The Database."
- **One idea per paragraph.** When a paragraph covers two topics, the reader looking for one will
  miss the other.
- **Avoid gendered language.** Use "they" for generic singular. Prefer inclusive terminology —
  "primary/replica" over "master/slave," "allowlist/denylist" over "whitelist/blacklist."

## Accessibility and inclusivity

### Content accessibility

- **Headings enable assistive technology.** Screen readers navigate by headings — meaningful
  hierarchy is functional, not just visual.
- **Alt text for images.** Describe what the image shows and why it's there.
- **Don't rely on color alone.** "The red text indicates an error" fails for colorblind readers. Use
  formatting plus text.
- **Plain language.** Non-native English speakers are a large portion of technical audiences.

### Screenshot guidelines

- All screenshots need descriptive file names and brief alt text.
- Describe annotations in surrounding text — screen readers can't read image overlays.
- Don't write text directly on screenshots.
- Use PNG over JPG for screenshots.
- Populate UI examples with believable but fictional data — protect real user data.
- If the product changes often, minimize screenshots and rely on text.

### Reducing bias

Use diverse, inclusive example names from varied cultural backgrounds. Replace animal-violence
idioms: "accomplish two things at once" instead of "kill two birds with one stone." Established
technical terms (kill, canary deployment, monkey-patching) have precise meanings and are fine.

## Structure and formatting

### Heading hierarchy

Use headings to create a scannable outline. A reader should understand the page's structure from
headings alone. Don't nest deeper than H4 — if you need H5, the page is too long or needs splitting.

Give any document with 6 or more sections a table of contents at the top, linking to each section.

### One meaning per visual device

Give each visual device — bold, italics, code formatting, blockquotes — one meaning per document and
apply it consistently. Bold that marks defined terms in one section and emphasis in the next teaches
the reader nothing; they stop trusting the signal. Pick the meaning, then either express emphasis in
the sentence itself or leave it out.

### Code examples

- Show working code. Code that almost works teaches the reader to distrust your docs.
- Use realistic names and values. `user_email = "alice@example.com"` teaches more than `x = "foo"`.
- Annotate non-obvious lines with comments. Don't comment the obvious.
- Show output when it helps — especially for CLI commands.

### Admonitions and callouts

Use sparingly. When everything is a warning, nothing is.

- **Note**: Extra context that's useful but not critical.
- **Tip**: A shortcut or best practice.
- **Warning**: Something that could cause problems if missed.
- **Caution/Danger**: Data loss, security risk, irreversible action.

If a page has more than 3-4 callouts, most of them should be regular prose.
