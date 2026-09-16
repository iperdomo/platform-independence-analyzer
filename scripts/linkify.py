#!/usr/bin/env python3
"""linkify.py - turn `path/to/file:NN` references in a Markdown report into
permalinks pinned to one commit.

Run it AFTER the report's line numbers are verified and BEFORE the HTML is
rendered, so the rendered page is clickable.

The point is the checking, not the rewriting. A reference is linked only if, at
the pinned commit:

  * the file exists at exactly that path
  * the line is within the file
  * the line is not blank (a blank line means the reference drifted)

Anything else is left as plain text and counted. Validation failures abort the
run, so a drifted line number is reported rather than linked.

Only self-contained references are handled: `path:NN` and `path:NN-MM`.
Anything needing context to interpret - a bare `:NN` continuation, a comma
list, a bare basename that is not a real path - is deliberately skipped.
Reports should name the full path on every reference they want linked.

Preconditions: no modified tracked files, because the line numbers were
verified against the working tree. Use --allow-dirty if you know better.

Re-running is a no-op, so it doubles as a staleness check: re-point --sha at a
newer commit and any drifted line number shows up as an error.
"""

import argparse
import os
import re
import subprocess
import sys
from pathlib import Path

CANDIDATE = re.compile(r"`([A-Za-z0-9_.][A-Za-z0-9_/.+-]*:\d+(?:-\d+)?)`")
SPAN = re.compile(r"(?<!\[)`([^`\n]+)`")
FENCE = re.compile(r"^\s*```")


def die(msg):
    sys.exit(f"{os.path.basename(sys.argv[0])}: {msg}")


def git(repo, *args):
    """Run a git command, returning stdout or None if it failed.

    Deliberately NOT check=True: every caller treats failure as a normal
    outcome, not an error. `git show <sha>:<path>` failing is how a reference
    to a non-existent path is detected, and the rev-parse calls are how "not a
    repo" and "no such commit" are detected. Raising here turns all of those
    into a traceback.
    """
    r = subprocess.run(
        ["git", "-C", repo, *args], capture_output=True, text=True, check=False
    )
    return r.stdout if r.returncode == 0 else None


def base_url(repo, url, style):
    """Derive the permalink prefix and the fragment style from the remote."""
    if not url:
        url = (git(repo, "remote", "get-url", "origin") or "").strip()
        if not url:
            die("no origin remote; pass --url")
    url = url.removesuffix(".git")
    if not url.startswith(("http://", "https://")):
        for p in ("ssh://", "git+ssh://"):
            url = url.removeprefix(p)
        url = url.split("@", 1)[-1]           # strip any user@
        url = url.replace(":", "/", 1)        # scp-style host:org/repo
        url = "https://" + url
    if not style:
        style = ("gitlab" if "gitlab" in url else
                 "bitbucket" if "bitbucket" in url else "github")
    prefix = {"github": f"{url}/blob", "gitlab": f"{url}/-/blob",
              "bitbucket": f"{url}/src"}.get(style) or die(f"unknown --style: {style}")
    return prefix, style


def fragment(style, start, end):
    if start == end:
        return f"#lines-{start}" if style == "bitbucket" else f"#L{start}"
    if style == "bitbucket":
        return f"#lines-{start}:{end}"
    return f"#L{start}-{end}" if style == "gitlab" else f"#L{start}-L{end}"


