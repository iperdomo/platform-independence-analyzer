# Consolidating a Multi-Repository Audit

A portfolio - a directory of independent repositories, an organization's
projects - is audited one repository at a time (the Step 1 guard enforces
this) and then consolidated. Use this file when the user asks for a
consolidated, portfolio, or cross-repo view, or after several per-repo runs.

## Inputs

The finished `PLATFORM-DEPENDENCY-ANALYSIS.md` of each repository. Run
`scripts/report.py check` on each: only a report that passes as final
(`Verification: completed <date>`) is an input. Finish or rerun any that is
still `pending`, and if a repository was never audited, say so rather than
leaving a silent hole in the matrix.

Do not re-scan. Consolidation reads the finished reports and nothing else;
re-deriving findings from the code produces numbers that disagree with the
per-repo reports the user already has. `report.py check` prints each report's
severity and verdict tally, which is the matrix row.

## Output

`PLATFORM-DEPENDENCY-CONSOLIDATED.md` in the directory holding the
repositories, containing:

- a header listing every repository included, with its report's date and its
  coverage limits;
- a **repo x severity matrix** (one row per repository, columns
  Critical/High/Medium/Low, plus a "no findings" marker for clean repos - the
  clean ones are a result, not an omission);
- **top vendors across the portfolio**: vendor, number of repositories, number
  of findings, so shared remediation is visible;
- **shared recommendations** - an abstraction several repositories need is
  worth building once;
- per-repo one-line summaries linking to each source report.

Claim IDs stay traceable by prefixing them with the repository name:
`ghost/PDA-003`. Never renumber - a consolidated ID must resolve back to a
heading in a per-repo report.
