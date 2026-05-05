require "test_helper"

class Llm::VivaTurnAssistTest < ActiveSupport::TestCase
  setup do
    @submission = submissions(:add1_by_admin)
    @submission.viva_turns.destroy_all
    @placeholder = @submission.viva_turns.create!(role: :assistant, status: :processing)
    # Use the same in-memory Problem the assist will read via @submission.problem,
    # so update_columns calls below are visible to the assist without needing reload.
    @problem = @submission.problem
    # update_columns bypasses the after_save PDF-generation callback that we don't want firing in unit tests
    @problem.update_columns(description: "Scenario A\nScenario B")
    @assist = Llm::VivaTurnAssist.new(submission: @submission, turn: @placeholder)
  end

  test "messages_array prepends description as first user message" do
    msgs = @assist.send(:messages_array)
    assert_equal 'system', msgs.first[:role]
    assert_equal 'user',   msgs[1][:role]
    assert_equal "Scenario A\nScenario B", msgs[1][:content]
  end

  test "first user message falls back to placeholder when description is blank" do
    @problem.update_columns(description: '')
    fresh = Llm::VivaTurnAssist.new(submission: @submission, turn: @placeholder)
    msgs  = fresh.send(:messages_array)
    assert_equal 'user', msgs[1][:role]
    assert_equal '(begin the interview)', msgs[1][:content]
  end

  test "student turns are remapped to role: user on the wire" do
    student = @submission.viva_turns.create!(role: :student, status: :ok, content: 'my answer')
    assistant = @submission.viva_turns.create!(role: :assistant, status: :ok, content: 'next question')
    msgs = @assist.send(:messages_array)

    student_msg = msgs.find { |m| m[:content] == 'my answer' }
    assistant_msg = msgs.find { |m| m[:content] == 'next question' }
    assert_equal 'user',      student_msg[:role]
    assert_equal 'assistant', assistant_msg[:role]
    # sanity: DB row still has student role
    assert student.student?
  end

  test "current placeholder turn is excluded from the message list" do
    msgs = @assist.send(:messages_array)
    refute msgs.any? { |m| m[:content] == '' }, 'placeholder content should not appear'
    # only system + scenario user; nothing else yet
    assert_equal 2, msgs.length
  end

  test "scenario instruction is included in system prompt iff description is present" do
    sys_with = @assist.send(:assemble_system_prompt)
    assert_includes sys_with, 'first user message contains the scenario'

    @problem.update_columns(description: '')
    fresh   = Llm::VivaTurnAssist.new(submission: @submission, turn: @placeholder)
    sys_off = fresh.send(:assemble_system_prompt)
    refute_includes sys_off, 'first user message contains the scenario'
  end

  test "system prompt always ends with the [[VIVA_DONE]] sentinel instruction" do
    sys = @assist.send(:assemble_system_prompt)
    assert_includes sys, '[[VIVA_DONE]]'
  end
end
