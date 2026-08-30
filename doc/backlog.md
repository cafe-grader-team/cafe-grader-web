# Backlog

Design refactors, deferred decisions, and "someday" follow-ups that don't yet
warrant a GitHub issue or fit in a single TODO comment. Each entry should be
short — title, why it matters, current state, proposed direction, rough size.
Trim or move to an issue when you start the work.

Conventions:
- One section per entry. Keep them grep-able.
- Cite file paths so the next reader (or Claude) can jump in cold.
- Don't put per-commit TODOs here — those go inline as `# TODO(scope): …`.
- Don't put scheduled or assigned work here — that goes on GitHub.
- When an entry is resolved, cut it to a pointer block (what shipped, rev, where
  the durable record lives, any residual) and move it to the `## Resolved` ledger
  at the bottom, newest first. The full write-up stays in `hg log`, the CHANGELOG
  and the linked docs.

---

## Memory accounting for C/C++ — address space vs cgroup (POLICY + a real bug)

**Raised 2026-08-03 from the CMS migration validation.** Three separate things
are tangled here; separating them makes the decision much easier.

### The mechanics (verified on both sides)

Both graders run isolate. Cafe passes `-m <KB>` for C/C++ → **RLIMIT_AS**, which
caps *address space*: everything the process maps, including memory reserved and
never touched. CMS passes `--cg-mem` → **cgroup accounting**, which caps pages
actually faulted in (RSS).

Concretely: a global `int dp[5000][5000]` is 100 MB of address space the instant
the binary maps its BSS, so cafe kills it at startup even if the solution touches
2 MB. Under cgroups the untouched pages cost ~nothing and it runs. Cafe fails on
*declaration*; CMS fails on *use*.

Cafe already uses cgroups for java/digital/go/python
(`app/engine/judge_base.rb#isolate_need_cg_by_lang`) — C/C++ are the exception.
isolate supports **both** flags simultaneously (`-m` and `--cg-mem` are separate
options), which enables the hybrid below.

### Issue 1 — POLICY: should unused declared memory count? (legitimate either way)

**Cafe style (address space) — for:**
- Deterministic: the verdict never depends on which testcase or how much of the
  array gets touched. Same program, same verdict, every run.
- Teaches memory discipline explicitly: "your solution must FIT in 256 MB" is a
  real competitive-programming skill, and declaring `MAXN` far beyond the limit
  is caught immediately rather than tolerated.
- Prevents lucky passes: a solution declaring 1 GB but touching little passes the
  given tests under cgroups, then dies on data that touches more. Address-space
  limiting rejects it consistently.
- Fails fast (cheaper to grade).

**Cafe style — against:**
- Counts things the student does not control: the static binary's mappings,
  allocator arenas, thread stacks, libstdc++'s own reservations. A solution
  genuinely using 50 MB can show substantially more address space.
- Penalises a widely-taught idiom (declare `dp[MAXN][MAXN]`, use a submatrix).
- Diverges from IOI / CMS / Codeforces, where limits are RSS-based. Students
  trained elsewhere — and problems authored elsewhere — assume the other model.
- Linux over-commits by default, so reserved-but-untouched memory costs the
  machine nothing; the limit measures something that is not a real resource cost.

**cgroup style — for:** measures what the machine actually pays; matches the
convention every imported problem was authored against; enables correct MLE
reporting (see Issue 2). **Against:** allows declare-huge-touch-little
solutions to pass; verdict can vary by testcase; may count page cache for files
the sandbox reads (needs testing on large-input tasks).

### Issue 2 — A BUG, independent of the policy choice

```
Evaluation.count                          6,922,221
Evaluation.where(result: :memory_limit)           0     <-- never, not once
Evaluation.where(result: :crash)            555,119     (8.0%)
```

**Cafe has never once reported "memory limit exceeded" for C/C++.** Under
`RLIMIT_AS`, an over-limit allocation makes `malloc` return NULL or throw
`bad_alloc`; the process dies by signal and isolate reports a runtime error, so
cafe records `crash` (`x`). Students exceeding memory are told their program
crashed — indistinguishable from a segfault. isolate can only report a genuine
memory-limit kill through cgroup accounting (`cg-oom-killed`), so **accurate MLE
verdicts require cgroups regardless of which policy is chosen for the limit.**

### Issue 3 — Imported CMS problems are effectively stricter than authored

Their `memory_limit` values were calibrated against RSS semantics. Enforced as
address space, the same number is a tighter budget, so students lose points they
earned on the source instance. Measured in the migration sweep: submissions CMS
scored 100 scored **0** here; enabling cgroups took two affected tasks from 8-9/10
to **10/10 exact** (`doc/CMS-Migration.md` §5.1).

### Measured behaviour (isolate experiments, 2026-08-03)

**How RSS/cgroup accounting actually charges.** A program declaring a 1 GiB
global array, touching the first 64 MiB, then the last 64 MiB, leaving the
middle untouched:

| point | RSS |
|---|---|
| declared, nothing touched | 1.6 MB |
| after touching FIRST 64 MiB | 67 MB |
| after touching LAST 64 MiB | **133 MB** |

