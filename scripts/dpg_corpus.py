#!/usr/bin/env python3
"""dpg_corpus.py - build a dependency corpus from recognized Digital Public Goods.

Independent of the skill's audit workflow. It feeds pattern maintenance: which
proprietary dependencies do real DPGs declare, and does references/patterns.tsv
catch them?

  dpg_corpus.py fetch     [OUT] [--limit 100] [--category "Open Software"]
  dpg_corpus.py clone     [OUT] [--jobs 4] [--min-free-gb 2]
  dpg_corpus.py inventory [OUT]
  dpg_corpus.py all       [OUT] (fetch, clone, inventory)
  dpg_corpus.py coverage  [OUT] [--patterns FILE]

OUT defaults to dpg-corpus/ at the skill root (gitignored). Every step reads
the previous step's files from OUT and can be re-run; `clone` skips what is
already cloned.

fetch      GET the DPG API, keep `category`, sort by `dpgSince` newest first,
           take --limit. Writes dpgs.json (the selected records) and
           sources.tsv (one row per URL found in sourceURL / otherSources).
           Only URLs written in those fields are used: a field that holds a
           comma list or a JSON blob is split into the URLs it contains, but an
           org or owner URL is never expanded into its repositories.
clone      `git ls-remote` each URL; anything that is not a git repository
           (org page, docs site, package page, short link) is logged and
           skipped. Repositories are shallow-cloned into OUT/<dpgId>/<owner>__<repo>.
           Writes clone-log.tsv.
inventory  Read the manifests in every clone and list the DIRECT declared
           dependencies (no lock files, no transitive deps). Writes stack.tsv,
           deps.tsv, deps-unique.tsv, inventory-errors.tsv and summary.md.
coverage   After the (manual) classification: for every dependency in
           proprietary.tsv (written by the reviewer, same first columns as
           deps-unique.tsv plus verdict/vendor/capability), take its declaration
           line(s) from each manifest and test them against every group of
           references/patterns.tsv with `rg -in`, the same engine and flags as
           scan.sh. Writes coverage.tsv (one row per proprietary dependency:
           caught / gap / no-decl-line, and the matching groups) and
           coverage-other.tsv (dependencies NOT in proprietary.tsv that a group
           still matches: false-positive candidates).

The clones are untrusted. Nothing in them is executed or imported: manifests
are parsed as data (json, tomllib, xml.etree, ast.literal_eval, regex). Clones
are made with core.symlinks=false and without submodules or LFS objects. Run
this script as `python3 -I scripts/dpg_corpus.py`, never from inside OUT.

Exit codes: 0 = ran; 1 = a step failed (message on stderr); 2 = bad usage or
the previous step's output is missing.
Standard library only; Python 3.11+ (tomllib).
"""

import argparse
import ast
import collections
import concurrent.futures
import configparser
import csv
import json
import os
import re
import shutil
import subprocess
import sys
import tempfile
import threading
import tomllib
import urllib.parse
import urllib.request
import xml.etree.ElementTree as ET
from pathlib import Path

API_URL = "https://app.digitalpublicgoods.net/api/v1/dpgs"
SKILL_ROOT = Path(__file__).resolve().parent.parent
DEFAULT_OUT = SKILL_ROOT / "dpg-corpus"

GIT_ENV = {
    "GIT_TERMINAL_PROMPT": "0",   # an org or 404 URL must fail, not prompt
    "GIT_ASKPASS": "/bin/true",
    "SSH_ASKPASS": "/bin/true",
    "GIT_LFS_SKIP_SMUDGE": "1",
}
GIT_SAFE = ["-c", "core.symlinks=false", "-c", "credential.helper=",
            "-c", "protocol.file.allow=never"]


def die(msg, code=1):
    print(f"error: {msg}", file=sys.stderr)
    sys.exit(code)


def write_tsv(path, header, rows):
    with open(path, "w", newline="", encoding="utf-8") as f:
        w = csv.writer(f, delimiter="\t", lineterminator="\n")
        w.writerow(header)
        w.writerows(rows)


def read_tsv(path):
    if not path.is_file():
        die(f"{path} not found - run the previous step first", 2)
    with open(path, newline="", encoding="utf-8") as f:
        return list(csv.DictReader(f, delimiter="\t"))


def clean(s):
    """Make a value safe for one TSV cell."""
    return re.sub(r"[\t\r\n]+", " ", str(s)).strip()


# ---------------------------------------------------------------------- fetch

URL_RE = re.compile(r"https?://[^\s\"'<>,;\[\]{}]+", re.I)


def extract_urls(value):
    """Every http(s) URL written anywhere in a field value (str, list, dict)."""
    if value is None:
        return []
    if isinstance(value, dict):
        return [u for v in value.values() for u in extract_urls(v)]
    if isinstance(value, list):
        return [u for v in value for u in extract_urls(v)]
    return [u.rstrip("/.)") for u in URL_RE.findall(str(value))]


def url_key(url):
    """Dedupe key: case, a trailing slash and .git do not make a new repo
    (GitHub and GitLab paths are case-insensitive)."""
    p = urllib.parse.urlsplit(url)
    path = re.sub(r"(\.git)?/*$", "", p.path)
    return (p.netloc.lower(), path.lower())


def select_dpgs(records, category, limit):
    def has_category(r):
        c = r.get("category")
        return category in c if isinstance(c, list) else c == category
    picked = [r for r in records if has_category(r)]
    picked.sort(key=lambda r: (r.get("dpgSince") or "", r.get("dpgId") or ""), reverse=True)
    return picked[:limit]


def source_rows(dpg):
    rows, seen = [], set()
    for field in ("sourceURL", "otherSources"):
        for url in extract_urls(dpg.get(field)):
            if url_key(url) in seen:
                continue
            seen.add(url_key(url))
            rows.append([dpg["dpgId"], clean(dpg.get("name", "")), field, url])
    return rows


