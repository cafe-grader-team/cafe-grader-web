# Dataset scoring & evaluation — reference

Verified semantics for `Dataset#score_type` and `Dataset#evaluation_type`,
pulled from the engine code. Update this file when the engine changes;
the help card (`app/views/problems/_edit_help.html.haml`) and the
dropdown labels in `app/views/datasets/_settings.html.haml` both lift
their text from here.

Sources: `app/engine/scorer.rb`, `app/engine/checker.rb`,
`lib/checker/relative.rb`, `lib/checker/postgres_checker.rb`.

## Score Type — how testcase scores aggregate into the final grade

| Key | Formula | Use when |
|---|---|---|
| `sum` | `Σ (testcase_score × weight) / Σ weights × 100` | Default. Weighted sum of testcase scores, normalized to 100. |
| `group_min` | Per group, take the *minimum* score in that group × the group's weight (the *minimum* weight found in the group — by convention all testcases in a group share one weight); then `Σ / total weight × 100`. | **IOI/ICPC subtask style.** A group only earns points if *every* testcase in it passes — one failure drags the whole group to its minimum. The importer warns when a package declares mixed weights inside a group. |
| `raw_sum` | `Σ testcase_score`. No weighting, no normalization. | When a custom checker emits per-testcase point values you want summed literally. **Pair with `custom_testlib_raw` evaluation_type.** |

Source: `scorer.rb:14-74` (`sum_of_all_testcases`, `group_min`, `raw_sum`).

## Testcase config — the weight & group tool

The **Testcase config** box on the dataset's Testcases tab (`weight_param` →
`DatasetsController#set_weight` → `Dataset#set_by_array` / `set_by_hash`)
assigns per-testcase `weight` (and, in CMS mode, `group`) in bulk. Input is
**JSON**, in one of these forms:

| Input | Effect |
|---|---|
| `[10, 20, 30]` | Flat: weight 10 → 1st testcase, 20 → 2nd, 30 → 3rd (positional, in display order). No grouping. |
| `[[10, 2], [20, 3]]` | **CMS mode** (triggered when the *first* element is an array). `[weight, count]`: group 1 = the next **2** testcases at weight 10; group 2 = the next **3** at weight 20. Writes both `weight` **and** an incrementing `group`. |
| `[[40, "1-.*"], [60, "2-.*"]]` | **CMS mode with a codename regexp.** `[weight, "regex"]`: group 1 = every testcase whose `code_name` matches `1-.*`, group 2 = those matching `2-.*`. The regexp is **anchored at the start** (like CMS's `re.match`), so `1-.*` matches `1-1`/`1-2` but **not** `10-1`. You can mix `[w, count]` and `[w, "regex"]` entries in one array, but don't overlap them. |
| `{"weight":[…], "group":[…], "group_name":[…]}` | Hash form: set each field independently by run-length array (`[value, count]` pairs allowed). **No** auto-grouping; counts only, no regexp. |

> ### ⚠ This looks like CMS but is **not** the same
> The `[[value, count]]` shape is deliberately CMS-compatible — you can paste a
> CMS `GroupMin` `score_type_parameters` list and it will often work — but the
> semantics diverge:
>
> - **The first number is a *weight*, not points.** cafe **normalizes**:
>   `Σ(min_score · weight) / Σ weight × 100`. CMS's number is *absolute
>   points*. They match only when the CMS values already sum to 100; otherwise
>   cafe rescales (e.g. CMS `[[30,5],[30,8]]` for a 60-point task stays 60 in
>   CMS but becomes 100 here).
> - **`T` (the second field) is a count *or* a codename regexp** — same as CMS.
>   The regexp matches `code_name`, start-anchored, mirroring CMS `re.match`.
> - **cafe stores the value per testcase**, CMS stores it once per subtask.
>   That's why cafe can drift into "mixed weights inside a group" (the editor
>   and importer both warn — see `group_min` above); CMS can't by construction.
>
> There is **no CMS package import/export** today (Italian/TPS ⇄ cafe is
> designed in `doc/problem-import-export-design-2026-07-14.md` Package 2 but not
> built). What is CMS-compatible at *runtime* is the checker protocol
> (`custom_testlib` / `custom_testlib_raw` below).

Source: `Dataset#set_by_array` / `set_by_hash`, `DatasetsController#set_weight`.

## Evaluation Type — how submission output is judged against the expected answer