So cgroup accounting charges the **sum of every distinct page ever touched** —
not the maximum of the regions, not the whole array. Untouched pages are never
charged; once an anonymous page is faulted in it stays charged (a judge box has
no swap, so nothing is reclaimed). Granularity is one page: touching a single
byte charges 4 KB. Note transparent hugepages are `madvise` on this host; under
`always`, a single byte could charge a 2 MB huge page and inflate sparse
patterns considerably.

**What `-m` and `--cg-mem` do together.** They are independent limits and both
are enforced — whichever binds first wins. Measured with a 128 MiB limit and a
program declaring 256 MiB:

| flags | declares 256 MiB, touches 0 | declares 256 MiB, touches 200 MiB |
|---|---|---|
| `-m` only (today) | killed, **signal 11**, `max-rss: 816 KB` | killed at startup, same |
| `--cg-mem` only | **runs fine** | killed, **signal 9**, `cg-mem` exactly at limit |
| both, equal | killed, **signal 11** (AS binds first) | killed at startup |
| `--cg-mem` limit + generous `-m` (1 G) | **runs fine** | killed, **signal 9** at exactly the limit |

**The decisive detail: signal 11 vs signal 9.** An address-space kill reports
SIGSEGV with `max-rss` of a few hundred KB — the process died having used almost
no memory, because the kernel refused the mapping, and *nothing in isolate's meta
indicates memory was the cause*. That is precisely why this repo has 555,119
`crash` verdicts and zero `memory_limit` ones. A cgroup kill reports SIGKILL with
`cg-mem` sitting exactly at the limit — unambiguous, and mappable to a proper `M`
verdict.

**Consequence for the policy debate:** "declaring `dp[5000][5000]` beyond the
limit should show MLE" is **not achievable through `-m`**. Address-space
enforcement can fail the program but can only ever report it as a crash. Wanting
both fail-on-declaration *and* an honest MLE verdict means `-m` cannot supply the
second half.

### Options

1. **Keep `-m` alone (status quo).** Your policy, but over-declaration keeps
   reading as "crash" and imported problems stay stricter than authored.
2. **Both flags, equal limits.** Byte-for-byte the same declaration behaviour as
   today, but a program that stays within address space and then over-uses gets a
   clean MLE. Strictly better reporting, zero loosening — the conservative fix.
3. **`--cg-mem` at the limit, `-m` generous (e.g. 4x).** Real memory overuse gets
   an accurate verdict; absurd declarations still fail fast; the common idiom
   (declare `MAXN`, use a submatrix) passes as it does on CMS/IOI/Codeforces.

Older framing kept below for reference:

1. **Keep cafe policy, fix the verdict.** Run with cgroups for accounting/reporting
   but keep an address-space cap too (`--cg-mem=<limit>` *and* `-m=<limit>`):
   students get a correct MLE verdict, and declaring beyond the limit still fails.
   Closest to today's behaviour while fixing Issue 2.
2. **Adopt CMS semantics** (`--cg-mem` only): full fidelity for imported problems,
   matches IOI convention. Strictly more permissive, so no existing grade can fall.
3. **Hybrid, per origin:** CMS semantics for imported problems, cafe semantics for
   native ones. Most faithful, but two grading models to explain and maintain —
   probably not worth it.
4. **Do nothing**, and raise imported problems' memory limits to compensate.

### Rollout requirement whichever is chosen

Use the existing Mode A replay harness (`problems:replay_validate`) to re-grade a
sample of **existing, non-imported** problems before/after and diff against stored
grades. Expect only `x -> P` transitions; **any `P -> x` means the page-cache
effect is real and stops the rollout.** Include tasks with large inputs. ~1 hour
of machine time; converts "should be safe" into "measured".

**Size:** the code change is one line (plus one more for the hybrid). The
decision and the verification are the work.

---

## Grounding materials — deferred follow-ups (from the 2026-07-19 design)

**Context.** Viva grounding was extracted off `Tag` into a dedicated
`GroundingMaterial` model with its own admin library (Manage → Grounding) and
a viva-only attach select on the problem form — see
`docs/superpowers/specs/2026-07-19-viva-grounding-materials-design.md` and
`doc/Viva-Exam.md` §3. Three items were explicitly deferred out of that work:

- **Unify `llm_prompt` into a shared `LlmAsset` model** (deferred alternative
  C from the spec). `llm_prompt` stays on `Tag` for now — small, always text,
  and working. Unifying it with `GroundingMaterial` into one LLM-asset model
  would let `Tag` become a pure label table, but rewrites the working
  rubric-injection path (`viva_turn_assist.rb`, `viva_grade_assist.rb`) for
  marginal benefit today; revisit if `llm_prompt` ever grows document-native
  needs (files, per-item token budgeting) the way grounding did.
- **Accurate page-count token estimate for grounding files.** `GroundingMaterial#compute_estimated_tokens`
  (`app/models/grounding_material.rb`) uses a byte-size proxy
  (`BYTES_PER_PROXY_TOKEN = 400`, i.e. ~1 token per 400 bytes) for attached
  PDF/image files — deliberately approximate, no PDF library in the codebase.
  A `pdf-reader`-based page count would give a tighter budgeting number.
