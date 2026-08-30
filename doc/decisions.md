# Engineering Decisions

Major, hard-to-reverse decisions and their reasoning. Newest first.
(Deferred work goes in `backlog.md`; this file is for decisions already made.)

## 2026-08-29 — `custom_cms` argv order is testlib's by design; verified safe on production

**Decision.** The `custom_cms` / `custom_cms_raw` evaluation types keep their
argv order `(input, USER output, correct answer)` — the testlib/Codeforces
convention — and the CMS-native order `(input, correct, USER)` stays a separate
type, `cms_comparator` (enum 7, added 2026-08-02 for `cms:clone`). No live
problem is switched. The name `custom_cms` is a known trap — it describes the
*result protocol* (score on stdout, `translate:*` on stderr), not the argv
order — and is now documented as such at every point of use; a rename to
`custom_testlib` is left open in `doc/backlog.md` (Resolved ledger, residual).

**Why.** The 2026-08-02 CMS-migration work found the order mismatch and
suspected the pre-existing `custom_cms` problems might be mis-graded.
Verified against production on 2026-08-29 (dae@10.0.5.50): all 10 problems on
the legacy order — `custom_cms` 570/606/656/659 and `custom_cms_raw` 649–654
(Rubik's Race, one shared binary) — were written to cafe's documented order.
Evidence, per distinct checker (5): run locally on the real testcase blobs with
crafted content in slot 2 vs slot 3, every checker's verdict tracks slot 2 only
and ignores slot 3 even when it holds garbage (659 accepted a valid `1L 2L`
solution in slot 2 with `1.0` and rejected it in slot 3; 656's Python source
reads `argv[2]` as the student grid; 659's `main` never reads the `argv[3]`
ifstream it constructs). Corroboration from production data: students hold
full-score `PPPP…` runs on all ten, although the stored reference answers are
placeholders (570 a fixed token, 659 and 650–654 a byte-copy of the input) that
a CMS-order checker would have graded *as the student's output* and failed
universally.

**Lesson recorded.** "Prints `translate:*`" does **not** mean "expects CMS argv
order" — cafe's own checker guide teaches the CMS result protocol with testlib
argv order, so every cafe-authored checker looks CMS-style to a `strings` grep.
Classify a checker by running it with asymmetric slot contents, never by its
output vocabulary.

**Guard rails.** Warning blocks in `doc/Checker-and-Auxiliary-Files.md`
(`custom_cms` section, plus a `cms_comparator` section that was missing),
`doc/dataset-scoring-and-evaluation.md`, and the `app/models/dataset.rb` /
`app/engine/checker.rb` comments; `Converters::CmsDumpConverter` maps CMS
`comparator` → `cms_comparator`, never `custom_cms`.

**Update 2026-08-30 (rev 2047) — renamed.** `custom_cms` → `custom_testlib`,
`custom_cms_raw` → `custom_testlib_raw`; enum integers 4/6 unchanged, so no
server needs a migration. `Dataset::LEGACY_EVALUATION_TYPES` normalizes the old
names on assignment (form, API, import packages) indefinitely; exports now
write the new names, so upgrade a fleet before moving packages from a new box
to an old one. `cms_comparator` became selectable in the dataset form
(**[CMS-NATIVE]**; rev 2048 made every dropdown label show its enum key, since the pre-1738 dropdown showed raw keys and that is the name authors know). Fleet census the same day (all 8 web servers): 25 `custom_cms` + 7
`custom_cms_raw` datasets, none `cms_comparator`; every checker on grader-2023,
comprog and compas is testlib-order. On the TOI box (16 CMS-package tasks) one
checker — `may2025_abcd` — is genuinely CMS-order (its verdict follows argv[3];
five different students scored an identical 54.0112 = the reference file's own
score) and is switched to `cms_comparator` + rejudged; the wiki
(`Checker-and-Auxiliary-Files`) carries the rename notice.

## 2026-08-22 — Submit authorization: one gate, web behavior is authoritative

**Decision.** Whether a user may create a submission is decided by exactly one
predicate, `User#can_submit_to_problem?` = admin, OR the problem is in the
user's `:submit` set (member on a fully-live problem: `available` ∧
`group.enabled` ∧ `groups_problems.enabled` ∧ `groups_users.enabled`), OR in
their `:edit` set (a group's **editor may test-submit draft/hidden problems in
their own groups**). Every layer consults it: `main#submit`, the API create,
viva start (**viva authorization matches normal problems**), the submit-form
UI (`@can_submit` — a reporter who can *view* a student-hidden problem gets a
view-only page, never a Submit button that fails at POST), and the model-layer
validation `Submission#must_have_valid_problem` as the last line of defense.
Trusted server-side tooling (repair shadows, replay engines, model-solution
import) bypasses explicitly with `save!(validate: false)`. Shipped rev 1996.

