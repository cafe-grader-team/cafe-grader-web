#!/usr/bin/env python3
"""Extract a stratified sample of a task's real submissions from a live CMS
instance -- source + CMS-recorded per-testcase outcomes, plus
compilation_outcome/compilation_text -- as the oracle input for Mode B
submission-replay validation (doc/CMS-Migration.md Sec 3).

A submission whose compilation FAILED on CMS (`compilation_outcome ==
"fail"`) has NO SubmissionEvaluation rows at all -- there is nothing
per-testcase to sample, only a final score of 0.0. Such a submission still
lands in the "0" score band and is still extracted (with an empty
`evaluations` dict); `compilation_outcome` is what lets the Ruby side
(app/engine/replay/cms_replay.rb) recognise it and fall back to a
score-only comparison instead of trying to build a per-testcase verdict
string from nothing.

Runs ON the CMS server as the cms user, streamed over ssh (never installed),
the same shape as extract_task.py:

    ssh HOST sudo -n -u cms /home/cms/cms_venv/bin/python3 - TASKNAME LIMIT \
        < script/cms_extract/extract_submissions.py > sample.json

Read-only against CMS: queries via SQLAlchemy SessionGen (never committed --
SessionGen's __exit__ always rolls back) plus FileCacher for submitted
source blobs. Selects submissions on the task's ACTIVE dataset with a
non-null score, stratified across five score bands -- [100,100], [60,99],
[30,59], [1,29], [0,0] -- taking up to LIMIT per band, lowest submission ids
first for determinism.

stdout: fd 1 is reserved for ONE json object {task, dataset_id, submissions}
    ONLY. Before any work starts, main() dup2's fd 1 onto stderr and keeps
    the real stdout fd aside (same trick as extract_task.py) -- CMS logs to
    stdout in-process (e.g. constructing FileCacher() alone emits an INFO
    line) and would otherwise corrupt the payload.
stderr: progress log + any stdout chatter from libraries
    exit: 0 ok, 2 usage, 3 task/dataset not found
Work dir is 0700 under /tmp and removed on exit.
Consumed by app/engine/replay/cms_replay.rb (Replay::CmsReplay.run).
Python 3.6 on the server -- no f-strings, no walrus operator.
"""
import json
import os
import shutil
import sys
import tempfile


# Inclusive [lo, hi] score bands, checked in this order. A score outside all
# five (e.g. a fractional value that straddles a boundary) is simply not
# sampled -- these bands are what Tier 1 asks for, not a claim to cover the
# whole real line.
BANDS = [
    ("100", 100.0, 100.0),
    ("60-99", 60.0, 99.0),
    ("30-59", 30.0, 59.0),
    ("1-29", 1.0, 29.0),
    ("0", 0.0, 0.0),
]


def log(msg):
    sys.stderr.write(msg + "\n")
    sys.stderr.flush()


def normalize_outcome(outcome):
    """Evaluation.outcome is stored as a Unicode string (checkers can print
    arbitrary text there); cast to float, defaulting a missing/unparseable
    value to 0.0 rather than raising -- a genuinely missing outcome should
    surface downstream as a wrong-answer verdict, not crash the extraction.
    """
    if outcome is None or outcome == "":
        return 0.0
    try:
        return float(outcome)
    except (TypeError, ValueError):
        return 0.0


def normalize_text(text):
    """Evaluation.text is a Postgres ARRAY(String): CMS stores a format
    template as the first element with %-style args as the rest (for
    localization), e.g. ["Execution timed out"] or ["Output is partially
    correct"]. Downstream classification only substring-matches ("timed
    out" / "killed" / "memory" -- verified against cms/grading/steps on the
    live server), so joining the elements is enough; no need to replicate
    CMS's %-substitution.
    """
    if text is None:
        return ""
    if isinstance(text, (list, tuple)):
        return " ".join(str(t) for t in text)
    return str(text)


def band_submission_results(session, sr_cls, sub_cls, dataset, lo, hi, limit):
    return (session.query(sr_cls)
            .join(sub_cls, sr_cls.submission_id == sub_cls.id)
            .filter(sr_cls.dataset_id == dataset.id)
            .filter(sr_cls.score.isnot(None))
            .filter(sr_cls.score >= lo)
            .filter(sr_cls.score <= hi)
            .order_by(sub_cls.id.asc())
            .limit(limit)
            .all())