| Key | Behavior | Notes |
|---|---|---|
| `default` | `diff -b -B -Z` | Ignores whitespace differences within lines, blank lines, and trailing whitespace. The right default for most problems. |
| `exact` | `diff -q` | Byte-for-byte after the standard `diff` line algorithm. No whitespace tolerance. |
| `relative` | `lib/checker/relative.rb` | Tokenizes on whitespace. Numeric tokens are compared with `EPSILON = 1e-6`; non-numeric tokens must match exactly. Use for floating-point output. |
| `postgres` | `lib/checker/postgres_checker.rb` | Strips `CREATE VIEW` / `DROP VIEW` lines, then compares as CMS-style with score on stdout. Used by the DB course. |
| `custom_cafe` | Runs the dataset's `checker` file. | Receives args: `<language> <testcase_num> <input> <output> <answer> 10`. Output is two lines: line 1 = `CORRECT` / `INCORRECT` / `COMMENT: <text>`; line 2 = score (integer or decimal). **The score is divided by 10** (`checker.rb:51`: `arr[1].to_d / 10`) — so a checker outputting `100` yields a score of `10`. Non-obvious legacy quirk. |
| `custom_testlib` | Runs the dataset's `checker` file as `checker <input> <user_output> <correct_answer>`. | CMS / Codeforces convention: exit 0, score on stdout, comment on stderr. The CMS framework's `translate:success` and `translate:wrong` markers on stderr are stripped automatically (`checker.rb:34`). **Argv order note:** this is the testlib/Codeforces convention (2nd arg = the submission's output, 3rd = the correct answer). It does **not** match what CMS itself invokes; see `cms_comparator` below. Named `custom_cms` until rev 2047 (likewise `custom_cms_raw` → `custom_testlib_raw`): the old names are still accepted on assignment via `Dataset::LEGACY_EVALUATION_TYPES`, so older export packages and API clients keep working, and reads return the new names. Verified on production 2026-08-29: all ten live problems on this order (four `custom_testlib`, six `custom_testlib_raw`) were written to it and grade correctly — `doc/decisions.md` 2026-08-29. |
| `custom_testlib_raw` | Runs the dataset's `checker` file. | Stdout is a raw decimal score. **Designed to pair with `raw_sum` score_type** so the per-testcase numbers add up directly without renormalization. Same legacy `(input, user, correct)` argv order as `custom_testlib`. |
| `cms_comparator` | Runs the dataset's `checker` file as `checker <input> <correct_answer> <user_output>` — CMS's own argv order. | Same result protocol as `custom_testlib`: exit 0, score on stdout, comment on stderr (`process_result_cms`). Exists **specifically** because CMS invokes its comparator as `["./checker", input, correct_output, user_output]` (CMS 1.4.dev3, `cms/grading/steps/trusted.py:237-240`) — arguments 2 and 3 are swapped relative to `custom_testlib`. A checker binary imported unmodified from a CMS task package expects THIS order; feeding it `custom_testlib`'s order silently hands it the wrong file in the "correct answer" slot (e.g. an empty file, for checker-only tasks with zero-byte reference outputs) and every submission scores wrong. `Converters::CmsDumpConverter` maps CMS's `comparator` evaluation mode to `cms_comparator`, never to `custom_testlib`. |

There is also a `'no_check'` branch in `checker.rb` (`check_command` returns
`""`, `process_result` returns a partial score of 0). It is **not in the
enum** (`Dataset#evaluation_type` values: 0=default, 1=exact, 2=relative,
3=custom_cafe, 4=custom_testlib, 5=postgres, 6=custom_testlib_raw, 7=cms_comparator),
so it's unreachable from the UI today. If you want a "skip judging" mode for
data-collection problems, surface it via the enum first.

## Compatibility cross-rules (not enforced; documented here)

- `raw_sum` + `custom_testlib_raw` is the intended pairing. Other combinations
  with `raw_sum` will produce strange totals because the score for
  non-custom evaluators is just 0 or 100 per testcase.
- `custom_*` evaluators, plus `cms_comparator`, all require a `checker` file
  attached to the dataset (`checker.rb` `check_for_required_file` checks
  this at run time and raises `GraderError` if missing).
- `custom_cafe`'s `/10` normalization means it natively lives on a 0-10
  scale. Convert your checker's intended scale accordingly.