The intended role model, in @nattee's words: admin is site-wide everything;
editor is "almost admin-like" for any problem in the groups they edit; member
sees/submits only when everything is on; reporter is just a member that can
additionally *see* problems whose in-group switch is off. **A disabled
membership row (`groups_users.enabled = false`) grants no role at all** — not
member, not reporter, not editor.

**Why (decided by @nattee):**

1. **The running web app is the spec.** The design was realized on the web
   first and documented later; when an audit found docs/API contradicting the
   web (the API 403'd editor test-submits the web allowed), the ruling was
   "the doc should match the web," not the reverse.
2. **One predicate, because drift is how the bugs happened.** The 2026-08-22
   audit (`docs/reports/submit-authorization.html`) found three layers each
   hand-rolling the rule: the web checked `:submit ∪ :edit`, the API `:submit`
   only, and the model check had been a silent no-op since the Rails 6.1 era
   (`errors[:base] <<` registers nothing; binary submissions skipped it
   entirely). Independent copies of an authorization rule *will* disagree.
3. **Disabled ≠ removed, but disabled = no powers.** Editor/reporter problem
   scopes previously ignored `groups_users.enabled`, so a disabled editor
   kept view/edit/test-submit. Disabling a membership is the UI's revocation
   gesture; it must revoke everything while preserving the row.

**Guard rails.** `test/models/submission_authorization_lock_test.rb` (the
model lock blocks unauthorized direct saves), `test/integration/submission_view_only_test.rb`
(form vs view-only notice). The measurement harness that found all of this —
an actor × problem-variant × entry-point matrix driver — is kept untracked as
`test/integration/authz_submit_probe_test.rb` for the future contest-mode pass.
User-facing docs: wiki "Users, Roles & Access Control" + the visual guide at
`docs/guide/authorization.html`.

## 2026-07-30 — LLM provider placement: generality decides the branch, config activates

**Decision.** Where an LLM provider's *code* lives is governed by one test:
*could a third-party deployment of upstream cafe-grader plausibly use this
provider with their own hardware or account?* Yes → classes live on **master**,
dormant until configuration activates them. No → classes live on **chula_cp**.
Configuration — `*_service` keys and endpoint registries in `config/llm.yml`,
secrets in Rails credentials — is always per-deployment and never a reason to
move code between branches.

Placement under this rule: abstract bases + registration hooks (per-model
provider map, `viva_turn_service`-style keys) — master, as today.
`Llm::SelfHostChat` / `Llm::SelfHostAssist` / `Llm::SubmissionRepairSelfHostAssist`
(generic OpenAI-compatible endpoints; any self-hosted vLLM/llama.cpp/TGI works)
— master. Future hosted-aggregator providers (e.g. OpenRouter) — master, API
keys in Rails credentials. ChulaGenie concrete classes (`Llm::GenieAssist`,
`Llm::TokenManager`, the viva/grounding Genie subclasses) — chula_cp, because
the Genie gateway is unreachable outside the university.

**Why.** The original working rule ("master carries only abstract LLM classes;
concrete implementations live on chula_cp") was an artifact of the first
provider being ChulaGenie, which genuinely cannot work off-campus. Read as a
general rule it would wrongly exile generic providers: a university running its
own vLLM box should deploy straight from master/upstream without ever learning
that chula_cp exists. Master is also the upstream-facing line (pushed to
cafe-grader-team), so generic providers there are a feature of the public
project, while Chula-only integrations would be dead code and internal detail.

## 2026-07-20 — Viva prompt storage: ownership follows cardinality (no unified "LLM asset" entity)

**Decision.** Content attached to problems is stored by its *natural cardinality*,
not by a shared mechanism. Per-problem content lives in columns on `problems`
(`viva_prompt` — the secret examiner briefing with rubric/model answers, audited
with redaction; `description` — the viva scenario). Cross-problem content lives
in shared entities: `GroundingMaterial` (files + token accounting + extraction
behavior) and `Tag` (labels, plus two staff-only text kinds). The 2026-07-19
rejection of a unified "LLM asset" model is reaffirmed: the candidates share
almost no *behavior*, and one table wearing three concepts serves authors worse
than three named concepts. What IS worth unifying is the UI grammar (library
page + select2 attach + token badge + used-by count), not the schema.

**Tag taxonomy (final).** `normal`/`topic` — labels, `public` at author's
choice; `llm_prompt` — AI-helper ("Codey") prompt, read ONLY by
`Llm::CommentAssist`; `viva_conduct` — shared examiner persona, read ONLY by
viva assembly, `order(:name)`. Both LLM kinds force `public = false`
(model-level coercion). Viva's system prompt assembles in fixed order:
conduct tags → `viva_prompt` → platform `SECURITY_DIRECTIVE` → protocol
directives. The `# Rubric` requirement validates against the column
(`Problem#viva_setup_errors`), where a per-problem contract belongs — a shared
instance can't carry per-problem guarantees.

**Deviation from the 2026-07-20 spec text (deliberate).** The spec said the
generic tag picker "stops offering LLM-kind tags." Implemented as written this
silently stripped `llm_prompt` tags on every ordinary problem save (`tag_ids=`
is whole-collection replacement, and the picker was the only attach UI for
helper tags). The picker therefore excludes only `viva_conduct` (which has its
dedicated Conduct-profile select); `llm_prompt` remains offered. The spec's
intent — no cross-feature prompt contamination — is enforced at the *consumer*
layer instead: each feature reads only its own kind, so misattachment is
structurally harmless.

## 2026-06-10 — Canonical MySQL collation: `utf8mb4_0900_ai_ci` (MySQL-only; MariaDB unsupported)

**Decision.** Every table and string column in the primary database uses
`utf8mb4_0900_ai_ci`. The database default is pinned to it (migration
`20260610120000_unify_collations_to_utf8mb4_0900`), connections request it
(`collation:` in `database.yml`), and `test/schema_collation_test.rb` fails
the suite the moment any table or column drifts.

**Consequence — supported database servers.**
**This repo REQUIRES MySQL 8.0+ — Oracle MySQL or Percona Server. MariaDB is
NOT supported and WILL NOT work.** MariaDB has no `utf8mb4_0900_*` collations,
so loading the schema (or any dump of it) fails immediately. Percona Server is
a drop-in MySQL fork and supports the 0900 family fully, so Percona remains an
option. This was already de-facto true before the decision (28 of 45 tables
were on 0900), but it is now intentional, documented, and enforced.

**Why (decided by @nattee):**

1. **No MariaDB in deployment planning; Percona remains possible.** We control
   the deployment on MySQL 8. Keeping a MariaDB exit open would have meant
   standardizing on `utf8mb4_unicode_ci` instead — converting the largest,
   hottest tables (including `submissions`, which carries every source file
   and binary upload) and fighting MySQL's default collation forever.
2. **Faster.** The 0900 family is MySQL 8's rewritten collation
   implementation and benchmarks significantly faster for comparisons and
   sorts than `utf8mb4_unicode_ci`.
3. **Better Thai (and general Unicode) handling.** `utf8mb4_unicode_ci`
   implements UCA 4.0.0 (2004); `utf8mb4_0900_ai_ci` implements UCA 9.0.0 —
   twelve years of added characters and collation fixes, including improved
   Thai handling. (For strict Thai dictionary *ordering*, the same family
   offers `utf8mb4_th_0900_ai_ci` per column/query if a report ever needs it.)
4. **It is the MySQL 8 default.** Tables created without an explicit
   `COLLATE` — future migrations, `solid_queue`/`solid_cache` schemas,
   dump-restores onto fresh servers, ad-hoc DBA tables — are born conforming.
   Standardizing on anything else regenerates drift forever.

**History this resolves.** Charset/collation mismatches were fixed at least
three times before (2025-07 `alter_utf8_for_comments`, 2026-03
`convert_utf8mb3_tables_to_utf8mb4`, 2026-04 rev 1586 which pinned the DB
default after new tables kept reverting to utf8mb3). Each round converted the
tables failing *that day* to `utf8mb4_unicode_ci`, while MySQL 8 kept minting
new tables as `0900_ai_ci`. The two populations (17 vs 28 tables) collided in
`ReportController#cheat_report` (`logins.ip_address` joined against
`submissions.ip_address` → "Illegal mix of collations"). The durable fix is a
single canonical collation **plus an enforced invariant** (the guard test) —
not another one-off conversion.

**Behavior notes.** `ai_ci` = accent- and case-insensitive, same class as
before. The 0900 family is NO PAD (trailing spaces are significant in
comparisons) unlike unicode_ci's PAD SPACE; this is the SQL-standard behavior
and nothing in the app relies on the old padding semantics.
