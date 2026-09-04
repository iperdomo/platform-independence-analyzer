# Triage, Noise, and Scale

What to do with scan output *before* drafting findings. A mid-sized repository
produces a few dozen hits and needs none of this. A large one produces
thousands - roughly 6,000 for a Moodle-class codebase, 4,000 of them inside a
single committed third-party tree - and "Tier 2 prunes it" is not a plan at
that volume. The report must reflect the repository, not the grep.

---

## T1. Triage order

1. Read the scan's **HITS BY DIRECTORY** table first, not the hits.
2. Classify whole *trees* in one decision: committed third-party code (T2),
   generated output, translation catalogs, test fixtures.
3. Only then read the residual first-party hits, file by file.
4. If a single vendor still has many first-party hit files, write one
   **aggregate finding** for it rather than one finding per file (T5).

Reading 4,000 hits sequentially and then discovering that 3,900 of them were a
vendored SDK is the failure this order exists to prevent.

## T2. Committed third-party trees

`vendor/` is only the best-known name. Real shapes from the corpus:

- a PHP application committing an entire payment SDK under
  `htdocs/includes/<vendor>/<vendor>-php/` - hundreds of hits, none of them
  the application's own code;
- a learning platform keeping third-party libraries under `public/lib/`, each
  with its own nested `composer.json`, and an inventory file
  (`thirdpartylibs.xml`) naming them;
- a game engine committing minified Firebase and Shopify SDKs under
  `Extensions/` and `ExtLibs/`;
- a Java monolith committing a rich-text editor twice and five near-duplicate
  template trees, multiplying every hit about fivefold.

**How to recognize one**: a `LICENSE`/`COPYING` file inside a subdirectory, an
upstream copyright header, minified or bundled files, a nested manifest
describing a library rather than a project, a directory named after the vendor,
or an inventory file listing third-party libraries. `scan.sh` flags directories
carrying these markers in its HITS BY DIRECTORY table - the flag is a prompt to
look, not a verdict.

