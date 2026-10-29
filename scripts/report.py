#!/usr/bin/env python3
"""report.py - bookkeeping for PLATFORM-DEPENDENCY-ANALYSIS.md.

The model writes and judges the report; this script does the parts a script is
better at: checking the structure and counting.

  report.py check REPORT      lint a draft or a final report
  report.py finalize REPORT   after Tier 2: render the severity table from the
                              final headings and mark the header completed

Every finding heading carries its claim ID, severity and status on one line,
so each finding has exactly one unique line to edit:

  ### [PDA-001] [High?] [UNVERIFIED] Stripe called from OrderService    (draft)
  ### [PDA-001] [High] [CONFIRMED] Stripe called from OrderService      (final)
  ### [PDA-002] [Medium] [ADJUSTED: vendor type leaks] ...
  ### [PDA-003] [OK] [ADJUSTED: real adapter, passes R2a] ...
  ### [PDA-004] [N/A] [REJECTED: comment, not usage] ...

`check` reads the `- Verification:` header to decide which rules apply: a
`pending` report may still hold UNVERIFIED findings, a `completed` one may not.
Exit codes: 0 = clean, 1 = problems found (listed on stdout), 2 = bad usage.
Standard library only; Python 3.9+.
"""

import argparse
import datetime
import re
import sys
from pathlib import Path

SEVERITIES = ("Critical", "High", "Medium", "Low")
HEADING = re.compile(
    r"^### \[(PDA-\d{3,})\] \[(Critical|High|Medium|Low|OK|N/A)(\?)?\] "
    r"\[(UNVERIFIED|CONFIRMED|ADJUSTED|REJECTED)(?::([^\]]*))?\] (\S.*)$")
FINDING_START = re.compile(r"^### \[PDA")
SECTION_END = re.compile(r"^#{1,3} ")
VERIFICATION = re.compile(r"^- Verification:\s*(\S+)(?:\s+(\S+))?")
SEV_PLACEHOLDER = "_Severity table pending verification._"
PLACEHOLDERS = (SEV_PLACEHOLDER, "_Executive summary pending verification._",
                "_File index pending verification._")
SEV_TABLE_HEAD = re.compile(r"^\|\s*Severity\s*\|\s*Count\s*\|")
SEV_ROW = re.compile(r"^\|\s*(Critical|High|Medium|Low)\s*\|\s*(\d+)\s*\|")
BARE_REF = re.compile(r"`:\d+(?:-\d+)?`")
FENCE = re.compile(r"^\s*```")


def outside_comments(lines):
    """Yield (index, line) for lines not inside an HTML comment."""
    inside = False
    for i, line in enumerate(lines):
        if inside:
            if "-->" in line:
                inside = False
            continue
        if "<!--" in line and "-->" not in line.split("<!--", 1)[1]:
            inside = True
        yield i, line


def parse(lines):
    """Return (findings, problems). A finding is a dict with its heading fields
    and the body lines up to the next heading of level 1-3."""
    findings, problems = [], []
    starts = [i for i, ln in outside_comments(lines) if FINDING_START.match(ln)]
    for i in starts:
        m = HEADING.match(lines[i])
        if not m:
            problems.append((i, "malformed finding heading; expected "
                                "`### [PDA-NNN] [Severity] [STATUS] title`"))
            continue
        end = next((j for j in range(i + 1, len(lines)) if SECTION_END.match(lines[j])),
                   len(lines))
        pid, sev, guess, status, reason, title = m.groups()
        findings.append(dict(line=i, id=pid, sev=sev, guess=bool(guess), status=status,
                             reason=(reason or "").strip(), title=title,
                             body=lines[i + 1:end]))
    return findings, problems


def header_state(lines):
    for i, ln in outside_comments(lines):
        m = VERIFICATION.match(ln)
        if m:
            return i, m[1], m[2]
    return None, None, None


