#!/usr/bin/env python3
"""Extract ONE task from a live CMS instance as a portable bundle.

Runs ON the CMS server as the cms user, streamed over ssh (never installed):

    ssh HOST sudo -n -u cms /home/cms/cms_venv/bin/python3 - TASKNAME [DUMP_DIR] \
        < script/cms_extract/extract_task.py > bundle.tar

Wraps the official cmsDumpExporter for ALL serialization (structure-only,
no submissions / user-tests / print jobs; the full-instance structure dump
measured ~45 s on c2, which is fine per clone, so no -c contest scoping is
needed). Adds only what official tooling cannot do:
  * single-task subtree filter -- Users/Participations (password hashes)
    never enter the bundle and never leave the server
  * digest-selective blob fetch via cms FileCacher (blobs live in the DB;
    there is no on-disk file store on c2)

Optional second positional argument DUMP_DIR lets callers reuse ONE dump
across many invocations (bulk cloning, see lib/tasks/cms.rake cms:clone_all):
  * if <DUMP_DIR>/dump/contest.json already exists, the exporter is SKIPPED
    and that file is read directly (logged as reusing the dump);
  * otherwise the exporter is run INTO <DUMP_DIR>/dump, creating DUMP_DIR
    itself (0700) if needed -- the exporter refuses to write into an
    already-existing dir, so "dump" is always a fresh subpath the first time,
    and present for every later call to reuse.
DUMP_DIR itself is never removed by this script -- the caller owns its
lifecycle (created and rm -rf'd once for the whole bulk run). Omitting
DUMP_DIR keeps prior behaviour exactly: the dump lives under this run's own
temp dir and is deleted with it on exit.

stdout: fd 1 is reserved for the tar stream of bundle/ (task.json +
    files/<digest>) ONLY. Before any work starts, main() dup2's fd 1 onto
    stderr and keeps the real stdout fd aside, so any library that writes
    to stdout/print() (CMS logs there in-process) lands on stderr instead
    of corrupting the tar; the tar is written straight to the saved fd.
stderr: progress log + any stdout chatter from libraries
    exit: 0 ok, 2 usage, 3 task not found
Read-only against CMS. This run's own temp work dir is 0700 under /tmp and
    removed on exit; a caller-supplied DUMP_DIR is not (see above).
Consumed by app/engine/converters/cms_dump_converter.rb (bundle_version 1).
"""
import json
import os
import shutil
import subprocess
import sys
import tarfile
import tempfile

BUNDLE_VERSION = 1
VENV = os.environ.get("CMS_VENV", "/home/cms/cms_venv")


def log(msg):
    sys.stderr.write(msg + "\n")
    sys.stderr.flush()


def build_subtree(objects, task_name):
    """Return (task_id, subtree, digests) for the named task.

    Pure function over the dump's object map (no CMS imports) so it is
    unit-testable off-server. Only the task row and its statements,
    attachments, datasets, managers, and testcases enter the subtree.
    """
    task_ids = [k for k, v in objects.items()
                if v.get("_class") == "Task" and v.get("name") == task_name]
    if not task_ids:
        return None, None, None
    tid = task_ids[0]
    task = objects[tid]
    subtree = {tid: task}
    digests = []
    for sid in task.get("statements", {}).values():
        subtree[str(sid)] = objects[str(sid)]
        digests.append(objects[str(sid)]["digest"])
    for aid in task.get("attachments", {}).values():
        subtree[str(aid)] = objects[str(aid)]
        digests.append(objects[str(aid)]["digest"])
    for did in task.get("datasets", []):
        ds = objects[str(did)]
        subtree[str(did)] = ds
        for mid in ds.get("managers", {}).values():
            subtree[str(mid)] = objects[str(mid)]
            digests.append(objects[str(mid)]["digest"])
        for tcid in ds.get("testcases", {}).values():
            tc = objects[str(tcid)]
            subtree[str(tcid)] = tc
            digests.append(tc["input"])
            digests.append(tc["output"])
    return tid, subtree, digests


