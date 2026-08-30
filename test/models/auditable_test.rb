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
end