def cmd_fetch(args):
    out = args.out
    if args.from_file:
        records = json.loads(Path(args.from_file).read_text(encoding="utf-8"))
    else:
        req = urllib.request.Request(args.api, headers={"User-Agent": "dpg_corpus.py"})
        try:
            with urllib.request.urlopen(req, timeout=120) as r:
                records = json.load(r)
        except (OSError, ValueError) as e:
            die(f"fetching {args.api}: {e}")
    if not isinstance(records, list):
        die("unexpected API response: expected a JSON list")

    dpgs = select_dpgs(records, args.category, args.limit)
    out.mkdir(parents=True, exist_ok=True)
    (out / "dpgs.json").write_text(json.dumps(dpgs, indent=2, ensure_ascii=False) + "\n",
                                   encoding="utf-8")
    rows = [row for d in dpgs for row in source_rows(d)]
    write_tsv(out / "sources.tsv", ["dpgId", "name", "field", "url"], rows)

    no_url = [d["dpgId"] for d in dpgs if not source_rows(d)]
    span = f"{dpgs[-1].get('dpgSince')} .. {dpgs[0].get('dpgSince')}" if dpgs else "-"
    print(f"fetch: {len(records)} records, {len(dpgs)} selected "
          f"(category={args.category!r}, dpgSince {span}), {len(rows)} source URLs")
    if no_url:
        print(f"fetch: {len(no_url)} DPGs list no URL at all: {', '.join(no_url)}")
    return 0


# ---------------------------------------------------------------------- clone

def repo_dirname(url):
    """<owner>__<repo> from the last two path segments, filesystem-safe."""
    p = urllib.parse.urlsplit(url)
    parts = [s for s in re.sub(r"\.git$", "", p.path.rstrip("/")).split("/") if s]
    parts = parts[-2:] if parts else [p.netloc]
    if len(parts) == 1:
        parts = [p.netloc] + parts
    return re.sub(r"[^A-Za-z0-9._-]+", "_", "__".join(parts)).strip("._") or "repo"


def plan_dirs(rows):
    """Assign each (dpgId, url) a unique directory inside its DPG folder."""
    used = collections.defaultdict(set)
    plan = []
    for r in rows:
        name = repo_dirname(r["url"])
        if name in used[r["dpgId"]]:
            host = urllib.parse.urlsplit(r["url"]).netloc
            name = re.sub(r"[^A-Za-z0-9._-]+", "_", f"{host}__{name}")
        used[r["dpgId"]].add(name)
        plan.append((r["dpgId"], r["url"], name))
    return plan


def git(*argv, cwd=None, timeout=None):
    env = {**os.environ, **GIT_ENV}
    return subprocess.run(["git", *GIT_SAFE, *argv], cwd=cwd, env=env, timeout=timeout,
                          stdin=subprocess.DEVNULL, capture_output=True, text=True,
                          errors="replace")


def last_line(text):
    lines = [l for l in text.strip().splitlines() if l.strip()]
    return clean(lines[-1]) if lines else ""


def clone_one(out, dpg_id, url, name, min_free, timeout, guard):
    dest = out / dpg_id / name
    rel = f"{dpg_id}/{name}"
    if (dest / ".git").is_dir():
        head = git("-C", str(dest), "rev-parse", "HEAD")
        return [dpg_id, url, rel, "exists", head.stdout.strip(), ""]
    try:
        probe = git("ls-remote", url, "HEAD", timeout=120)
    except subprocess.TimeoutExpired:
        return [dpg_id, url, "", "not-a-repo", "", "ls-remote timed out"]
    if probe.returncode != 0:
        return [dpg_id, url, "", "not-a-repo", "", last_line(probe.stderr)]
    if not probe.stdout.strip():
        return [dpg_id, url, "", "empty-repo", "", "ls-remote returned no HEAD"]
    with guard:
        free = shutil.disk_usage(out).free
    if free < min_free:
        return [dpg_id, url, "", "disk-guard", "", f"{free / 2**30:.1f} GB free"]

    tmp = dest.with_name(dest.name + ".partial")
    shutil.rmtree(tmp, ignore_errors=True)
    tmp.parent.mkdir(parents=True, exist_ok=True)
    try:
        r = git("clone", "--depth", "1", "--single-branch", "--no-tags", "--quiet",
                url, str(tmp), timeout=timeout)
    except subprocess.TimeoutExpired:
        shutil.rmtree(tmp, ignore_errors=True)
        return [dpg_id, url, "", "failed", "", f"clone timed out after {timeout}s"]
    if r.returncode != 0:
        shutil.rmtree(tmp, ignore_errors=True)
        return [dpg_id, url, "", "failed", "", last_line(r.stderr)]
    tmp.rename(dest)
    head = git("-C", str(dest), "rev-parse", "HEAD")
    return [dpg_id, url, rel, "cloned", head.stdout.strip(), ""]


def cmd_clone(args):
    out = args.out
    plan = plan_dirs(read_tsv(out / "sources.tsv"))
    min_free = int(args.min_free_gb * 2**30)
    guard, lock = threading.Lock(), threading.Lock()
    results, done = {}, 0
    with concurrent.futures.ThreadPoolExecutor(max_workers=args.jobs) as pool:
        futures = {pool.submit(clone_one, out, d, u, n, min_free, args.timeout, guard): i
                   for i, (d, u, n) in enumerate(plan)}
        for fut in concurrent.futures.as_completed(futures):
            row = fut.result()
            results[futures[fut]] = row
            with lock:
                done += 1
                print(f"[{done}/{len(plan)}] {row[3]:<10} {row[0]} {row[1]}"
                      + (f"  ({row[5]})" if row[5] else ""), file=sys.stderr)
    rows = [results[i] for i in range(len(plan))]
    write_tsv(out / "clone-log.tsv", ["dpgId", "url", "dir", "status", "commit", "detail"], rows)
    counts = collections.Counter(r[3] for r in rows)
    print("clone: " + ", ".join(f"{k}={v}" for k, v in sorted(counts.items())))
    return 0


# ------------------------------------------------------------------ inventory

PRUNE_DIRS = {
    "node_modules", "vendor", "Pods", ".git", "dist", "build", "target", ".venv",
    "venv", "__pycache__", "coverage", ".next", ".cache", ".expo", "third_party",
    "thirdparty", "extlibs", "ExtLibs", "archetype-resources", "maven-archetype",
    "bower_components", ".gradle", ".dart_tool", ".tox", ".mypy_cache",
}
MAX_MANIFEST_BYTES = 5 * 2**20