- **Grounding image files (png/jpeg) are rejected at upload — PDF-only for v1.**
  `GroundingMaterial::ALLOWED_CONTENT_TYPES` was originally
  `image/png`/`image/jpeg`/`image/webp` plus `application/pdf`, but
  `Llm::Request.encode_pdf_part` (`app/services/llm/request.rb:124`) hard-guards
  `return nil unless attachment.content_type == 'application/pdf'`, so an
  uploaded image was accepted, token-counted, then silently never sent to the
  model — a validation/delivery mismatch fixed by narrowing
  `ALLOWED_CONTENT_TYPES` to `%w[application/pdf]`. Adding image support back
  requires extending BOTH `ALLOWED_CONTENT_TYPES` (validation) AND
  `encode_pdf_part` (or a sibling encoder emitting a plain
  `data:image/png;base64,...` `image_url` part, no PDF-specific framing)
  together — extending either alone reintroduces the same silent-drop bug.

---

## Help patterns — follow-ups under the context-dependent split

**Decision (2026-05-17).** Two patterns coexist intentionally: inline
knowledge card (`_xxx_help.html.haml`) on index/overview pages where space
is available and visibility matters for new admins; offcanvas drawer on
edit/detail pages where space is at a premium. Convention written into
CLAUDE.md under "Frontend & UI Conventions". Do NOT unify onto a single
pattern; that earlier plan was rejected.

**Discoverability.** Offcanvas trigger buttons must be labeled (`? Help`),
not icon-only. Codified in CLAUDE.md. First-visit popover pointing at the
button is a future enhancement using the existing cookie-based
`dismiss-announcement` controller pattern — deferred until we see whether
the visible label alone is enough.

**Open items under this split.**
- **Shared offcanvas helper.** ✅ DONE 2026-07-01 — `shared/_help_drawer.html.haml`,
  rendered as a layout (`render layout: 'shared/help_drawer', locals: {id:, title:, subtitle:}`);
  new drawers use it instead of hand-rolling the chrome.
- **Edit-drawer content density.** ✅ DONE 2026-07-19 — `problems/_edit_help` is a
  5-item Bootstrap accordion (data-API driven, survives Turbo-frame reloads).
  Optional follow-up: trim the prose if it still feels heavy once collapsed.

**Out of scope.** `app/views/main/help.html.haml` is a full-page
student-facing help with i18n — different concern, not covered by the
admin help-pattern split.

---

## Import/Export & CMS interop (from doc/problem-import-export-design-2026-07-14.md)

**Status 2026-08-02.** A *live-server* CMS import path shipped (master revs 1960–1968;
spec `docs/superpowers/specs/2026-08-02-cms-clone-import-design.md`):
`rails "cms:clone[task]"` ssh's to the CMS host, wraps the official `cmsDumpExporter`,
filters one task's subtree, fetches its blobs via `FileCacher`, and converts through
`Converters::CmsDumpConverter` into the trusted `ProblemImporter`. Validated against
c2 (`mar2025_eatingfish`): structure exact, and a replay of 8 real c2 submissions
scored 8/8 identical to CMS (only benign `T→P`/`x→P` per-testcase diffs). None of the
capability items below are closed by that work — Communication / OutputOnly / file-I/O
/ GroupMinPrereq are now *detected and rejected with a clear message* pointing here,
which is the interim behavior the 2026-07-14 design specified.

**Production transport that works today** (verified 2026-08-02, no new code needed):
clone on a box that has ssh to the CMS host → problem page **Download (all datasets)** →
upload that zip on the production server's existing **Problems → Import** page. Export→
import was round-tripped on the cloned problem: every field identical (both datasets,
42 testcases, weights, managers, statement, testcase bytes). This keeps production from
ever needing ssh/sudo access to the CMS host. Known cosmetic gap: the **live** dataset's
name is not preserved through a plain zip import (root `ds_name` is inert — the importer
auto-names the live dataset `Dataset N`; additional datasets keep their names). `cms:clone`
renames it explicitly; the web import path does not.

**Open, in the order that serves "import c2 → production, repeatably":**

- **UI-facing CMS *package* import (unbuilt).** The 2026-07-14 design's UI decision —
  "existing import page with format auto-detect" — is still unimplemented. Note the
  shape difference: `CmsDumpConverter` consumes a *dump bundle* produced by our own
  extractor, NOT a CMS-native package, so the upload path needs the originally-planned
  `CmsItalianConverter` (`task.yaml`) and/or `TpsConverter` (`problem.json`) plus
  sniffing in `problems_controller#do_import`. They slot into `app/engine/converters/`
  behind the same `convert(src, dest) → {log:, warnings:, errors:}` contract and can
  reuse the staging-layout knowledge (notably: a converter MUST emit `managers_dir` +
  `managers_pattern` or the importer silently skips `managers/*`). Needed when someone
  hands over a package file and there is no DB access; NOT needed for the c2→production
  flow above. Size: ~1 day per format + fixtures.
- **Mode B replay gate (CMS-source) before any bulk clone.** The 2026-08-02 validation
  was a hand-rolled script. Committing it as a CMS source mode in the existing
  `Replay::` harness (reuse `ReplayGrader`/`ReplayDiff`; new pieces are a CMS submission
  sampler and a CMS-outcome→cafe-verdict-char translator) turns per-task validation into
  one command. Matters because the 8-submission check only exercised white-diff +
  integer GroupMin + grader compilation; `Sum`, regex GroupMin params, and comparator
  (`custom_cms`) checkers have never been run against a real task. Size: ~half a day.