def check(lines, final=None):
    findings, problems = parse(lines)
    hline, state, date = header_state(lines)
    if hline is None:
        problems.append((0, "no `- Verification:` header line"))
    elif state not in ("pending", "completed"):
        problems.append((hline, f"Verification header must be `pending` or "
                                f"`completed <YYYY-MM-DD>`, got `{state}`"))
    if final is None:
        final = state == "completed"
    if final and state == "completed" and not re.fullmatch(r"\d{4}-\d{2}-\d{2}", date or ""):
        problems.append((hline, "completed header needs a date: "
                                "`- Verification: completed YYYY-MM-DD`"))

    seen = {}
    for f in findings:
        i, pid = f["line"], f["id"]
        if pid in seen:
            problems.append((i, f"{pid} duplicates the ID on line {seen[pid] + 1}"))
        seen.setdefault(pid, i)
        verified = f["status"] != "UNVERIFIED"
        if verified and f["guess"]:
            problems.append((i, f"{pid}: verified finding still has a `?` severity"))
        if not verified and not f["guess"]:
            problems.append((i, f"{pid}: UNVERIFIED finding needs a tentative `?` severity"))
        if f["status"] in ("ADJUSTED", "REJECTED") and not f["reason"]:
            problems.append((i, f"{pid}: {f['status']} needs a reason: "
                                f"`[{f['status']}: <short reason>]`"))
        if f["status"] in ("UNVERIFIED", "CONFIRMED") and f["reason"]:
            problems.append((i, f"{pid}: {f['status']} takes no reason; "
                                f"put it in the Verification note"))
        if (f["status"] == "REJECTED") != (f["sev"] == "N/A"):
            problems.append((i, f"{pid}: REJECTED and [N/A] go together (R4a)"))
        body = "\n".join(f["body"])
        if not re.search(r"^Claimed role:", body, re.M):
            problems.append((i, f"{pid}: missing `Claimed role:` line"))
        if not re.search(r"^Locations:", body, re.M):
            problems.append((i, f"{pid}: missing `Locations:` line"))
        if verified and not re.search(r"^Verification note:", body, re.M):
            problems.append((i, f"{pid}: verified finding has no `Verification note:`"))
        if final and not verified:
            problems.append((i, f"{pid}: still UNVERIFIED in a completed report"))
        if final and "pending verification" in body:
            problems.append((i, f"{pid}: body still says `pending verification`"))

    ids = sorted(int(f["id"][4:]) for f in findings)
    gaps = sorted(set(range(1, ids[-1] + 1)) - set(ids)) if ids else []
    if gaps:
        problems.append((findings[0]["line"], "claim IDs skip "
                         + ", ".join(f"PDA-{g:03d}" for g in gaps)
                         + " - IDs are assigned once in Tier 1 and never renumbered"))

    if final:
        for i, ln in outside_comments(lines):
            if ln.strip() in PLACEHOLDERS:
                problems.append((i, f"placeholder left in a completed report: {ln.strip()}"))
        table = severity_rows(lines)
        expected = counts(findings)
        if not table:
            problems.append((0, "completed report has no severity table "
                                "(run `report.py finalize`)"))
        elif table != expected:
            problems.append((0, f"severity table {table} does not match the "
                                f"headings {expected} (re-run `report.py finalize`)"))

    fenced = False
    for i, ln in enumerate(lines):
        if FENCE.match(ln):
            fenced = not fenced
        elif not fenced and BARE_REF.search(ln):
            problems.append((i, f"bare reference {BARE_REF.search(ln)[0]}: write the full "
                                f"path, e.g. `src/app.ts:24` (linkify links only full paths)"))
        bad = next((c for c in ln if ord(c) > 127), None)
        if bad:
            problems.append((i, f"non-ASCII character {bad!r} (U+{ord(bad):04X})"))
    return findings, sorted(problems), final


def counts(findings):
    return {s: sum(f["sev"] == s for f in findings) for s in SEVERITIES}