LANG_BY_EXT = {
    ".py": "Python", ".js": "JavaScript", ".jsx": "JavaScript", ".mjs": "JavaScript",
    ".cjs": "JavaScript", ".ts": "TypeScript", ".tsx": "TypeScript", ".java": "Java",
    ".kt": "Kotlin", ".kts": "Kotlin", ".scala": "Scala", ".groovy": "Groovy",
    ".go": "Go", ".rb": "Ruby", ".php": "PHP", ".cs": "C#", ".fs": "F#",
    ".vb": "Visual Basic", ".swift": "Swift", ".m": "Objective-C", ".mm": "Objective-C",
    ".dart": "Dart", ".rs": "Rust", ".c": "C", ".h": "C/C++ header", ".cc": "C++",
    ".cpp": "C++", ".cxx": "C++", ".hpp": "C++", ".ex": "Elixir", ".exs": "Elixir",
    ".erl": "Erlang", ".clj": "Clojure", ".cljs": "Clojure", ".r": "R", ".jl": "Julia",
    ".lua": "Lua", ".pl": "Perl", ".sh": "Shell", ".vue": "Vue", ".svelte": "Svelte",
    ".hs": "Haskell", ".ml": "OCaml", ".elm": "Elm", ".sol": "Solidity",
}
NOT_A_LANGUAGE = {"Shell", "C/C++ header"}  # counted, but never a repo's main language

# Dependency name -> framework label shown in stack.tsv / summary.md.
FRAMEWORKS = {
    ("npm", "react"): "React", ("npm", "react-native"): "React Native",
    ("npm", "next"): "Next.js", ("npm", "vue"): "Vue", ("npm", "nuxt"): "Nuxt",
    ("npm", "@angular/core"): "Angular", ("npm", "svelte"): "Svelte",
    ("npm", "@sveltejs/kit"): "SvelteKit", ("npm", "express"): "Express",
    ("npm", "@nestjs/core"): "NestJS", ("npm", "fastify"): "Fastify",
    ("npm", "koa"): "Koa", ("npm", "electron"): "Electron", ("npm", "expo"): "Expo",
    ("npm", "@ionic/angular"): "Ionic", ("npm", "@ionic/react"): "Ionic",
    ("npm", "@capacitor/core"): "Capacitor", ("npm", "gatsby"): "Gatsby",
    ("npm", "@remix-run/react"): "Remix", ("npm", "ember-source"): "Ember",
    ("npm", "meteor-node-stubs"): "Meteor", ("npm", "@strapi/strapi"): "Strapi",
    ("pypi", "django"): "Django", ("pypi", "flask"): "Flask", ("pypi", "fastapi"): "FastAPI",
    ("pypi", "tornado"): "Tornado", ("pypi", "streamlit"): "Streamlit",
    ("pypi", "odoo"): "Odoo", ("pypi", "frappe"): "Frappe",
    ("maven", "org.springframework.boot:spring-boot-starter-web"): "Spring Boot",
    ("maven", "org.springframework.boot:spring-boot-starter"): "Spring Boot",
    ("maven", "io.quarkus:quarkus-core"): "Quarkus", ("maven", "io.micronaut:micronaut-core"): "Micronaut",
    ("gradle-plugin", "com.android.application"): "Android",
    ("gradle-plugin", "org.springframework.boot"): "Spring Boot",
    ("composer", "laravel/framework"): "Laravel", ("composer", "symfony/framework-bundle"): "Symfony",
    ("composer", "drupal/core"): "Drupal", ("composer", "drupal/core-recommended"): "Drupal",
    ("composer", "yiisoft/yii2"): "Yii", ("composer", "cakephp/cakephp"): "CakePHP",
    ("rubygems", "rails"): "Rails", ("rubygems", "sinatra"): "Sinatra",
    ("pub", "flutter"): "Flutter", ("hex", "phoenix"): "Phoenix",
    ("go", "github.com/gin-gonic/gin"): "Gin", ("go", "github.com/labstack/echo/v4"): "Echo",
    ("go", "github.com/gofiber/fiber/v2"): "Fiber",
    ("nuget", "Microsoft.AspNetCore.App"): "ASP.NET Core",
}

PEP508_NAME = re.compile(r"^\s*([A-Za-z0-9][A-Za-z0-9._-]*)")


def pep503(name):
    return re.sub(r"[-_.]+", "-", name).lower()


def pep508_names(specs):
    for s in specs:
        if isinstance(s, str):
            m = PEP508_NAME.match(s)
            if m:
                yield m.group(1)


def read_text(path):
    return path.read_text(encoding="utf-8", errors="replace")


# Each parser returns a list of (ecosystem, name, scope). scope is "" when the
# manifest does not say. Parsers raise on unreadable input; the caller records
# the error and the file still counts as a manifest.

def p_package_json(path):
    data = json.loads(read_text(path))
    out = []
    if not isinstance(data, dict):
        return out
    for key, scope in (("dependencies", "runtime"), ("devDependencies", "dev"),
                       ("peerDependencies", "peer"), ("optionalDependencies", "optional")):
        deps = data.get(key)
        if isinstance(deps, dict):
            for name, spec in deps.items():
                if isinstance(spec, str) and spec.startswith(("workspace:", "file:", "link:", "portal:")):
                    continue  # a local package of the same repo
                out.append(("npm", name, scope))
    return out


def p_requirements(path):
    out = []
    for line in read_text(path).splitlines():
        line = line.split(" #")[0].strip()
        if not line or line.startswith(("#", "-")) or "://" in line.split("@")[0]:
            continue
        m = PEP508_NAME.match(line)
        if m:
            out.append(("pypi", m.group(1), ""))
    return out


def p_pyproject(path):
    data = tomllib.loads(read_text(path))
    out = []
    proj = data.get("project", {})
    out += [("pypi", n, "runtime") for n in pep508_names(proj.get("dependencies", []))]
    for specs in (proj.get("optional-dependencies") or {}).values():
        out += [("pypi", n, "optional") for n in pep508_names(specs)]
    for specs in (data.get("dependency-groups") or {}).values():
        out += [("pypi", n, "dev") for n in pep508_names(specs)]
    tool = data.get("tool", {})
    poetry = tool.get("poetry", {})
    groups = [("runtime", poetry.get("dependencies")), ("dev", poetry.get("dev-dependencies"))]
    groups += [("dev", g.get("dependencies")) for g in (poetry.get("group") or {}).values()]
    for scope, deps in groups:
        if isinstance(deps, dict):
            out += [("pypi", n, scope) for n in deps if n.lower() != "python"]
    for key in ("pdm", "uv"):
        dev = (tool.get(key) or {}).get("dev-dependencies")
        if isinstance(dev, dict):
            dev = [s for v in dev.values() for s in v]
        if isinstance(dev, list):
            out += [("pypi", n, "dev") for n in pep508_names(dev)]
    return out