- Communication task support in the judge (manager process + FIFOs) — unblocks CMS Communication import/export.
- OutputOnly grading support — unblocks CMS OutputOnly import/export.
- GroupMinPrereq scoring in cafe's scorer (`score_param` to hold the prereq DAG) — unblocks importing dae's CMS camp tasks that use the custom score type.
- File-I/O task support (or a permanent-rejection decision) for Italian-format tasks with `infile`/`outfile`.
- Checker protocol adapter so `custom_cafe` checkers can be exported to CMS.
- C++ relative comparator (CMS-side equivalent of `lib/checker/relative.rb`).
- ✅ DONE 2026-07-19 — group-weight uniformity warning in the dataset UI
  (`Dataset#mixed_weight_groups`, shared with the import warning) and CMS-style
  codename-regex grouping in the Testcase config tool; the weight/group grammar
  and the CMS-divergence caveat are documented in `doc/dataset-scoring-and-evaluation.md`.
- Approach-C IR refactor of import/export — only if supported formats multiply beyond Italian+TPS.
- ✅ AUDITED 2026-07-19 — every single-string shell invocation on the grading path
  (`isolate_runner.rb`, `checker.rb:155`, `compiler/postgres.rb`, `judge_base.rb`,
  `grader.rb`). **Finding: no untrusted (student) input reaches any command
  string** — inputs are deployment config, engine-built ID paths, the
  admin-managed `languages` table, and problem-author files; authors already have
  arbitrary code execution by design (custom checkers run *unsandboxed* at
  `checker.rb:155`). Action taken: `judge_base.rb#run_initializer` → argv
  `system(*init_cmd)`. Optional hardening: `check_command` → argv, `${UID}` →
  `Process.uid` so `run_isolate` can drop the shell. **Separate larger item:**
  move custom checkers inside isolate if checkers are ever accepted from
  less-trusted authors.
- ✅ FIXED 2026-07-19 — `test/controllers/` and `test/integration/` must not declare
  the same class name (Ruby merges them and cross-contaminates `setup`); the
  integration file is now `report_controller_access_test.rb` /
  `ReportControllerAccessTest`. The rule stands for new test files.

---

## Viva `answer` action — concurrent at-cap POSTs can double-enqueue the grade job

**Context (noted 2026-07-21 during viva Phase 1 review).** `VivaSessionsController#answer`
(`app/controllers/viva_sessions_controller.rb`) hard-caps the interview: when
`@submission.viva_turns.where(role: :student).count >= @submission.problem.viva_hard_cap`
it writes a closing system turn, sets `status: :evaluating`, and enqueues
`Llm::VivaGradeAssistJob.perform_later(@submission)` — all without a row lock.
Two truly concurrent POSTs at the cap (double-click, two tabs, a retried
request) can both read the same pre-cap count and both take the force-finish
branch, enqueuing the grade job twice for one submission. This is a
pre-existing pattern across the whole controller (no action here takes a row
lock), not something specific to this branch.

**Impact.** Regrading is idempotent (the grader recomputes from the
transcript), so a double-enqueue costs an extra LLM grading call — noise/cost,
not a correctness or grade-manipulation bug.

**Fix direction.** Either `@submission.lock!` around the check-and-transition,
or a unique-job guard on `Llm::VivaGradeAssistJob` keyed by submission id.
Small; low priority given the impact is cost only.

---

## `datatables/configs.js` render functions interpolate unescaped HTML

**Context (noted 2026-07-21 during viva Phase 1 review).**
`app/javascript/controllers/datatables/configs.js` builds several DataTables
column `render` functions with raw template-literal interpolation of
server-supplied fields — `${data}` (lines 102, 184, 197) and
`${row.full_name}` (lines 108, 203) — dropped straight into HTML strings with
no escaping. `data`/`row.full_name` here are problem names / user full names,
which admins and group editors can set via ordinary edit forms.

**Impact.** These are all admin/editor-only management tables, so this isn't
a privilege-escalation vector (an admin who can already do arbitrary damage
would be attacking themselves or other admins). But it's a live class of bug:
a problem or user name containing HTML/script content would render
unescaped for the next admin who views that table, which is worth closing.

**Fix direction.** Add a small `escapeHtml` helper in the configs module and
wrap every user-controlled interpolation (`data`, `row.full_name`, and any
other free-text row field) with it. Bounded, mechanical change once the
helper exists — the main work is grepping the file for every interpolation
site so none are missed.

---

## `ai_gateway:` holds ONE gateway — no second bearer-key gateway side by side

`Llm::AiGatewayTransport.gateway_config` (`app/services/llm/ai_gateway_transport.rb`)
reads a single `Rails.configuration.llm[:ai_gateway]` block, so a deployment
runs exactly one bearer-key gateway. Running two concurrently — the Chula AI
Gateway *and* an OpenRouter-style aggregator held as a fallback for when a
model retires or the proxy wobbles — needs `ai_gateway:` generalized into a
keyed registry shaped like `self_hosted_models:`, plus a provider class per
entry so the admin pickers can tell the two rosters apart.

