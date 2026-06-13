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
| `group_min` | Per group, take the *minimum* score in that group × its max weight; then `Σ / total weight × 100`. | **IOI/ICPC subtask style.** A group only earns points if *every* testcase in it passes — one failure drags the whole group to its minimum. |
| `raw_sum` | `Σ testcase_score`. No weighting, no normalization. | When a custom checker emits per-testcase point values you want summed literally. **Pair with `custom_cms_raw` evaluation_type.** |

Source: `scorer.rb:14-74` (`sum_of_all_testcases`, `group_min`, `raw_sum`).

## Evaluation Type — how submission output is judged against the expected answer

| Key | Behavior | Notes |
|---|---|---|
| `default` | `diff -b -B -Z` | Ignores whitespace differences within lines, blank lines, and trailing whitespace. The right default for most problems. |
| `exact` | `diff -q` | Byte-for-byte after the standard `diff` line algorithm. No whitespace tolerance. |
| `relative` | `lib/checker/relative.rb` | Tokenizes on whitespace. Numeric tokens are compared with `EPSILON = 1e-6`; non-numeric tokens must match exactly. Use for floating-point output. |
| `postgres` | `lib/checker/postgres_checker.rb` | Strips `CREATE VIEW` / `DROP VIEW` lines, then compares as CMS-style with score on stdout. Used by the DB course. |
| `custom_cafe` | Runs the dataset's `checker` file. | Receives args: `<language> <testcase_num> <input> <output> <answer> 10`. Output is two lines: line 1 = `CORRECT` / `INCORRECT` / `COMMENT: <text>`; line 2 = score (integer or decimal). **The score is divided by 10** (`checker.rb:51`: `arr[1].to_d / 10`) — so a checker outputting `100` yields a score of `10`. Non-obvious legacy quirk. |
| `custom_cms` | Runs the dataset's `checker` file. | CMS / Codeforces convention: exit 0, score on stdout, comment on stderr. The CMS framework's `translate:success` and `translate:wrong` markers on stderr are stripped automatically (`checker.rb:34`). |
| `custom_cms_raw` | Runs the dataset's `checker` file. | Stdout is a raw decimal score. **Designed to pair with `raw_sum` score_type** so the per-testcase numbers add up directly without renormalization. |

There is also a `'no_check'` branch in `checker.rb` (`check_command` returns
`""`, `process_result` returns a partial score of 0). It is **not in the
enum** (`Dataset#evaluation_type` values: 0=default, 1=exact, 2=relative,
3=custom_cafe, 4=custom_cms, 5=postgres, 6=custom_cms_raw), so it's
unreachable from the UI today. If you want a "skip judging" mode for
data-collection problems, surface it via the enum first.

## Compatibility cross-rules (not enforced; documented here)

- `raw_sum` + `custom_cms_raw` is the intended pairing. Other combinations
  with `raw_sum` will produce strange totals because the score for
  non-custom evaluators is just 0 or 100 per testcase.
- `custom_*` evaluators all require a `checker` file attached to the
  dataset (`checker.rb:100` checks this at run time and raises
  `GraderError` if missing).
- `custom_cafe`'s `/10` normalization means it natively lives on a 0-10
  scale. Convert your checker's intended scale accordingly.