def p_setup_cfg(path):
    cp = configparser.ConfigParser(interpolation=None, strict=False)
    cp.read_string(read_text(path))
    out = []
    if cp.has_option("options", "install_requires"):
        out += [("pypi", n, "runtime")
                for n in pep508_names(cp.get("options", "install_requires").splitlines())]
    if cp.has_section("options.extras_require"):
        for _, v in cp.items("options.extras_require"):
            out += [("pypi", n, "optional") for n in pep508_names(v.splitlines())]
    return out


def p_setup_py(path):
    """setup(...) keywords read from the syntax tree; the file is never run."""
    tree = ast.parse(read_text(path))
    consts = {}  # NAME = <literal> at module level, for install_requires=REQS
    for node in tree.body:
        if isinstance(node, ast.Assign) and len(node.targets) == 1 \
                and isinstance(node.targets[0], ast.Name):
            try:
                consts[node.targets[0].id] = ast.literal_eval(node.value)
            except ValueError:
                pass

    def value(node):
        if isinstance(node, ast.Name):
            return consts.get(node.id)
        try:
            return ast.literal_eval(node)
        except ValueError:
            return None

    out = []
    scopes = {"install_requires": "runtime", "extras_require": "optional", "tests_require": "dev"}
    for node in ast.walk(tree):
        if not isinstance(node, ast.Call):
            continue
        for kw in node.keywords:
            if kw.arg not in scopes:
                continue
            v = value(kw.value)
            specs = [s for vs in v.values() for s in (vs if isinstance(vs, list) else [vs])] \
                if isinstance(v, dict) else v
            if isinstance(specs, (list, tuple)):
                out += [("pypi", n, scopes[kw.arg]) for n in pep508_names(specs)]
    return out


def p_pipfile(path):
    data = tomllib.loads(read_text(path))
    return [("pypi", n, scope)
            for key, scope in (("packages", "runtime"), ("dev-packages", "dev"))
            for n in (data.get(key) or {})]


def p_environment_yml(path):
    out, in_deps, in_pip = [], False, False
    for line in read_text(path).splitlines():
        if re.match(r"^dependencies\s*:", line):
            in_deps = True
            continue
        if in_deps and re.match(r"^\S", line):
            break
        if not in_deps:
            continue
        m = re.match(r"^(\s*)-\s*([^\s#]+)", line)
        if not m:
            continue
        if m.group(2) == "pip:":
            in_pip, pip_indent = True, len(m.group(1))
            continue
        if in_pip and len(m.group(1)) <= pip_indent:
            in_pip = False
        name = re.split(r"[=<>!~ ]", m.group(2).split("::")[-1])[0]
        if name and name not in ("python", "pip"):
            out.append(("pypi" if in_pip else "conda", name, ""))
    return out


def xml_local(tag):
    return tag.rsplit("}", 1)[-1]


def xml_child(el, name):
    for c in el:
        if xml_local(c.tag) == name:
            return (c.text or "").strip()
    return ""


def p_pom(path):
    root = ET.fromstring(path.read_bytes())
    out = []
    for el in root.iter():
        kind = xml_local(el.tag)
        if kind not in ("dependency", "plugin"):
            continue
        g, a = xml_child(el, "groupId"), xml_child(el, "artifactId")
        if not a:
            continue
        if kind == "plugin":
            out.append(("maven", f"{g or 'org.apache.maven.plugins'}:{a}", "plugin"))
        else:
            out.append(("maven", f"{g}:{a}", xml_child(el, "scope") or "compile"))
    return out


GRADLE_CONF = re.compile(
    r"\b(\w*(?:[iI]mplementation|[aA]pi|[cC]ompile|[cC]ompileOnly|[rR]untimeOnly|"
    r"[rR]untime|kapt|ksp|annotationProcessor|classpath|coreLibraryDesugaring|"
    r"developmentOnly|wearApp))\b\s*\(?(.*)")
GRADLE_COORD = re.compile(r"""["']([A-Za-z0-9_.\-]+):([A-Za-z0-9_.\-]+)(?::[^"']*)?["']""")
GRADLE_MAP = re.compile(r"""group\s*[:=]\s*["']([^"']+)["']\s*,\s*name\s*[:=]\s*["']([^"']+)["']""")
GRADLE_PLUGIN = re.compile(r"""(?:\bid\s*\(?\s*|apply\s+plugin\s*:\s*)["']([A-Za-z0-9_.\-]+)["']""")


def p_gradle(path):
    out = []
    for line in read_text(path).splitlines():
        line = line.split("//")[0] if "://" not in line else line
        for m in GRADLE_PLUGIN.finditer(line):
            out.append(("gradle-plugin", m.group(1), "plugin"))
        m = GRADLE_CONF.search(line)
        if not m:
            continue
        conf, rest = m.group(1), m.group(2)
        scope = "dev" if conf.lower().startswith(("test", "androidtest", "debug")) else conf
        for g, a in GRADLE_COORD.findall(rest) + GRADLE_MAP.findall(rest):
            out.append(("maven", f"{g}:{a}", scope))
    return out


def p_versions_toml(path):
    data = tomllib.loads(read_text(path))
    out = []
    for v in (data.get("libraries") or {}).values():
        if isinstance(v, str):
            coord = ":".join(v.split(":")[:2])
        elif isinstance(v, dict):
            coord = v.get("module") or (f"{v['group']}:{v['name']}" if "group" in v and "name" in v else "")
        else:
            coord = ""
        if coord:
            out.append(("maven", coord, ""))
    for v in (data.get("plugins") or {}).values():
        pid = v.split(":")[0] if isinstance(v, str) else (v or {}).get("id")
        if pid:
            out.append(("gradle-plugin", pid, "plugin"))
    return out


def p_sbt(path):
    return [("maven", f"{g}:{a}", "")
            for g, a in re.findall(r'"([^"]+)"\s*%%?%?\s*"([^"]+)"\s*%', read_text(path))]