**Deliberately not built (2026-08-30), and this is the YAGNI half of the old
"OpenRouter LLM provider" entry.** Nobody runs two gateways today, and a
single-gateway deployment is fully served by the current block — *including* a
downstream site whose only gateway is OpenRouter, which is what that entry was
really about. The other half (provider-agnostic cost + a documented recipe)
shipped at rev 2050; see Resolved. Revisit only when a second concurrent
gateway is actually wanted.

**Size:** medium — config shape, initializer wiring, per-entry provider
classes, picker plumbing.

---

## Near-Miss: student-facing phase (deliberately deferred)

Interaction model (staged ladder vs one-click AI repair vs mode-split),
lifeline economy via the existing `comments.cost` machinery,
GraderConfiguration budget keys. Deferred until the batch data is digested —
the contest-scale evidence now exists; see `doc/Near-Miss-Grading.md`
(experimental record + the max(original, repaired) policy) and spec
section 13 (`docs/superpowers/specs/2026-07-30-near-miss-grading-design.md`).

---

## Near-Miss: `problems.statement_text` — designed 2026-07-31, deferred

Decision (dae): statements reach LLM prompts as **pdf-reader-extracted text**,
stored on the Problem as an **editable draft** (the `GroundingMaterial
#extraction_draft` pattern), because raw extraction drops Thai combining
marks and humans must be able to fix it once. Consumer: the ASSIST path
(unblocks `SelfHostAssist` in the picker) — NOT repair, which measured
better without statements. Integrity design (agreed after the
clobbering-vs-staleness discussion):

| Piece | Rule |
|---|---|
| `statement_text` (mediumtext) | machine draft or human-edited text |
| `statement_text_auto` (bool, default true) | true = safe to regenerate; any human form-save sets false |
| `statement_text_checksum` (string) | statement blob checksum the text was extracted from / edited against |
| Upload hook | re-extract ONLY if auto or blank — never clobber human edits |
| Problem form | textarea + staleness badge on checksum mismatch + explicit "Re-extract from PDF" button (resets auto) |

Plus: `pdf-reader` graduates into the Gemfile; blank extraction (scanned
PDFs) leaves the field blank and prompts omit the section; leave the column
out of the audited attrs (derived, bulky).

---

## CMS clone — deferred hardening batch (from 2026-08-02 final review)

- Nil CMS `time_limit`/`memory_limit` convert to `0` silently via `.to_f`/`.to_i`
  — add a reject-or-warn guard. `app/engine/converters/cms_dump_converter.rb:284-285`
  (`write_dataset_into`).
- Fractional `GroupMin` points truncate to an int weight with no warning —
  add a warn when `points` isn't a whole number.
  `app/engine/converters/cms_dump_converter.rb:172-202` (`build_group_plan`).
- `Errno::EPIPE` on the ssh stdin write surfaces as a raw backtrace instead
  of a clean `abort` — rescue it. `lib/tasks/cms.rake:36` (`stdin.write(File.read(script))`).
- Add `-o ConnectTimeout=10` to the ssh invocation so a dead/unreachable CMS
  host fails fast instead of hanging on the default TCP timeout.
  `lib/tasks/cms.rake:31` (the `ssh -o BatchMode=yes ...` cmd array).
- An empty ACTIVE dataset (0 testcases) imports with no warning — give it
  root parity with the additional-dataset warning path (non-active empty
  datasets already get a `skipped non-active dataset` warning via
  `dataset_reject_reasons`; the active one has no equivalent signal).
  `app/engine/converters/cms_dump_converter.rb:127-147` (`dataset_reject_reasons`),
  `:327` (the per-dataset testcase-count log line).
- `script/cms_extract/extract_task.py`'s module docstring documents exit
  codes `0 ok, 2 usage, 3 task not found` but not the traceback/exit-1 case
  for an unhandled exception (e.g. `cmsDumpExporter` failure) — the rake
  task already treats any nonzero exit as failure so behavior is correct,
  just undocumented. `script/cms_extract/extract_task.py:1-21` (docstring).

---

## Upstream GitHub Pages for docs/ + wiki visual-companion links

**Why it matters.** The user-facing authorization guide
(`docs/guide/authorization.html`) and the audit report are published only on
the fork's Pages site (`nattee.github.io/cafe-grader-web`) — the upstream wiki
can't link them canonically yet, and the fork wiki pointer references the
temporary URL.

**Current state.** The code alignment this entry originally tracked shipped at
rev 1996 (`User#can_submit_to_problem?` everywhere; disabled memberships grant
no role; resurrected model lock). Fork Pages serves master:/docs and works.