**The rule**: a vendored SDK tree is **evidence that the vendor is used**, and
that fact belongs in the report. It is *not* hundreds of findings, and its
internal call sites are not violations - they are the vendor's own code calling
itself. Classification happens in **first-party code**: which of the
project's own files call into that tree, and from what layer. Write it up as
one finding naming the vendor, cite the tree once with its size ("the Stripe
PHP SDK is committed at `htdocs/includes/stripe/stripe-php/`, 400+ files"), and
then cite the first-party call sites normally.

A vendored tree also changes the remediation advice: the dependency cannot be
swapped by changing a manifest line, because there is no manifest line.

## T3. What the scan excludes, and what that costs

`scripts/scan.sh` prints its exclusion list in the header of every run. It
covers `.gitignore`d paths plus: `vendor/`, `Pods/`, `*.pbxproj`, `*.orig`,
`*.rej`, `.expo/`, lock files, `*.md`, committed build output (`dist/`,
`build/`, `out/`, `*.min.js`, `*.min.css`, `*.bundle.js`), committed
third-party trees (`third_party/`, `thirdparty/`, `extlibs/`), translation
catalogs (`locales/`, `*.po`, `*.pot`, `*.mo`, `*.arb`, `*.xlf`), and
`.ipynb_checkpoints/`.

This list is deliberately the same as SKILL.md Step 1's. Two consequences to
state honestly in the report when they apply:

- **A vendor whose only trace lives in an excluded path produces no hits.**
  Committed build output is the common case: a tracked `dist/` bundling a
  vendor SDK means the *source* should show it too - if it does not, say so
  rather than reporting the repo clean.
- **Translation catalogs under other names** (`langs/`, `lang/`, `i18n/`,
  `translations/`) are not excluded, because the names are not conventional
  enough to guess. They show up in the directory table as a large block of
  hits; classify the tree once and move on.

## T4. Known pattern collisions

Expect these; they are not scanner bugs, and Tier 2 should reject them fast.

| Pattern | Collides with | Where seen |
|---|---|---|
| `amplitude.` | GLSL shader code (`amplitude` is a wave parameter) | Game engine filter shaders |
| `mongoose` | The embedded C web server of the same name | Game engine IDE runtime |
| `segment` | Audio and NLP segmentation code | Speech-to-text repos |
| `base_url` | Ordinary API-client config and test fixtures | Any REST client |
| `heap` | The data structure | Anywhere |
| `replicate` | Database replication (hence the pattern requires `replicate.run`/`.Client`) | Backends |
| `modal` | UI modals (hence the pattern requires `modal.Function`/`modal.App`) | Frontends |
| `disqus`, and any vendor name | Icon-name lists (`material-community-icons` ships hundreds of brand names) | Mobile/web apps |
| `UA-`, `G-`, `GTM-` | Lowercase identifiers under `-i` (hence these are case-pinned with `(?-i:...)`) | Anywhere |
| Vendor names in prose | Comments, changelogs, docs, allowlists, sample config | Everywhere |

When a collision costs more than it earns, tighten the pattern in
`references/patterns.tsv` rather than teaching the reader to ignore it.

## T5. Large repositories: aggregate findings

One finding per file does not scale, and it misrepresents the risk: 47 files
importing one vendor inside one workspace is *one* coupling with 47 call sites,
not 47 couplings.

**Rule**: when a vendor has more than roughly **10 first-party hit files within
one sub-project**, write a single aggregate finding:

- title it after the vendor and the sub-project;
- give a **location count** ("47 files, 210 call sites in `core/`");
- cite three to five *representative* `path:line` sites, chosen to span the
  layers involved (one domain call, one adapter if any, one entry point);
- list the full file set in the File Index, not in the finding body;
- keep the severity of the worst site, and say which site that is.

Below that threshold, keep one finding per file - the per-file detail is what
makes small reports actionable.

Aggregation happens **before** Tier 2, so the verifier sees a small number of
substantive claims rather than a flood of near-duplicates.

## T6. Jupyter notebooks

Notebooks are JSON, and ripgrep does match inside them, but the citations are
misleading and the noise is real:

- **Line numbers cite JSON lines**, not notebook lines. Cite
  `notebook.ipynb` **cell N** (and the line within the cell) instead, so a
  reader can find the code.
- **Multi-line calls are split** across elements of a `"source"` array, so a
  pattern spanning lines will not match. A vendor call can be present and
  unmatched.
- **Base64 outputs inflate everything** - images and plots stored in the
  notebook. Read `"source"` cells; ignore `"outputs"`.
- `.ipynb_checkpoints/` duplicates every cell of its notebook and is excluded.

Two structural cases:

- **Notebooks-as-source repositories.** In an nbdev project the `.py` files are
  *generated* from notebooks; auditing only the `.py` output misses the source
  of truth, and reporting a finding in generated code misplaces the fix. Scan
  the notebooks and cite them.
- **A directory named `notebooks/` may contain ordinary `.py` code.** Never
  skip a path by name; check what is in it.

## T7. Declared vs wired - check both directions

Two different errors, and a report should be immune to both:

- **Declared but never wired** - a dependency in the manifest with zero source
  references (a dead Azure SDK entry, a Gradle plugin on the classpath that is
  never applied, a retired App Center dependency). This is **not** a finding:
  it goes under Acceptable Dependencies as a declared-but-unused dependency,
  ideally with a note that it can be deleted.
- **Wired but never declared** - source or config that reaches a vendor with no
  manifest entry anywhere: `[FIRApp configure]` in an `AppDelegate.m` beside a
  `GoogleService-Info.plist` while the Podfile names no Firebase pod; a raw
  HTTP call to a vendor endpoint; a git-URL dependency. This **is** a finding,
  and it is the one a manifest-driven audit misses entirely.

Both checks are cheap: for each declared candidate, one grep for source hits;
for each source hit, one look at whether any manifest declares it.