def p_go_mod(path):
    out, in_block = [], False
    for line in read_text(path).splitlines():
        s = line.strip()
        if s.startswith("require ("):
            in_block = True
            continue
        if in_block and s.startswith(")"):
            in_block = False
            continue
        m = re.match(r"^require\s+(\S+)\s+\S+", s) or (in_block and re.match(r"^(\S+)\s+v\S+", s))
        if m and "// indirect" not in s:
            out.append(("go", m.group(1), ""))
    return out


def p_composer(path):
    data = json.loads(read_text(path))
    out = []
    for key, scope in (("require", "runtime"), ("require-dev", "dev")):
        for name in (data.get(key) or {}) if isinstance(data, dict) else []:
            if name == "php" or name.startswith(("ext-", "lib-")) or "/" not in name:
                continue
            out.append(("composer", name, scope))
    return out


def p_gemfile(path):
    return [("rubygems", n, "")
            for n in re.findall(r"""^\s*gem\s+['"]([^'"]+)['"]""", read_text(path), re.M)]


def p_cargo(path):
    data = tomllib.loads(read_text(path))
    out = []

    def take(tables, scope):
        for name, spec in (tables or {}).items():
            if isinstance(spec, dict):
                if "path" in spec and "version" not in spec and "git" not in spec:
                    continue  # a crate of the same workspace
                name = spec.get("package", name)
            out.append(("cargo", name, scope))

    for holder in [data, data.get("workspace", {})] + list((data.get("target") or {}).values()):
        take(holder.get("dependencies"), "runtime")
        take(holder.get("dev-dependencies"), "dev")
        take(holder.get("build-dependencies"), "build")
    return out


def p_pubspec(path):
    out, section, child_indent, skip_indent = [], None, None, None
    sdk_pkgs = {"flutter", "flutter_test", "flutter_localizations", "flutter_driver",
                "integration_test", "flutter_web_plugins"}
    for line in read_text(path).splitlines():
        if not line.strip() or line.lstrip().startswith("#"):
            continue
        indent = len(line) - len(line.lstrip())
        if indent == 0:
            m = re.match(r"^(dependencies|dev_dependencies)\s*:", line)
            section = (m and ("runtime" if m.group(1) == "dependencies" else "dev")) or None
            child_indent = None
            continue
        if not section:
            continue
        if child_indent is None:
            child_indent = indent
        if indent == child_indent:
            m = re.match(r"^\s*([A-Za-z0-9_]+)\s*:", line)
            if m and m.group(1) not in sdk_pkgs:
                out.append(("pub", m.group(1), section))
    return out


def p_csproj(path):
    root = ET.fromstring(path.read_bytes())
    out = []
    for el in root.iter():
        kind = xml_local(el.tag)
        if kind in ("PackageReference", "PackageVersion"):
            name = el.get("Include") or el.get("Update")
            if name:
                out.append(("nuget", name, ""))
        elif kind == "package" and el.get("id"):  # packages.config
            out.append(("nuget", el.get("id"), ""))
    return out


def p_podfile(path):
    return [("cocoapods", n, "")
            for n in re.findall(r"""^\s*pod\s+['"]([^'"]+)['"]""", read_text(path), re.M)]


def p_package_swift(path):
    out = []
    for url in re.findall(r"""\.package\s*\([^)]*?url\s*:\s*"([^"]+)\"""", read_text(path), re.S):
        parts = [s for s in re.sub(r"\.git$", "", urllib.parse.urlsplit(url).path).split("/") if s]
        out.append(("swiftpm", "/".join(parts[-2:]) or url, ""))
    return out


def p_description(path):
    out, fields, cur = [], {}, None
    for line in read_text(path).splitlines():
        m = re.match(r"^([A-Za-z][A-Za-z0-9/@.-]*):\s*(.*)$", line)
        if m:
            cur = m.group(1)
            fields[cur] = m.group(2)
        elif cur and line[:1].isspace():
            fields[cur] += " " + line.strip()
    for key, scope in (("Depends", "runtime"), ("Imports", "runtime"),
                       ("LinkingTo", "build"), ("Suggests", "optional")):
        for item in fields.get(key, "").split(","):
            name = re.sub(r"\(.*?\)", "", item).strip()
            if name and name != "R":
                out.append(("cran", name, scope))
    return out


def p_mix(path):
    text = read_text(path)
    m = re.search(r"defp?\s+deps\b.*?\bdo\b(.*?)\n\s*end\b", text, re.S)
    return [("hex", n, "") for n in re.findall(r"\{\s*:([a-z_][a-z0-9_]*)\s*,", m.group(1) if m else "")]


def p_deps_edn(path):
    return [("maven", n.replace("/", ":") if "/" in n else f"{n}:{n}", "")
            for n in re.findall(r"([A-Za-z0-9_.\-]+/[A-Za-z0-9_.\-$]+)\s*\{\s*:(?:mvn/version|git/|local/root)",
                                read_text(path))]


def p_project_clj(path):
    text = read_text(path)
    m = re.search(r":dependencies\s*\[(.*?)\]\s*(?::|\)\s*$)", text, re.S)
    return [("maven", n.replace("/", ":") if "/" in n else f"{n}:{n}", "")
            for n in re.findall(r'\[\s*([A-Za-z0-9_.\-/]+)\s+"', m.group(1) if m else "")]


def p_odoo_manifest(path):
    data = ast.literal_eval(read_text(path).strip())
    ext = (data.get("external_dependencies") or {}) if isinstance(data, dict) else {}
    return [("pypi", n, "runtime") for n in pep508_names(ext.get("python") or [])]


def p_cordova_config(path):
    root = ET.fromstring(path.read_bytes())
    return [("npm", el.get("name"), "plugin") for el in root.iter()
            if xml_local(el.tag) == "plugin" and el.get("name")]


