# Overview

**Checker** and **auxiliary files** are optional components used during the execution, evaluation, or scoring of a problem in the *cafe-grader* system. Some auxiliary files are associated with the overall problem (e.g., *Attachment*), while others are tied to individual datasets (e.g., *Checker*, *Managers*, *Data Files*, *Initializers*). There are four types of dataset-level auxiliary files:

- **Checker** — A program that determines the score of a contestant's output. By default, outputs must match the expected answer using whitespace-tolerant `diff`. A checker can be supplied to allow multiple valid outputs, partial scoring, or domain-specific validation (e.g., judging PostgreSQL queries).
- **Managers** — Source files that are visible during both the compilation and evaluation phases. These are used when the contestant submits only a function implementation. The *manager* typically includes a `main()` function that calls the contestant's code. When using managers, the problem setter must specify the file that acts as the main entry point.
- **Data Files** — Files available in read-only mode during evaluation. The same file is accessible for every testcase and is typically used to provide static data that the submission must read.
- **Initializer** — A program executed **once per worker host per dataset**. This is useful when the problem requires external setup, such as loading data into a database. Since different workers may run on different hosts, initializers help ensure a consistent starting state.

---

# Evaluation Types

Every dataset carries an `evaluation_type` that selects how the contestant's output is compared to the expected answer. The complete list is:

| `evaluation_type`  | Requires a custom checker? | Description                                                                                                  |
|--------------------|:--------------------------:|--------------------------------------------------------------------------------------------------------------|
| `default`          | No                         | Whitespace-tolerant diff (`diff -q -b -B -Z`) — ignores trailing blanks and blank lines. **The default.**    |
| `exact`            | No                         | Strict byte-for-byte diff (`diff -q`).                                                                        |
| `relative`         | No                         | Token-wise floating-point comparison via `lib/checker/relative.rb`.                                          |
| `postgres`         | No                         | Built-in PostgreSQL checker (`lib/checker/postgres_checker.rb`).                                              |
| `custom_cms`       | **Yes**                    | Runs the attached checker in CMS-style (score 0.0–1.0).                                                       |
| `custom_cms_raw`   | **Yes**                    | Runs the attached checker in CMS-style but the score is stored verbatim (not clamped to 0–1). Allows negative scores, subject to the DB column's precision. |
| `custom_cafe`      | **Yes**                    | Runs the attached checker in cafe-grader style.                                                               |
| `no_check`         | No                         | No comparison is performed; the evaluation is recorded as `partial` with score 0. Useful for manual grading. |

The three `custom_*` types require a **Checker** file to be attached to the dataset; validation fails otherwise.

---

# Checker

A **checker** is an executable file that scores the output of a contestant's submission. It can be either a script with a shebang line (e.g., `#!/usr/bin/env python3`) or a compiled binary. Checkers receive input via command-line arguments and communicate results through `STDOUT` and optionally `STDERR`.

The checker is executed **only after the submission finishes successfully** — i.e., it does not crash, exceed the time limit, or blow the memory limit. Input file paths, expected outputs, and contestant outputs are passed as arguments.

cafe-grader supports three checker invocation styles: **CMS**, **CMS raw**, and **cafe-grader**. They differ in argument order and in how STDOUT is interpreted.

A checker must exit with status `0`. A non-zero exit status is treated as a **grader error**, and the stderr output is captured in the evaluation comment for diagnosis.

---

## CMS Style (`custom_cms`)

The checker receives:

- `ARGV[1]` — Full path to the testcase input file
- `ARGV[2]` — Full path to the contestant's output
- `ARGV[3]` — Full path to the expected answer file

The checker must print a single line to `STDOUT` containing a floating-point number between `0.0` and `1.0`, representing the score for the testcase (`1.0` = full score). Testcase weights are applied by the system; the checker only judges correctness of the specific testcase.

The checker may also print a line to `STDERR` — this becomes a *comment* visible to contestants on the result page. As a convenience for porting CMS checkers, the stderr strings `translate:success` and `translate:wrong` are stripped (they produce no contestant-visible comment).

---

## CMS Raw Style (`custom_cms_raw`)

Arguments are **identical to `custom_cms`**. The difference is in how the score is interpreted:

- The STDOUT score is **not** clamped to `0.0`–`1.0`; it is stored verbatim (including negative values).
- The stored value is bounded only by the precision of the `evaluations.score` column in the database.
- The evaluation is always recorded as `partial` — it will never be marked `correct` or `wrong` by the comparator alone. Final pass/fail status depends on the dataset's `score_type` and any downstream scoring logic.

Use this mode for problems where you want to award a continuous, possibly negative score (e.g., penalty-based heuristic problems, regression-style grading).

---

## cafe-grader Style (`custom_cafe`)

The checker receives:

- `ARGV[1]` — Submission language name (e.g., `cpp`, `python`)
- `ARGV[2]` — Testcase number
- `ARGV[3]` — Full path to the testcase input file
- `ARGV[4]` — Full path to the contestant's output
- `ARGV[5]` — Full path to the expected answer file
- `ARGV[6]` — The literal string `10` (the full-mark scale; see the output format below)

`ARGV[1]`, `ARGV[2]`, and `ARGV[6]` are provided for backward compatibility and are typically unused.

This style requires the checker to output **two lines** to `STDOUT`:

1. A verdict line, one of:
   - `CORRECT` — Full score. The second line is ignored.
   - `INCORRECT` — Zero score. The second line is ignored.
   - `COMMENT:xxx` — Partial credit; the score is read from the second line. `xxx` is shown to the contestant on the result page.

2. A floating-point score in the range `0.0`–`10.0`, used only when the first line starts with `COMMENT:`. A score of `10.0` corresponds to full marks (the system divides by 10 internally).

If the output is malformed (fewer than two lines, or an unrecognized verdict), the evaluation is recorded as a grader error.

---

## Example (`custom_cms`)

Suppose the problem is to print all **odd numbers** between two integers `A` and `B` (inclusive), in any order. A valid output for input `4 9` could be `5 7 9`, `5 9 7`, `9 7 5`, etc. Since multiple correct outputs are allowed, a custom checker is needed.

```python
#!/usr/bin/env python3
import sys

def report_wrong(comment):
    print("0.0")
    sys.stderr.write(comment)
    exit(0)

def report_correct():
    print("1.0")
    exit(0)

# Read A and B
with open(sys.argv[1]) as input_file:
    A, B = [int(x) for x in next(input_file).split()]

# Dictionary to track numbers
avail = {}

# Read contestant output
with open(sys.argv[2]) as output_file:
    array = [int(x) for x in next(output_file).split()]

for x in array:
    if avail.get(x):
        report_wrong("Duplicate number")
    if x < A or x > B:
        report_wrong("Number out of range")
    if x % 2 != 1:
        report_wrong("Not odd number")
    avail[x] = True

# Check for missing numbers
for num in range(A, B + 1):
    if num % 2 == 1 and not avail.get(num):
        report_wrong("Missing")

report_correct()
```

---

# Managers

In many problems, the problem setter wants contestants to submit only part of their program — typically a specific function — while the setter provides the surrounding code that reads input, calls the contestant's function, and writes output. In that case, the problem setter must include a **manager** file in the dataset. The contestant's source file and the manager file are compiled (or run) together in the same working directory.

When managers are attached, the dataset's `main_filename` must identify which manager file is the entry point. Uploading managers automatically switches the problem's `compilation_type` to `with_managers`.

### Example

Suppose we want a contestant to implement the C++ function `int max_diff(const vector<int> &a)`, which returns the maximum difference between two elements of `a`. Assume the contestant's code is in `student.h`. The manager might look like:

```cpp
#include <iostream>
#include <vector>
#include "student.h"

int main() {
    std::ios_base::sync_with_stdio(false);
    std::cin.tie(0);

    int n;
    std::cin >> n;
    std::vector<int> a(n);
    for (int i = 0; i < n; ++i) {
        std::cin >> a[i];
    }

    // Calling the contestant's function
    int result = max_diff(a);

    std::cout << result << std::endl;
}
```

The manager handles I/O and calls `max_diff`. The contestant only needs to implement the function body.

### Example — manager with embedded checker logic

For problems where checker logic is tightly coupled with the manager, you can integrate them:

```cpp
#include <iostream>
#include <vector>
#include <algorithm>
#include "student.h"

int main() {
    std::ios_base::sync_with_stdio(false);
    std::cin.tie(0);

    int n;
    std::cin >> n;
    std::vector<int> a(n);
    for (int i = 0; i < n; ++i) {
        std::cin >> a[i];
    }

    // Compute the reference answer inside the manager
    int min_value = *std::min_element(a.begin(), a.end());
    int max_value = *std::max_element(a.begin(), a.end());
    int correct_result = max_value - min_value;

    // Call the contestant's function
    int result = max_diff(a);

    // Embedded checker logic
    if (result == correct_result) {
        std::cout << "YES luius8yag4hlakjsdlfkjd" << std::endl;
    } else {
        std::cout << "NO" << std::endl;
    }
}
```

In this pattern the expected output for every testcase is the literal string `YES luius8yag4hlakjsdlfkjd`. The random suffix prevents a contestant from bypassing the checker by simply printing `YES` and exiting. Separating the manager and checker is usually cleaner, but embedding can be convenient when they share significant state.

---

# Data Files

Data files are attached to the dataset and mounted **read-only** inside the sandbox at evaluation time. Every testcase sees the same set of files. Use them for static reference data that the submission must consult (e.g., lookup tables, pre-computed indexes).

Data files are downloaded to each worker once and reused across testcases.

---

# Initializers

Initializers are executables attached to the dataset. When a worker first encounters a dataset, it downloads the initializer(s) and runs the one named by the dataset's `initializer_filename` exactly once. The result is recorded in the `worker_datasets` table so the initializer is not re-run on subsequent submissions from the same worker.

Use initializers for per-host setup that would be too expensive to repeat for every submission — for example, bulk-loading rows into a local PostgreSQL instance.

The initializer is invoked with three arguments:

1. A JSON string describing every testcase, of the shape:
   ```json
   {
     "testcases": {
       "<testcase_id>": {
         "inp_file": "/absolute/path/to/input",
         "ans_file": "/absolute/path/to/answer"
       },
       ...
     }
   }
   ```
2. A dataset-specific config file path (currently reserved for `postgresql_config.yml`).
3. A workspace path the initializer may use for scratch files.

Initializer exit status is not currently inspected; any setup errors must be diagnosed from worker logs.