**What remains.** After the next /upstream-sync carries `docs/` to
cafe-grader-team: an org **admin** (dae's token is WRITE, not admin) must
enable GitHub Pages there (Settings → Pages → Deploy from a branch →
master + /docs), then (1) add the visual-companion link block to the wiki
page `Users-Roles-and-Access-Control` pointing at
`https://cafe-grader-team.github.io/cafe-grader-web/guide/authorization.html`,
(2) swap the temporary fork URLs in the fork-wiki pointer page.

**Size.** Trivial once the admin flips the Pages switch.

---

## Jobs stuck in `:process` forever when a grader dies mid-job (no reclaim)

**Why it matters.** `Job.take_oldest_waiting_job` flips a job to `:process` and
assigns the `grader_process`; nothing ever flips it back. If the grader dies
before `Job#report` — OOM, `kill -9`, a host reboot, the watchdog's
stalled-KILL branch (`Grader.plan_box` → `:kill`) — the job stays `:process`,
its parent chain never completes, and the submission sits in `evaluating`
forever (`app/models/job.rb`, `app/engine/grader.rb#main_loop`). Surfaced
2026-08-29 while hardening the watchdog; it is why duplicate graders get
TERM (graceful — `main_loop` finishes the current job) and never KILL.

**Direction.** A reclaim sweep: `Job.where(status: :process)` whose
`grader_process.last_heartbeat` is older than N minutes (or whose recorded pid
is gone) → back to `:wait`; compile / evaluate / score jobs are all
re-runnable. Natural home: `Grader.watchdog` (already per-minute, already
knows which graders are alive) or a Solid Queue recurring task next to
`viva_turn_failsafe`. Liveness should be pid-based, not only heartbeat-based:
`grader_processes.pid` exists but `Grader#initialize` never writes it
(`GraderProcess.register_grader` is legacy and unused). Size: small-medium,
plus a test that a `:process` job with a dead grader returns to `:wait` and is
picked up again.

---

## Problem stat page — per-group breakdown + deep link to the max-score report — MOSTLY RESOLVED 2026-08-28

**Shipped (rev 2029).** The stat page's "Score report" pill opens the Best Score
report with the problem *and* a section preselected (`Problem#report_group_for`:
live group with submissions > most-submitted incl. archived > newest live); the
shared report filter partials now honour `probs[…]` / `users[…]` URL params (the
dead prefill hooks fixed for all four reports).

**Still open — direction (2), only if switching groups in the report proves too
slow in practice:** a "By group" card on the stat page itself — one row per group
(users, attempted, solved, mean best score) from `Submission.regular.where(problem:)`
best-per-user joined to `groups_users` (honour `enabled`, drop editor/reporter
roles as the report does), scoped to `groups_for_action(:report)`, each row
deep-linking into the report via the shipped prefill. Size: medium.

---

## Resolved

Pointer blocks only — newest first. Full write-ups: `hg log`, CHANGELOG, linked docs.

### OpenRouter LLM provider — RESOLVED 2026-08-30 (generic path hardened, recipe documented)

**Rev 2050.** The entry asked for an OpenRouter provider; the generic one had
already landed (`Llm::AiGatewayTransport`, rev 2018), so what was actually
missing was (a) cost resolution that does not assume LiteLLM and (b) a recipe a
downstream operator can follow. Both shipped. **No OpenRouter-specific code
path exists, and none is wanted** — pointing the `ai_gateway:` block at it is
configuration.

- `compute_cost` resolves header → `usage.cost` in the response body → `0.0`
  **at WARN**. The silent zero was the real defect and was never
  OpenRouter-specific: cost tracking off on the proxy, a model missing from
  LiteLLM's price map, or an upgrade dropping the header each recorded $0.00
  into `Comment.cost_summary_for` and the near-miss lifeline budget with no
  signal at all. `execute_call` now keeps the raw header string, so a genuine
  `0` stays authoritative instead of falling through.
- New optional `ai_gateway.usage_in_body` sends `usage: {include: true}`, which
  is what makes a body-reporting gateway emit cost. Off by default: LiteLLM has
  no such key and would forward the unknown field upstream.
- **The trap worth remembering** (measured, not assumed): `execute_call` POSTs
  an *absolute* path and Faraday resolves it against `base_url` with URI-join
  semantics, so an absolute path REPLACES the prefix's path —
  `https://openrouter.ai/api` + `/v1/chat/completions` silently becomes
  `https://openrouter.ai/v1/chat/completions` (404). The documented recipe keeps
  `base_url` bare and puts the whole `/api/v1/...` in `completion_path`. LiteLLM
  proxies mount at the root and are unaffected.
- Worked OpenRouter block in `config/llm.yml`, explicitly labelled UNVERIFIED on
  the two points that need a live account: the exact `usage.cost` opt-in, and
  whether OpenRouter accepts the OpenAI `file` content part that
  `convert_pdf_parts` emits for PDFs (built and tested against LiteLLM; only
  viva grounding and statement PDFs depend on it).

Tests: `test/services/llm/ai_gateway_transport_test.rb` — header wins over body,
a genuine header `0` is authoritative and does not warn, body fallback for
string *and* symbol keys, the loud zero, and `usage_in_body` off / on /
caller-supplied. **Residual:** the multi-gateway registry, now its own open
entry above.

### `custom_cms` checker argv order on LIVE problems — RESOLVED 2026-08-29 (no mis-grading)

**Verified on production (10.0.5.50), rev 2046.** All 10 problems on the legacy
argv order — `custom_cms` 570 `d68_q3a_jobqueue`, 606 `a68_q1a_horse`, 656
`a68_q4z_guitar_array3`, 659 `a68_q4a_normal_puzzle`, and `custom_cms_raw`
649–654 `rubiks_race_1..6` (one shared binary) — expect cafe's
`(input, USER, correct)` order, so `Checker#check_command` invokes them
correctly and no submission was mis-graded. Method: pulled each checker and its
real testcase blobs, ran them locally with crafted content in slot 2 vs slot 3
(empty / garbage / the reference / a valid solution); in every checker the
verdict tracks slot 2 only and slot 3 is ignored even when it holds garbage
(656 is a Python script reading `argv[2]` as the student grid; 659 accepted a
valid `1L 2L` solution in slot 2 with `1.0` and rejected it in slot 3 — its
`main` constructs an `ifstream` on `argv[3]` and never reads it). Cross-check
from production data: students hold full-score `PPPP…` runs on all ten although
the stored reference answers are placeholders (570 a fixed token; 659 and
650–654 a byte-copy of the input) that a CMS-order checker would have graded
*as the student's output* and failed universally. **The `strings` proxy in the
original entry is wrong** — all five print `translate:*` (CMS *result*
protocol, exactly as `doc/Checker-and-Auxiliary-Files.md` teaches) yet take
testlib argv order; output vocabulary says nothing about argv order. Durable
record: `doc/decisions.md` 2026-08-29; loud naming-trap warnings now sit in
`doc/Checker-and-Auxiliary-Files.md` (plus a `cms_comparator` section that was
missing), `doc/dataset-scoring-and-evaluation.md`, `doc/CMS-Migration.md` §5.3.
**Residual — DONE rev 2047 (2026-08-30):** (a) renamed `custom_cms` →
`custom_testlib`, `custom_cms_raw` → `custom_testlib_raw` (integers unchanged;
`Dataset::LEGACY_EVALUATION_TYPES` aliases the old names on assignment); (b)
`cms_comparator` exposed in the dataset dropdown as **[CMS-NATIVE]**. Fleet census
(8 servers) in `doc/decisions.md` 2026-08-29 update; TOI-box `may2025_abcd` was
the one true CMS-order checker → `cms_comparator` + rejudge.

### Grader.watchdog duplicate-spawn → isolate box collisions (`!` results) — RESOLVED 2026-08-29

**Rev 2045 + automation rev 58.** Incident 2026-08-27 on the ISE grader
(10.0.5.70): two orphaned whenever crontab blocks (identified by the
schedule.rb path; the app dir had been renamed) ran two watchdogs per minute,
both spawned per box, and `lines.count >= 1` read the pair as healthy —
isolate "This box is currently in use" → `!` on ~130 submissions that day
(bursts Jun 23–29 and Jul 17 too); hosts deduped by hand the same day.
Code: `Grader.watchdog` takes a host-wide non-blocking flock
(`Dir.tmpdir/cafe-grader-watchdog-<worker_id>.lock`), parses
`ps -o pid,ppid,etimes,args` via `Grader.grader_processes` (every grader is
an `sh -c` → Ruby chain; the wrapper is collapsed and the Ruby leaf signalled),
and `Grader.plan_box` TERMs every duplicate but the oldest — TERM, never
KILL, see the stuck-jobs entry — and stops *all* processes of a disabled box
(was: first pid only); duplicate kills go to `Rails.logger.warn`. Rerun
idempotency: `JudgeBase#prepare_testcase_directory` `rm_f`s the previous
`stdout.txt` (a run that died with its box left it 0644/other-uid; a rerun on
another box could not truncate it — 14 of 142 rejudges on 08-27). Deploy: CI
runs `whenever --clear-crontab` (drops the legacy path-identified block,
no-op after) then `whenever --update-crontab cafe-grader`. Tests
`test/engine/grader_watchdog_test.rb`. Not done: retry on isolate `XX`
(cause removed); the TOI box (10.24.0.100) crontab is still unchecked.

### Viva grading: harden against transcript-continuation failures — RESOLVED 2026-08-29

**Revs 2024 + 2043.** (a) Prompt hardening, rev 2024: `INTERVIEWER:`/`STUDENT:`
transcript labels + trailing `=== END OF TRANSCRIPT ===` re-anchor (Claude
compliance 3/24 → 16/16, Gemini unaffected). (b) Silent nil-score grades, rev
2043: the hole was `extract_json_object` returning the first balanced `{…}` and
the write path trusting it — not "no JSON", which has raised since rev 1667.
`grade_schema_error` (numeric `total_points` 0..100, non-empty `rubric`) and
unparseable brace blocks now raise `ResponseError`; `VivaGradeAssist#respond`
(new `Llm::Request#respond` template) re-asks once — not on
`finish_reason=length` — then the existing `grader_error` path (red admin alert,
`llm_response_raw` = last body, first bad reply at WARN, Re-run picker); both
attempts' cost on the grade row. Tests `test/services/llm/viva_grade_assist_test.rb`.
(c) Interview/narrative language is a **conduct-tag** concern, not code: DS kit
`_conduct.md` §Language (examiner English-only, students Thai/English/mixed,
translation → simpler English, narrative in the student's language), deployed
as prod `viva_conduct` tag 38 and verified identical 2026-08-29; convention
recorded in `doc/Viva-Exam.md` §2.
Grader model history: gemini-2.5-flash → 3.1-pro (chula_cp rev 2008; 12-session
comparison on 10.0.5.50 `~/viva_compare_results.jsonl`) → 3.7-flash via the Chula
AI Gateway (2026-08-27 bake-off, `~/cafe-grader/bakeoff-2026-08-27/report.html`);
rev 2011 made both end paths use the grade service's default.
**Residual (policy, ~$1):** re-test `claude-opus-4-5` as grader with the hardened
prompt on all 12 sessions — strictest and most consistent (spread ≤4) in the
4-session probe; strict-vs-generous on uncovered rubric items is the instructor's
call before any exam-graded viva.

### API ↔ web parity: IP whitelist not enforced on `/api/v1` — RESOLVED 2026-08-28

**Rev 2026.** Full web parity: one predicate `User#allowed_from_ip?` backs the web
gate, a per-request 403 in `Api::V1::BaseController#authenticate_api_user!`, and
token-issuance refusal in `auth/login`; CIDR matching lives in
`GraderConfiguration.whitelisted_ip?`. Tests: `authorization_sweep_spec.rb`
(whitelist sweep over every `/api/v1` route), `authorization_spec.rb`,
`test/models/grader_configuration_test.rb`. CHANGELOG 4.5.0.

### Viva grade display — narrative doesn't belong in `grader_comment` / main list — RESOLVED 2026-08-28

**Rev 2036 (4.5.0 head).** Success path writes `Submission#viva_result_marker`
(`viva` / `viva:terminated`, from `viva_terminated_at`) to `grader_comment`; the
narrative lives on `viva_grades.narrative` only. `_submission_short` shows a
badge-as-link for viva rows plus "Interview in progress" / "Grading in
progress…" / red "Grader error" states. One-off cleanup
`bin/rails viva:clean_grader_comments [APPLY=1]` (`Viva::GraderCommentCleaner`,
report-first). Record: CHANGELOG 4.5.0, `doc/Viva-Exam.md`.

### Viva/tag markdown fields are bare textareas — add highlighting + preview — RESOLVED 2026-08-28

**Rev 2030.** `markdown_editor_controller.js` (Ace `mode-markdown`, `github`
theme, soft wrap) wraps all four textareas via
`ApplicationHelper#markdown_editor_data`, with an Edit / Preview toggle →
`POST /markdown/preview` (`safe_markdown`, editors only); `grounding-draft`
dispatches `change` so "Copy draft into Body" still works. Not done by design:
side-by-side preview, client-side renderer.

### Viva problem edit page — right column is empty, left column crammed — RESOLVED 2026-08-28

**Rev 2031.** One form over both columns: Detail card left, Viva Exam card right
(Scenario + briefing full width, then interview setup). Hint and Description tabs
dropped for viva problems; `form=` rejected because Rails does not propagate it
to a multiple select's hidden input. Type switches redraw `#problem-edit` on
save; a dataset-less problem gets an "Add dataset" empty state.

### Reporter role: let it report on finished (unavailable / archived) courses — RESOLVED 2026-07-01

**Option 3b.** Editors are group-scoped content curators:
`Problem.group_editable_by_user` dropped the `available` / `groups.enabled`
filters, `group_reportable_by_user` = editor-set ∪ reporter-gated-set, and
`Group.reportable_by_user` is role-aware — an editor sees/edits/reports on
archived courses and draft problems in their groups; reporters stay scoped to
live content. **Operational rule:** to give a non-admin access to a finished
course, make them an *editor* of its group. Option B (scores-only split) not
taken. Tests `test/models/problem_scope_authorization_test.rb`; the role model is
documented in `doc/Users-Roles-and-Access-Control.md` / the upstream wiki page
and superseded in detail by `doc/decisions.md` 2026-08-22.

### Publish "Users, Roles & Access Control" wiki page — RESOLVED 2026-07-01

Live at https://github.com/cafe-grader-team/cafe-grader-web/wiki/Users-Roles-and-Access-Control
(wiki commit `54b2c8d`). Source draft: `doc/Users-Roles-and-Access-Control.md` —
edit here, then re-push to the separate wiki repo
(`git@github.com:cafe-grader-team/cafe-grader-web.wiki.git`). Wiki `Home.md` is
intentionally minimal (GitHub's auto sidebar lists pages).

### AuditLog destroy test — RESOLVED 2026-06-20

`test/models/auditable_test.rb` (4 tests): own-row destroy writes a `destroy`
row, the `dependent: :destroy` cascade writes rows for `ContestProblem` /
`ContestUser`, the snapshot stores `[value, nil]`, `AuditLog.paused` suppresses.
Confirms `after_destroy_commit` fires under transactional tests.

### CSRF meta null-safety in DataTable inits — RESOLVED 2026-06-20

`?.` on every `meta[name="csrf-token"]` lookup — 5 view sites plus 4 in the
shared `datatables/configs.js`; a grep for the unguarded form returns nothing.
Rule codified in CLAUDE.md "Testing Notes" (the unguarded form throws when
forgery protection is off and silently kills the whole DataTable).

### System-test suite — RESOLVED 2026-06-15

`bin/rails test:system` 46/46 green (was 20 failing on 2026-05-21). Six root-cause
clusters, none of them production regressions: the no-spaces `name` rule is
intentional (`NameFormatValidator`, human text goes in `description`) — tests
fixed, not the rule; `select2_select` helper scoped to the open widget with
`exact_text`; async turbo_stream submits raced the DB read — wait for `.toast`;
submissions "Go" button replaced by the select2 chooser; users-page drift
(unguarded CSRF meta, redirect target, grant-admin select2, `f.button :submit`).
Two tests skipped on hunches were both wrong diagnoses and are un-skipped. All
lessons live in CLAUDE.md "Testing Notes". Leftover UI question: the user-edit
page's second submit button outside the form via `form=`.