def severity_rows(lines):
    rows = {}
    for _, ln in outside_comments(lines):
        m = SEV_ROW.match(ln)
        if m:
            rows[m[1]] = int(m[2])
    return {s: rows.get(s, 0) for s in SEVERITIES} if rows else {}


def render_table(findings):
    c = counts(findings)
    return ["| Severity | Count |", "|---|---|"] + [f"| {s} | {c[s]} |" for s in SEVERITIES]


def tally(findings):
    c = counts(findings)
    status = {s: sum(f["status"] == s for f in findings)
              for s in ("CONFIRMED", "ADJUSTED", "REJECTED", "UNVERIFIED")}
    return (f"findings: {len(findings)} - "
            + ", ".join(f"{s} {c[s]}" for s in SEVERITIES)
            + f", OK {sum(f['sev'] == 'OK' for f in findings)}"
            + f", N/A {sum(f['sev'] == 'N/A' for f in findings)}\n"
            + "verdicts: " + ", ".join(f"{k} {v}" for k, v in status.items() if v))


def report_problems(path, problems):
    for i, msg in problems:
        print(f"{path}:{i + 1}: {msg}")


def cmd_check(path, lines):
    findings, problems, final = check(lines)
    report_problems(path, problems)
    pending = [f["id"] for f in findings if f["status"] == "UNVERIFIED"]
    print(f"{'final' if final else 'draft'} report, {len(problems)} problem(s)")
    print(tally(findings))
    if pending and not final:
        print("unverified: " + " ".join(pending))
    elif findings and not final and not problems:
        print("every finding is verified - next: `report.py finalize`")
    return 1 if problems else 0


def cmd_finalize(path, lines, date):
    findings, problems, _ = check(lines, final=False)
    pending = [f["id"] for f in findings if f["status"] == "UNVERIFIED"]
    if pending:
        problems.append((0, "still UNVERIFIED: " + " ".join(pending)
                         + " - resume the verifier to finish them"))
    if problems:
        report_problems(path, problems)
        print("finalize refused: fix the problems above first", file=sys.stderr)
        return 1

    table = render_table(findings)
    out, i, placed = [], 0, False
    live = {j for j, _ in outside_comments(lines)}
    while i < len(lines):
        ln = lines[i]
        if i in live and not placed and (ln.strip() == SEV_PLACEHOLDER
                                         or SEV_TABLE_HEAD.match(ln)):
            out += table
            placed = True
            i += 1
            if SEV_TABLE_HEAD.match(ln):  # replace the old table in full
                while i < len(lines) and lines[i].startswith("|"):
                    i += 1
            continue
        if i in live and VERIFICATION.match(ln):
            ln = f"- Verification: completed {date}"
        out.append(ln)
        i += 1
    if not placed:
        print(f"{path}: no `{SEV_PLACEHOLDER}` placeholder or severity table "
              f"to replace", file=sys.stderr)
        return 1
    Path(path).write_text("\n".join(out) + "\n", encoding="utf-8")
    print(f"wrote {path}")
    print(tally(findings))
    print("next: write the File Index and Executive Summary, then run `report.py check`")
    return 0


def main():
    ap = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    sub = ap.add_subparsers(dest="cmd", required=True)
    sub.add_parser("check", help="lint a draft or final report").add_argument("report")
    fin = sub.add_parser("finalize", help="render the severity table, mark completed")
    fin.add_argument("report")
    fin.add_argument("--date", default=datetime.date.today().isoformat(),
                     help="completion date (default: today)")
    args = ap.parse_args()

    path = Path(args.report)
    if not path.is_file():
        print(f"report.py: not a file: {path}", file=sys.stderr)
        return 2
    lines = path.read_text(encoding="utf-8").splitlines()
    if args.cmd == "check":
        return cmd_check(args.report, lines)
    return cmd_finalize(args.report, lines, args.date)


if __name__ == "__main__":
    sys.exit(main())