def run_exporter(dump_dir):
    """Run the official cmsDumpExporter INTO dump_dir (must not yet exist)."""
    log("[extract] official cmsDumpExporter (structure only, no submissions) ...")
    subprocess.run(
        [os.path.join(VENV, "bin", "cmsDumpExporter"),
         "-F", "-S", "-U", "-P", dump_dir],
        check=True, stdout=sys.stderr, stderr=sys.stderr)


def main():
    # CMS logs to stdout from *inside our process* (not just the
    # cmsDumpExporter subprocess, which is already redirected below via
    # stdout=sys.stderr) -- e.g. constructing FileCacher() alone emits an
    # INFO line to stdout. In the 2026-08-02 live run those lines, plus more
    # emitted during the blob-fetch loop, interleaved into the tar bytes and
    # corrupted the received stream. Reserve the real fd 1 for the tar only:
    # save it aside, then point fd 1 at stderr so ANY library write to
    # stdout (now or in a future CMS version) is harmless.
    real_stdout_fd = os.dup(sys.stdout.fileno())
    os.dup2(sys.stderr.fileno(), sys.stdout.fileno())

    if len(sys.argv) not in (2, 3):
        log("usage: extract_task.py <task_name> [dump_dir]")
        return 2
    task_name = sys.argv[1]
    dump_dir_arg = sys.argv[2] if len(sys.argv) == 3 else None
    work = tempfile.mkdtemp(prefix="cms_extract_")
    os.chmod(work, 0o700)
    try:
        # The exporter/FileCacher may create relative cache dirs -> keep them
        # inside the 0700 work dir.
        os.chdir(work)
        if dump_dir_arg:
            # Reusable across many invocations (bulk clone): the exporter
            # writes into a fresh "dump" subpath the first time; later calls
            # find it there and skip the exporter entirely.
            dump_dir = os.path.join(dump_dir_arg, "dump")
            if os.path.exists(os.path.join(dump_dir, "contest.json")):
                log("[extract] reusing existing dump at %s" % dump_dir)
            else:
                if not os.path.isdir(dump_dir_arg):
                    os.makedirs(dump_dir_arg)
                    os.chmod(dump_dir_arg, 0o700)
                run_exporter(dump_dir)
        else:
            dump_dir = os.path.join(work, "dump")  # exporter refuses existing dirs
            run_exporter(dump_dir)
        with open(os.path.join(dump_dir, "contest.json")) as f:
            dump = json.load(f)
        dump_version = dump.get("_version")
        objects = {k: v for k, v in dump.items() if not k.startswith("_")}
        tid, subtree, digests = build_subtree(objects, task_name)
        if tid is None:
            names = sorted(v["name"] for v in objects.values()
                           if v.get("_class") == "Task")
            log("ERROR: task '%s' not found. %d tasks exist, e.g.: %s"
                % (task_name, len(names), ", ".join(names[:10])))
            return 3
        log("[extract] task id %s: %d objects, %d unique blobs"
            % (tid, len(subtree), len(set(digests))))

        bundle = os.path.join(work, "bundle")
        files_dir = os.path.join(bundle, "files")
        os.makedirs(files_dir)
        with open(os.path.join(bundle, "task.json"), "w") as f:
            json.dump({"bundle_version": BUNDLE_VERSION,
                       "dump_version": dump_version,
                       "task_id": tid,
                       "objects": subtree},
                      f, ensure_ascii=False, indent=1)

        log("[extract] fetching blobs via FileCacher ...")
        from cms.db.filecacher import FileCacher  # venv import; server only
        fc = FileCacher()
        for dig in sorted(set(digests)):
            src = fc.get_file(dig)
            with open(os.path.join(files_dir, dig), "wb") as out:
                shutil.copyfileobj(src, out)
            src.close()

        log("[extract] streaming bundle to stdout ...")
        out_stream = os.fdopen(real_stdout_fd, "wb")
        try:
            tar = tarfile.open(fileobj=out_stream, mode="w|")
            try:
                tar.add(bundle, arcname="bundle")
            finally:
                tar.close()
            out_stream.flush()
        finally:
            out_stream.close()
        log("[extract] done")
        return 0
    finally:
        shutil.rmtree(work, ignore_errors=True)


if __name__ == "__main__":
    sys.exit(main())