def parser_for(rel_parts):
    """Pick the parser for a file from its name (and parent dir name)."""
    name = rel_parts[-1]
    parent = rel_parts[-2] if len(rel_parts) > 1 else ""
    low = name.lower()
    exact = {
        "package.json": p_package_json, "pyproject.toml": p_pyproject,
        "setup.cfg": p_setup_cfg, "setup.py": p_setup_py, "Pipfile": p_pipfile,
        "environment.yml": p_environment_yml, "environment.yaml": p_environment_yml,
        "pom.xml": p_pom, "build.gradle": p_gradle, "build.gradle.kts": p_gradle,
        "libs.versions.toml": p_versions_toml, "build.sbt": p_sbt, "go.mod": p_go_mod,
        "composer.json": p_composer, "Gemfile": p_gemfile, "Cargo.toml": p_cargo,
        "pubspec.yaml": p_pubspec, "packages.config": p_csproj,
        "Directory.Packages.props": p_csproj, "Directory.Build.props": p_csproj,
        "Podfile": p_podfile, "Package.swift": p_package_swift, "DESCRIPTION": p_description,
        "mix.exs": p_mix, "deps.edn": p_deps_edn, "project.clj": p_project_clj,
        "__manifest__.py": p_odoo_manifest,
    }
    if name in exact:
        return exact[name]
    if low.endswith((".csproj", ".fsproj", ".vbproj")):
        return p_csproj
    if (low.startswith("requirements") and low.endswith((".txt", ".in"))) or \
            (parent == "requirements" and low.endswith((".txt", ".in"))):
        return p_requirements
    if name == "config.xml" and len(rel_parts) <= 2:  # Cordova keeps it at the project root
        return p_cordova_config
    return None


def norm_name(eco, name):
    name = name.strip()
    if eco == "pypi":
        return pep503(name)
    if eco in ("npm", "composer", "swiftpm"):
        return name.lower()
    return name


def scan_repo(repo_dir):
    """Walk one clone: manifests -> deps, file extensions -> languages."""
    manifests, errors = [], []
    langs = collections.Counter()
    for dirpath, dirnames, filenames in os.walk(repo_dir):
        dirnames[:] = sorted(d for d in dirnames if d not in PRUNE_DIRS)
        rel_dir = Path(dirpath).relative_to(repo_dir)
        for fn in sorted(filenames):
            full = Path(dirpath) / fn
            ext = os.path.splitext(fn)[1].lower()
            if ext in LANG_BY_EXT:
                langs[LANG_BY_EXT[ext]] += 1
            parser = parser_for((rel_dir / fn).parts)
            if not parser or full.is_symlink():
                continue
            rel = str(rel_dir / fn)
            try:
                if full.stat().st_size > MAX_MANIFEST_BYTES:
                    raise ValueError("larger than 5 MB, not parsed")
                deps = parser(full)
            except Exception as e:  # untrusted input: record and keep going
                errors.append((rel, f"{type(e).__name__}: {clean(e)[:200]}"))
                deps = None
            manifests.append((rel, parser.__name__[2:], deps))
    return manifests, errors, langs


def main_languages(langs, n=3):
    real = [(k, v) for k, v in langs.most_common() if k not in NOT_A_LANGUAGE]
    return [k for k, _ in real[:n]] or [k for k, _ in langs.most_common(1)]


def cmd_inventory(args):
    out = args.out
    if not (out / "dpgs.json").is_file():
        die(f"{out}/dpgs.json not found - run the previous step first", 2)
    dpgs = json.loads((out / "dpgs.json").read_text(encoding="utf-8"))
    clone_log = read_tsv(out / "clone-log.tsv")
    cloned = [r for r in clone_log if r["status"] in ("cloned", "exists")]

    stack_rows, dep_rows, err_rows = [], [], []
    per_dpg = collections.defaultdict(lambda: {"repos": [], "langs": collections.Counter(),
                                               "ecos": set(), "fw": set(), "deps": set()})
    n_manifests = n_parsed = 0
    for i, r in enumerate(cloned, 1):
        print(f"[{i}/{len(cloned)}] {r['dir']}", file=sys.stderr)
        repo_dir = out / r["dir"]
        repo = r["dir"].split("/", 1)[1]
        manifests, errors, langs = scan_repo(repo_dir)
        agg = per_dpg[r["dpgId"]]
        agg["repos"].append(repo)
        agg["langs"].update(langs)
        err_rows += [[r["dpgId"], repo, rel, msg] for rel, msg in errors]
        repo_deps = set()
        for rel, kind, deps in manifests:
            n_manifests += 1
            if deps is None:
                stack_rows.append([r["dpgId"], repo, kind, rel, "error"])
                continue
            n_parsed += 1
            uniq = sorted({(e, norm_name(e, n), s) for e, n, s in deps if n.strip()})
            stack_rows.append([r["dpgId"], repo, kind, rel, len(uniq)])
            for eco, name, scope in uniq:
                dep_rows.append([r["dpgId"], repo, eco, clean(name), scope, rel])
                repo_deps.add((eco, name))
                agg["ecos"].add(eco)
                if (eco, name) in FRAMEWORKS:
                    agg["fw"].add(FRAMEWORKS[(eco, name)])
        if not manifests:
            stack_rows.append([r["dpgId"], repo, "-", "(no manifest found)", 0])
        agg["deps"] |= repo_deps

    write_tsv(out / "stack.tsv", ["dpgId", "repo", "manifest_type", "manifest", "deps"], stack_rows)
    write_tsv(out / "deps.tsv", ["dpgId", "repo", "ecosystem", "dependency", "scope", "manifest"],
              dep_rows)
    write_tsv(out / "inventory-errors.tsv", ["dpgId", "repo", "manifest", "error"], err_rows)

    uniq = collections.defaultdict(lambda: (set(), set()))
    for d, repo, eco, name, _, _ in dep_rows:
        uniq[(eco, name)][0].add(d)
        uniq[(eco, name)][1].add((d, repo))
    urows = sorted(([eco, name, len(ds), len(rs), ",".join(sorted(ds)[:5])]
                    for (eco, name), (ds, rs) in uniq.items()),
                   key=lambda x: (x[0], -x[2], x[1]))
    write_tsv(out / "deps-unique.tsv",
              ["ecosystem", "dependency", "dpgs", "repos", "example_dpgIds"], urows)

    write_summary(out, dpgs, read_tsv(out / "sources.tsv"), clone_log, per_dpg,
                  n_manifests, n_parsed, err_rows, len(dep_rows), urows)
    print(f"inventory: {len(cloned)} repos, {n_parsed} of {n_manifests} manifests parsed "
          f"({len(err_rows)} errors), {len(dep_rows)} dependency rows, "
          f"{len(urows)} unique dependencies")
    return 0


