require "test_helper"

# Model-level coverage for the Auditable concern's destroy path. The
# "Auditable must exist" bug (fixed by making `belongs_to :auditable`
# optional, 2026-05-17) slipped through because there was no test that a
# destroy actually writes its audit row — only a controller integration
# test for the read paths. These tests guard both shapes: an own-row
# destroy, and a cascade through a `dependent: :destroy` association.
class AuditableTest < ActiveSupport::TestCase
  test "destroying an audited record writes a destroy audit row" do
    contest = contests(:contest_b)
    assert_difference -> { AuditLog.for(contest).where(action: "destroy").count }, 1 do
      contest.destroy!
    end
  end

  test "destroy audit snapshots tracked attributes as [value, nil]" do
    contest = contests(:contest_b)
    name = contest.name
    contest.destroy!
    row = AuditLog.for(contest).find_by(action: "destroy")
    assert_not_nil row, "expected a destroy audit row for the contest"
    assert_equal [name, nil], row.object_changes["name"]
  end

  test "destroying a parent cascades destroy audit rows to dependent children" do
    contest = contests(:contest_a)
    cp_ids = contest.contests_problems.pluck(:id)
    cu_ids = contest.contests_users.pluck(:id)
    assert cp_ids.any? && cu_ids.any?,
      "fixture should have ContestProblem/ContestUser children to cascade"

    contest.destroy!

    assert_equal cp_ids.sort,
      AuditLog.where(auditable_type: "ContestProblem", action: "destroy", auditable_id: cp_ids)
              .pluck(:auditable_id).sort
    assert_equal cu_ids.sort,
      AuditLog.where(auditable_type: "ContestUser", action: "destroy", auditable_id: cu_ids)
              .pluck(:auditable_id).sort
  end

  test "AuditLog.paused suppresses the destroy audit row" do
    contest = contests(:contest_b)
    assert_no_difference -> { AuditLog.where(action: "destroy").count } do
      AuditLog.paused { contest.destroy! }
    end
  end
  # --- update path: the diff must survive everything that can happen between
  # the save and the commit (2026-09-17, viva:import wrote no audit row).

  test "an update audited inside a transaction survives a reload before the commit" do
    problem = problems(:prob_add)
    old_name = problem.full_name
    assert_difference -> { AuditLog.for(problem).where(action: "update").count }, 1 do
      ActiveRecord::Base.transaction do
        problem.update!(full_name: "renamed in a transaction")
        problem.reload   # clears saved_changes — the trap viva:import's post_check fell into
      end
    end
    row = AuditLog.for(problem).where(action: "update").last
    assert_equal [old_name, "renamed in a transaction"], row.object_changes["full_name"]
  end

  test "two saves in one transaction give one update row with the merged diff" do
    problem = problems(:prob_add)
    old_name, old_score = problem.full_name, problem.full_score
    assert_difference -> { AuditLog.for(problem).where(action: "update").count }, 1 do
      ActiveRecord::Base.transaction do
        problem.update!(full_name: "first save")
        problem.update!(full_score: 42)
        problem.update!(full_name: "second save")
      end
    end
    row = AuditLog.for(problem).where(action: "update").last
    assert_equal [old_name, "second save"], row.object_changes["full_name"], "first old, last new"
    assert_equal [old_score, 42], row.object_changes["full_score"]
  end

  test "a field changed and changed back inside one transaction is not reported" do
    problem = problems(:prob_add)
    old_name = problem.full_name
    ActiveRecord::Base.transaction do
      problem.update!(full_name: "temporary")
      problem.update!(full_name: old_name, full_score: 77)
    end
    row = AuditLog.for(problem).where(action: "update").last
    assert_not_nil row
    assert_equal %w[full_score], row.object_changes.keys
  end

  test "create then update in one transaction gives one create row carrying both saves" do
    problem = nil
    assert_difference -> { AuditLog.where(auditable_type: "Problem", action: "create").count }, 1 do
      assert_no_difference -> { AuditLog.where(auditable_type: "Problem", action: "update").count } do
        ActiveRecord::Base.transaction do
          problem = Problem.create!(name: "audit_created", full_name: "Created", full_score: 1, date_added: Date.current)
          problem.update!(full_score: 7)
        end
      end
    end
    row = AuditLog.for(problem).find_by(action: "create")
    assert_equal "audit_created", row.object_changes["name"].last
    assert_equal 7, row.object_changes["full_score"].last, "the create row shows the value as committed"
  end

  test "a rolled-back save leaves nothing behind for the next commit" do
    problem = problems(:prob_add)
    ActiveRecord::Base.transaction do
      problem.update!(full_name: "never committed")
      raise ActiveRecord::Rollback
    end
    problem.update!(full_score: 5)
    row = AuditLog.for(problem).where(action: "update").last
    assert_equal %w[full_score], row.object_changes.keys, "the rolled-back full_name must not leak into this row"
  end

  test "AuditLog.paused around a save inside an outer transaction still suppresses the row" do
    problem = problems(:prob_add)
    assert_no_difference -> { AuditLog.for(problem).count } do
      ActiveRecord::Base.transaction do
        AuditLog.paused { problem.update!(full_name: "quiet") }
      end
    end
  end
end
