# Tier 2 Verifier Prompt

The main agent reads this file at Tier 2, fills in the three
`<ABSOLUTE_PATH_...>` placeholders, and passes the block below verbatim as the
prompt of exactly one general-purpose subagent.

Why it is shaped this way:

- The subagent does not inherit the skill; it knows only this prompt. It is
  pointed at the two rule files and told not to read `SKILL.md`, whose scan
  workflow would pull it away from verifying.
- The procedure cites rule IDs instead of restating rules. The verifier reads
  the rulebook in full, and a second copy here would drift.
- Each finding has one unique heading line carrying ID, severity and status,
  so a verdict is a single exact-string edit of that line.

```text
You are verifying a platform-dependency audit. A draft report exists; confirm,
adjust, or reject each finding with call-site and cross-file analysis, and edit
the draft in place. Do not re-scan the repository for new findings.

Repo root: <ABSOLUTE_PATH_TO_REPO_ROOT>   (run every repo-wide grep from here)
Draft:     <ABSOLUTE_PATH_TO_DRAFT>

Read these two files in full before judging anything. They are the complete
rules, and the only ones:
- <ABSOLUTE_PATH_TO_SKILL_DIR>/references/classification-rules.md (R1-R8)
- <ABSOLUTE_PATH_TO_SKILL_DIR>/references/dependency-patterns.md (shapes,
  wrapper and binding attribution, the dated license tables)
Do not read the skill's SKILL.md; it describes the scan, not your job.

For each finding (each `### [PDA-NNN] ...` heading still marked
[UNVERIFIED]), in order:
1. Real usage (R6): open every cited path:line. A comment, doc, fixture string
   or a known collision from R6's table is a false positive.
2. Role (R2, R2b, R2c): read the file and its neighbours, not just the path.
3. Adapter test (R2a): does the file implement an interface for the
   capability, and is it the only place the vendor SDK is referenced? Settle
   the second half with a repo-wide grep.
4. Callers: grep for importers of the flagged module. Vendor types leaking
   through its public surface mean Medium (R3).
5. Wrappers, bindings and hostable services (R4): attribute a wrapper or
   binding to the service behind it; resolve any base_url / endpoint / DSN
   with R5, or describe a provider registry with R5a.
6. Modifiers: build-variant containment (R3), ambiguity discount (R3),
   upstream forks (R8), hardcoded credentials (R7 - one clause, never a
   finding).
7. Decide the verdict (R4a) and edit the finding:
   - Rewrite the heading line - it is unique - to exactly one of:
       ### [PDA-NNN] [<Critical|High|Medium|Low>] [CONFIRMED] <title>
       ### [PDA-NNN] [<Critical|High|Medium|Low>] [ADJUSTED: <reason>] <title>
       ### [PDA-NNN] [OK] [ADJUSTED: <reason>] <title>
       ### [PDA-NNN] [N/A] [REJECTED: <reason>] <title>
     Drop the `?`. Re-title the finding if attribution changed (R4). Reasons
     are short and contain no square brackets.
   - Fix the `Claimed role:` line if the role was wrong.
   - Add one line directly under the heading:
       Verification note: <what you found, citing full path:line>
   - If the Recommended fix no longer fits the verdict, rewrite it.
   - Cite every location with its full repository path and line, e.g.
     `src/context/EpisodeContext.tsx:136` or `src/api/index.ts:24-28`. Never a
     bare `:24`, never a basename alone: only full paths can be checked and
     linked later.

Rules of engagement:
- Edit only finding blocks. Leave the header, the Executive Summary, the
  Acceptable Dependencies list and the `_... pending verification._` lines to
  the main agent; if something belongs in Acceptable Dependencies, say so in
  the Verification note.
- Never renumber claim IDs. Never use replace_all.
- When still uncertain after analysis, keep the finding (CONFIRMED or
  ADJUSTED) and say why in the Verification note; do not reject on doubt.
- A license basis stated in a `Problem:` line is checked against the dated
  tables in dependency-patterns.md, not against memory - training data on
  vendor relicensing is frequently stale. If neither settles it, keep the
  finding with an ambiguity note.
- Work through every finding. If you are interrupted, the next message will
  ask you to continue with the ones still marked [UNVERIFIED].

When done, return one line per claim: `PDA-NNN: <VERDICT> - <one-clause reason>`.
```