def extract_submission(fc, sr):
    """Build one submission's JSON entry, or return None (with a stderr
    warning) if it has no submitted file to read a source from.

    `compilation_outcome` is always included ("ok" / "fail" / None). When
    compilation failed, `sr.evaluations` is empty by construction (CMS never
    evaluates a submission that didn't compile) -- that's expected, not an
    extraction bug, and is exactly the signal the Ruby side uses to switch
    to a score-only comparison. `compilation_text` (CMS's compiler
    output, an ARRAY(String) like Evaluation.text) is included, normalised
    to a string, only when CMS actually recorded one.
    """
    sub = sr.submission
    files = list(sub.files.values())
    if not files:
        log("  WARNING: submission %d has no files -- skipped" % sub.id)
        return None
    if len(files) > 1:
        files.sort(key=lambda f: f.filename)
        log("  WARNING: submission %d has %d files (expected 1); using '%s'"
            % (sub.id, len(files), files[0].filename))

    content = fc.get_file(files[0].digest).read()
    source = content.decode("utf-8", "replace")

    evaluations = {}
    for ev in sr.evaluations:
        evaluations[ev.testcase.codename] = {
            "outcome": normalize_outcome(ev.outcome),
            "text": normalize_text(ev.text),
        }

    entry = {
        "cms_submission_id": sub.id,
        "language": sub.language,
        "cms_score": float(sr.score),
        "compilation_outcome": sr.compilation_outcome,
        "source": source,
        "evaluations": evaluations,
    }
    if sr.compilation_text:
        entry["compilation_text"] = normalize_text(sr.compilation_text)
    return entry


def main():
    # Same reservation trick as extract_task.py: CMS logs to stdout
    # in-process (e.g. constructing FileCacher() alone emits an INFO line),
    # which would otherwise interleave into the JSON payload.
    real_stdout_fd = os.dup(sys.stdout.fileno())
    os.dup2(sys.stderr.fileno(), sys.stdout.fileno())

    if len(sys.argv) != 3:
        log("usage: extract_submissions.py <task_name> <per_band_limit>")
        return 2
    task_name = sys.argv[1]
    try:
        per_band_limit = int(sys.argv[2])
    except ValueError:
        log("per_band_limit must be an integer, got %r" % (sys.argv[2],))
        return 2

    work = tempfile.mkdtemp(prefix="cms_extract_")
    os.chmod(work, 0o700)
    try:
        # The FileCacher may create relative cache dirs -> keep them inside
        # the 0700 work dir (same reasoning as extract_task.py).
        os.chdir(work)

        from cms.db import SessionGen, Task, Submission, SubmissionResult
        from cms.db.filecacher import FileCacher

        with SessionGen() as session:
            task = session.query(Task).filter(Task.name == task_name).first()
            if task is None:
                names = sorted(t.name for t in session.query(Task).all())
                log("ERROR: task '%s' not found. %d tasks exist, e.g.: %s"
                    % (task_name, len(names), ", ".join(names[:10])))
                return 3
            dataset = task.active_dataset
            if dataset is None:
                log("ERROR: task '%s' has no active dataset" % task_name)
                return 3
            log("[extract] task '%s' id %d, active dataset id %d ('%s')"
                % (task_name, task.id, dataset.id, dataset.description))

            fc = FileCacher()
            submissions = []
            for band_name, lo, hi in BANDS:
                srs = band_submission_results(session, SubmissionResult, Submission,
                                              dataset, lo, hi, per_band_limit)
                log("[extract] band %-6s: %d submission(s) (limit %d)"
                    % (band_name, len(srs), per_band_limit))
                for sr in srs:
                    entry = extract_submission(fc, sr)
                    if entry is not None:
                        submissions.append(entry)

            log("[extract] %d submission(s) total" % len(submissions))
            payload = {"task": task_name, "dataset_id": dataset.id, "submissions": submissions}

        log("[extract] writing JSON to fd 1 ...")
        out = os.fdopen(real_stdout_fd, "wb")
        try:
            out.write(json.dumps(payload, ensure_ascii=False).encode("utf-8"))
            out.flush()
        finally:
            out.close()
        log("[extract] done")
        return 0
    finally:
        shutil.rmtree(work, ignore_errors=True)


if __name__ == "__main__":
    sys.exit(main())