def md_cell(s):
    return clean(s).replace("|", "\\|")


def write_summary(out, dpgs, sources, clone_log, per_dpg, n_manifests, n_parsed,
                  err_rows, n_dep_rows, urows):
    status = collections.Counter(r["status"] for r in clone_log)
    by_dpg = collections.defaultdict(collections.Counter)
    for r in clone_log:
        by_dpg[r["dpgId"]][r["status"]] += 1
    eco_count = collections.Counter(u[0] for u in urows)
    lines = [
        "# DPG corpus summary", "",
        f"- DPGs selected: {len(dpgs)}",
        f"- Source URLs: {len(sources)}",
        "- Clone results: " + ", ".join(f"{k} {v}" for k, v in sorted(status.items())),
        f"- Manifests: {n_parsed} of {n_manifests} parsed, {len(err_rows)} errors "
        "(inventory-errors.tsv)",
        f"- Direct dependency rows: {n_dep_rows}; unique dependencies: {len(urows)}",
        "- Unique dependencies by ecosystem: "
        + ", ".join(f"{k} {v}" for k, v in eco_count.most_common()),
        "", "## Per DPG", "",
        "| dpgId | name | dpgSince | repos | languages | frameworks | ecosystems "
        "| deps | self-declared proprietary deps |",
        "|---|---|---|---|---|---|---|---|---|",
    ]
    for d in dpgs:
        gid = d["dpgId"]
        agg = per_dpg.get(gid)
        c = by_dpg.get(gid, collections.Counter())
        repos = f"{c['cloned'] + c['exists']} of {sum(c.values())}"
        langs = ", ".join(main_languages(agg["langs"])) if agg else "-"
        fw = ", ".join(sorted(agg["fw"])) if agg and agg["fw"] else "-"
        ecos = ", ".join(sorted(agg["ecos"])) if agg and agg["ecos"] else "-"
        ndeps = len(agg["deps"]) if agg else 0
        declared = {0: "no", 1: "yes"}.get(d.get("isProprietaryDependencies"), "-")
        lines.append(f"| {gid} | {md_cell(d.get('name', ''))} | {d.get('dpgSince', '')} | {repos} "
                     f"| {langs} | {fw} | {ecos} | {ndeps} | {declared} |")
    skipped = [r for r in clone_log if r["status"] not in ("cloned", "exists")]
    lines += ["", f"## Skipped sources ({len(skipped)})", "",
              "| dpgId | url | status | detail |", "|---|---|---|---|"]
    lines += [f"| {r['dpgId']} | {md_cell(r['url'])} | {r['status']} | {md_cell(r['detail'])} |"
              for r in skipped]
    no_src = [d["dpgId"] for d in dpgs if not by_dpg.get(d["dpgId"])]
    no_repo = [d["dpgId"] for d in dpgs if by_dpg.get(d["dpgId"]) and not per_dpg.get(d["dpgId"])]
    lines += ["", "## DPGs with nothing to inventory", "",
              f"- No source URL in the API: {', '.join(no_src) or 'none'}",
              f"- URLs listed, none cloneable: {', '.join(no_repo) or 'none'}", ""]
    (out / "summary.md").write_text("\n".join(lines), encoding="utf-8")


# ------------------------------------------------------------------- coverage

def decl_regex(eco, name):
    """Regex locating a dependency's declaration in its manifest."""
    if eco == "pypi":  # PEP 503 spelling; must START a requirement, so an extra
        # (sentry-sdk[celery]) or a config string mentioning the name is not one
        return re.compile(r"(^\s*[\"']?|[=,\[]\s*[\"'])"
                          + r"[-_.]+".join(map(re.escape, re.split(r"[-_.]+", name)))
                          + r"(?![\w-])", re.I)
    if eco in ("npm", "composer"):  # a JSON key with its value, not a mention in "scripts"
        return re.compile(r"[\"']" + re.escape(name) + r"[\"']\s*:\s*(\"[^\"]*\"|'[^']*')?", re.I)
    if eco == "maven":  # gradle "g:a[:v]", pom/toml carry the artifactId
        return re.compile(r"(?<![\w.-])" + re.escape(name.split(":")[-1]) + r"(?![\w-])", re.I)
    return re.compile(r"(?<![\w@/.-])" + re.escape(name) + r"(?![\w-])", re.I)


COMMENT = re.compile(r"^\s*(#|//|<!--|/?\*)")


def pom_block(text_lines, i):
    """The <dependency>/<plugin> element around line i of a pom.xml."""
    lo = i
    while lo > max(0, i - 15) and not re.search(r"<(dependency|plugin)[\s>]", text_lines[lo]):
        lo -= 1
    hi = i
    while hi < min(len(text_lines) - 1, i + 15) and not re.search(r"</(dependency|plugin)>", text_lines[hi]):
        hi += 1
    return " ".join(l.strip() for l in text_lines[lo:hi + 1])


def decl_lines(text_lines, eco, name, manifest=""):
    """The manifest text that declares `name`, one string per declaration.
    JSON manifests give the `"name": "spec"` pair only, because JSON may hold
    every dependency on one line. A pom.xml gives the enclosing <dependency> or
    <plugin> element (the groupId sits on another line); commented-out blocks
    and comment lines never count. Other maven sources
    (Gradle, version catalogs) give the line with the full group:artifact,
    falling back to the artifactId line for split forms. Never neighbouring
    lines: in a build.gradle those are other dependencies."""
    if eco == "maven":
        group, _, artifact = name.rpartition(":")
        if manifest.endswith("pom.xml"):
            rx = re.compile(r"<artifactId>\s*" + re.escape(artifact) + r"\s*</artifactId>", re.I)
            blocks = [pom_block(text_lines, i) for i, l in enumerate(text_lines) if rx.search(l)]
            return [b for b in blocks if not b.startswith("<!--")
                    and (not group or "${" in group or group.lower() in b.lower())]
        full = re.compile(r"(?<![\w.-])" + re.escape(name) + r"(?![\w.-])", re.I)
        code = [l for l in text_lines if not COMMENT.match(l)]
        hits = [l.strip() for l in code if full.search(l)]
        return hits or [l.strip() for l in code if decl_regex(eco, name).search(l)]
    rx = decl_regex(eco, name)
    out = []
    for line in text_lines:
        m = rx.search(line)
        if m and not COMMENT.match(line) and not re.search(r"extras\s*=\s*\[[^\]]*$", line[:m.start() + 1]):
            out.append(m.group(0) if eco in ("npm", "composer") else line.strip())
    return out


