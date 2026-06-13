require "test_helper"

class VivaTurnTest < ActiveSupport::TestCase
  setup do
    @submission = submissions(:add1_by_admin)
  end

  # Helper: bypass the touch on save by stamping updated_at directly.
  def stamp_updated_at(turn, time)
    VivaTurn.where(id: turn.id).update_all(updated_at: time)
    turn.reload
  end

  test "fail_stale! marks old :processing turns as :error" do
    stuck = @submission.viva_turns.create!(role: :assistant, status: :processing, content: nil)
    stamp_updated_at(stuck, 30.minutes.ago)

    count = VivaTurn.fail_stale!
    stuck.reload

    assert_equal 1, count
    assert_predicate stuck, :error?
    assert_match(/timed out/i, stuck.content)
    assert_match(/Retry/, stuck.content)
  end

  test "fail_stale! leaves fresh :processing turns alone" do
    fresh = @submission.viva_turns.create!(role: :assistant, status: :processing, content: nil)
    # Default updated_at is now → within the threshold.

    count = VivaTurn.fail_stale!
    fresh.reload

    assert_equal 0, count
    assert_predicate fresh, :processing?
  end

  test "fail_stale! ignores already-resolved turns" do
    ok_turn = @submission.viva_turns.create!(role: :assistant, status: :ok, content: "done")
    error_turn = @submission.viva_turns.create!(role: :assistant, status: :error, content: "oops")
    stamp_updated_at(ok_turn, 1.hour.ago)
    stamp_updated_at(error_turn, 1.hour.ago)

    count = VivaTurn.fail_stale!

    assert_equal 0, count, ":ok and :error turns must not be touched"
    ok_turn.reload
    error_turn.reload
    assert_predicate ok_turn, :ok?
    assert_predicate error_turn, :error?
  end

  test "fail_stale! ignores non-assistant roles even if :processing somehow" do
    # Student/system turns shouldn't sit in :processing (the model
    # validates content presence for ok student turns; :processing has
    # no such requirement so this oddball state is technically reachable
    # by raw SQL). The sweeper should still only touch assistant turns.
    weird = @submission.viva_turns.create!(role: :student, status: :processing, content: "x")
    stamp_updated_at(weird, 1.hour.ago)

    count = VivaTurn.fail_stale!
    weird.reload

    assert_equal 0, count
    assert_predicate weird, :processing?
  end

  test "fail_stale! threshold is configurable" do
    turn = @submission.viva_turns.create!(role: :assistant, status: :processing, content: nil)
    stamp_updated_at(turn, 2.minutes.ago)

    # Default threshold (10 min) — too fresh.
    assert_equal 0, VivaTurn.fail_stale!

    # Tighter threshold — now stale.
    count = VivaTurn.fail_stale!(threshold: 1.minute)
    assert_equal 1, count
  end
end
