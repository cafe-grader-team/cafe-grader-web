require 'test_helper'
require 'open3'

# extract_task.py runs on the CMS server, but its subtree filter is a pure
# function — tested here by shelling the dev box's python3 against the
# committed fixture's object map plus an injected User row (which must be
# excluded: password hashes never enter a bundle).
class ExtractTaskFilterTest < ActiveSupport::TestCase
  SCRIPT  = Rails.root.join('script/cms_extract/extract_task.py')
  FIXTURE = Rails.root.join('test/cms_bundles/eatingfish_mini/task.json')

  PYTEST = <<~PY
    import importlib.util, json, sys
    spec = importlib.util.spec_from_file_location("extract_task", sys.argv[1])
    m = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(m)
    data = json.load(open(sys.argv[2]))
    objs = dict(data["objects"])
    objs["999"] = {"_class": "User", "username": "x", "password": "hash"}
    objs["998"] = {"_class": "Participation", "user": "999", "contest": "7"}
    tid, subtree, digests = m.build_subtree(objs, "eatingfish_mini")
    assert tid == "408", tid
    assert "999" not in subtree and "998" not in subtree, "user data leaked"
    assert subtree["408"]["_class"] == "Task"
    assert "1414" in subtree and "1418" in subtree, "datasets missing"
    assert "20001" in subtree, "testcase missing"
    ds = set(digests)
    for d in ["dig-grader", "dig-header", "dig-st-th", "dig-st-en", "dig-att",
              "dig-in-101", "dig-out-101", "dig-in-201", "dig-out-201",
              "dig-in-202", "dig-out-202"]:
        assert d in ds, "missing digest " + d
    missing_tid, _, _ = m.build_subtree(objs, "no_such_task")
    assert missing_tid is None
    print("OK")
  PY

  test 'build_subtree keeps the task subtree, drops users, collects all digests' do
    out, err, status = Open3.capture3({ 'PYTHONDONTWRITEBYTECODE' => '1' },
                                       'python3', '-c', PYTEST, SCRIPT.to_s, FIXTURE.to_s)
    assert status.success?, "python failed:\n#{err}"
    assert_includes out, 'OK'
  end
end