def load_patterns(path):
    groups = []
    for line in Path(path).read_text(encoding="utf-8").splitlines():
        if not line.strip() or line.startswith("#"):
            continue
        cols = line.split("\t")
        if len(cols) >= 2 and cols[1]:
            groups.append((cols[0], cols[1]))
    if not groups:
        die(f"no pattern groups in {path}", 2)
    return groups


def match_groups(texts, groups):
    """{index of text: [group labels]} using rg -in, exactly like scan.sh."""
    hits = collections.defaultdict(list)
    with tempfile.NamedTemporaryFile("w", suffix=".txt", encoding="utf-8", delete=False) as f:
        f.write("\n".join(t.replace("\n", " ") for t in texts) + "\n")
        tmp = f.name
    try:
        for label, pat in groups:
            r = subprocess.run(["rg", "-in", "--no-filename", "-e", pat, "--", tmp],
                               capture_output=True, text=True, errors="replace")
            if r.returncode == 2:
                die(f"rg rejected the pattern of group {label!r}: {last_line(r.stderr)}")
            for line in r.stdout.splitlines():
                hits[int(line.split(":", 1)[0]) - 1].append(label)
    finally:
        os.unlink(tmp)
    return hits


def cmd_coverage(args):
    out = args.out
    if shutil.which("rg") is None:
        die("ripgrep (rg) is required", 127)
    groups = load_patterns(args.patterns)
    prop = {(r["ecosystem"], r["dependency"]): r for r in read_tsv(out / "proprietary.tsv")
            if r.get("verdict", "proprietary") != "not"}
    deps = read_tsv(out / "deps.tsv")

    # One text per (dependency row, declaration); all deps, so false positives show too.
    cache, texts, owner = {}, [], []
    for i, d in enumerate(deps):
        mpath = out / d["dpgId"] / d["repo"] / d["manifest"]
        if mpath not in cache:
            try:
                cache = {mpath: read_text(mpath).splitlines()}  # deps.tsv is grouped by manifest
            except OSError:
                cache = {mpath: []}
        for t in decl_lines(cache[mpath], d["ecosystem"], d["dependency"], d["manifest"]):
            texts.append(t[:2000])
            owner.append(i)
    hits = match_groups(texts, groups)

    by_dep = collections.defaultdict(lambda: {"decls": 0, "groups": collections.Counter(),
                                              "dpgs": set(), "example": ""})
    for ti, i in enumerate(owner):
        d = deps[i]
        agg = by_dep[(d["ecosystem"], d["dependency"])]
        agg["decls"] += 1
        agg["groups"].update(set(hits.get(ti, [])))
        if not agg["example"]:
            agg["example"] = clean(texts[ti])[:160]
    for d in deps:
        by_dep[(d["ecosystem"], d["dependency"])]["dpgs"].add(d["dpgId"])

    rows, other = [], []
    for key, agg in sorted(by_dep.items()):
        g = ",".join(sorted(agg["groups"]))
        if key in prop:
            p = prop[key]
            status = "caught" if agg["groups"] else ("gap" if agg["decls"] else "no-decl-line")
            rows.append([key[0], key[1], len(agg["dpgs"]), p.get("verdict", ""), p.get("vendor", ""),
                         p.get("capability", ""), status, g, agg["example"]])
        elif agg["groups"]:
            other.append([key[0], key[1], len(agg["dpgs"]), g, agg["example"]])
    missing = sorted(k for k in prop if k not in by_dep)
    rows += [[e, n, 0, prop[(e, n)].get("verdict", ""), prop[(e, n)].get("vendor", ""),
              prop[(e, n)].get("capability", ""), "not-in-deps", "", ""] for e, n in missing]

    write_tsv(out / "coverage.tsv", ["ecosystem", "dependency", "dpgs", "verdict", "vendor",
                                     "capability", "status", "groups", "example_decl"], rows)
    write_tsv(out / "coverage-other.tsv", ["ecosystem", "dependency", "dpgs", "groups",
                                           "example_decl"], other)
    counts = collections.Counter(r[6] for r in rows)
    print(f"coverage: {len(rows)} proprietary dependencies checked against {len(groups)} groups: "
          + ", ".join(f"{k} {v}" for k, v in sorted(counts.items()))
          + f"; {len(other)} non-proprietary dependencies matched by a group")
    return 0


# ----------------------------------------------------------------------- main

def main(argv=None):
    ap = argparse.ArgumentParser(description=__doc__.split("\n\n")[0],
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    sub = ap.add_subparsers(dest="cmd", required=True)

    def add(name, help_):
        p = sub.add_parser(name, help=help_)
        p.add_argument("out", nargs="?", type=Path, default=DEFAULT_OUT,
                       help=f"corpus directory (default: {DEFAULT_OUT})")
        return p

    for p in (add("fetch", "select DPGs and list their source URLs"),
              add("all", "fetch, clone and inventory")):
        p.add_argument("--limit", type=int, default=100)
        p.add_argument("--category", default="Open Software")
        p.add_argument("--api", default=API_URL)
        p.add_argument("--from-file", help="read the API response from a file instead")
    for p in (add("clone", "shallow-clone every source URL that is a git repository"),
              sub.choices["all"]):
        p.add_argument("--jobs", type=int, default=4)
        p.add_argument("--min-free-gb", type=float, default=2.0)
        p.add_argument("--timeout", type=int, default=1800, help="seconds per clone")
    add("inventory", "list direct declared dependencies of every clone")
    add("coverage", "check proprietary.tsv against the pattern table").add_argument(
        "--patterns", type=Path, default=SKILL_ROOT / "references" / "patterns.tsv")

    args = ap.parse_args(argv)
    if args.cmd == "all":
        return cmd_fetch(args) or cmd_clone(args) or cmd_inventory(args)
    return {"fetch": cmd_fetch, "clone": cmd_clone, "inventory": cmd_inventory,
            "coverage": cmd_coverage}[args.cmd](args)


if __name__ == "__main__":
    sys.exit(main())