def main():
    ap = argparse.ArgumentParser(
        description="Link `path:NN` spans to permalinks, checking each against "
                    "the tree at the pinned commit. Everything else is left alone.")
    ap.add_argument("docs", nargs="+", metavar="markdown-file")
    ap.add_argument("-C", "--repo", help="git repository (default: toplevel containing the doc)")
    ap.add_argument("-s", "--sha", default="HEAD", help="commit to pin to (default: HEAD)")
    ap.add_argument("-u", "--url", help="base web URL (default: from the origin remote)")
    ap.add_argument("--style", choices=("github", "gitlab", "bitbucket"))
    ap.add_argument("--allow-dirty", action="store_true", help="skip the clean-tree check")
    ap.add_argument("--audit", action="store_true", help="print every resolution, then stop")
    ap.add_argument("-w", "--write", action="store_true", help="apply the changes")
    ap.add_argument("-q", "--quiet", action="store_true", help="suppress the summary")
    args = ap.parse_args()

    for d in args.docs:
        if not os.path.isfile(d):
            die(f"not a file: {d}")

    repo = args.repo or os.path.dirname(os.path.abspath(args.docs[0]))
    repo = (git(repo, "rev-parse", "--show-toplevel") or "").strip()
    if not repo:
        die(f"not inside a git repository: {args.repo or args.docs[0]}")

    if not args.allow_dirty:
        dirty = git(repo, "status", "--porcelain", "--untracked-files=no") or ""
        if dirty.strip():
            print("modified tracked files - line numbers may not match the pinned\n"
                  "commit. Commit/stash them, or pass --allow-dirty.\n" + dirty,
                  file=sys.stderr)
            return 2

    sha = (git(repo, "rev-parse", "--verify", args.sha + "^{commit}") or "").strip()
    if not sha:
        die(f"no such commit: {args.sha}")
    prefix, style = base_url(repo, args.url, args.style)

    texts = {d: Path(d).read_text(encoding="utf-8") for d in args.docs}
    refs = sorted({m for t in texts.values() for m in CANDIDATE.findall(t)})

    blobs, url, audit, errors, skipped = {}, {}, [], [], []
    for ref in refs:
        path, _, spec = ref.rpartition(":")
        start, _, end = spec.partition("-")
        start, end = int(start), int(end or start)

        if path not in blobs:
            out = git(repo, "show", f"{sha}:{path}")
            blobs[path] = out.splitlines() if out is not None else None
        lines = blobs[path]

        if lines is None:
            skipped.append(ref)
        elif not 1 <= start <= len(lines) or end > len(lines):
            errors.append(f"{ref}: out of range (file has {len(lines)} lines)")
        elif not lines[start - 1].strip():
            errors.append(f"{ref}: points at a BLANK line")
        else:
            frag = fragment(style, start, end)
            url[ref] = f"{prefix}/{sha}/{path}{frag}"
            audit.append(f"{ref:<46} -> {path + frag:<44} | {lines[start - 1].strip()[:72]}")

    if not args.quiet:
        print(f"repo            : {repo}")
        print(f"pinned to       : {sha}")
        print(f"base url        : {prefix}/{sha} ({style})")
        print(f"documents       : {' '.join(args.docs)}")
        print(f"refs validated  : {len(url)}")
        print(f"skipped (no such path at commit): {len(skipped)}")
        print(*(f"   - {s}" for s in skipped), sep="\n") if skipped else None
        print(f"validation errs : {len(errors)}")
        print(*(f"   ! {e}" for e in errors), sep="\n") if errors else None

    if args.audit:
        print(*audit, sep="\n")
        return 1 if errors else 0
    if errors:
        print("\nABORT: fix the references above before writing.", file=sys.stderr)
        return 1
    if not args.write:
        if not args.quiet:
            print("\ndry run only; re-run with --write")
        return 0

    # `(?<!\[)` leaves spans that are already links alone, which is what makes
    # re-running a no-op. Fenced blocks are skipped.
    for doc, text in texts.items():
        out, fenced = [], False
        for line in text.splitlines():
            if FENCE.match(line):
                fenced = not fenced
            elif not fenced:
                line = SPAN.sub(
                    lambda m: f"[`{m[1]}`]({url[m[1]]})" if m[1] in url else m[0], line)
            out.append(line)
        Path(doc).write_text("\n".join(out) + "\n", encoding="utf-8")
        if not args.quiet:
            print(f"wrote {doc}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
