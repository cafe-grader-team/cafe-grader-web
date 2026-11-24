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

  test "fail_stale! threshold governs a turn that has started running" do
    turn = @submission.viva_turns.create!(role: :assistant, status: :processing, content: nil)
    VivaTurn.where(id: turn.id).update_all(llm_started_at: 2.minutes.ago, updated_at: 2.minutes.ago)

    # Default threshold (10 min) — started only 2 min ago, too fresh.
    assert_equal 0, VivaTurn.fail_stale!

    # Tighter threshold — now stale.
    assert_equal 1, VivaTurn.fail_stale!(threshold: 1.minute)
  end

  test "fail_stale! leaves a still-queued turn alone until the queue grace passes" do
    turn = @submission.viva_turns.create!(role: :assistant, status: :processing, content: nil)
    # queued 12 min ago but never started (llm_started_at nil)
    VivaTurn.where(id: turn.id).update_all(llm_started_at: nil, updated_at: 12.minutes.ago)

    assert_equal 0, VivaTurn.fail_stale!, "queued 12 min but not started — not yet stale at the 20 min grace"
    assert_equal 1, VivaTurn.fail_stale!(queue_threshold: 10.minutes)
  end

  test "the timed-out message names the wait that applied" do
    queued = @submission.viva_turns.create!(role: :assistant, status: :processing, content: nil)
    VivaTurn.where(id: queued.id).update_all(llm_started_at: nil, updated_at: 30.minutes.ago)
    VivaTurn.fail_stale!
    assert_match 'no response after 20 minutes', queued.reload.content

    running = @submission.viva_turns.create!(role: :assistant, status: :processing, content: nil)
    VivaTurn.where(id: running.id).update_all(llm_started_at: 15.minutes.ago, updated_at: 15.minutes.ago)
    VivaTurn.fail_stale!
    assert_match 'no response after 10 minutes', running.reload.content
  end
end
