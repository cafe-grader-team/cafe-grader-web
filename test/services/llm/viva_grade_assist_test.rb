require "test_helper"

class Llm::VivaGradeAssistTest < ActiveSupport::TestCase
  setup do
    @submission = submissions(:add1_by_admin)
    @submission.viva_turns.destroy_all
    @submission.viva_turns.create!(role: :assistant, status: :ok, content: 'first question')
    @submission.viva_turns.create!(role: :student,   status: :ok, content: 'my answer')
    @submission.viva_turns.create!(role: :assistant, status: :ok, content: 'follow-up')
    @problem = @submission.problem
    @problem.update_columns(description: "Scenario A\nScenario B")
    @assist = Llm::VivaGradeAssist.new(submission: @submission)
  end

  test "messages_array sends three messages: system + scenario + transcript" do
    msgs = @assist.send(:messages_array)
    assert_equal 3, msgs.length
    assert_equal 'system', msgs[0][:role]
    assert_equal 'user',   msgs[1][:role]
    assert_equal 'user',   msgs[2][:role]

    assert_equal "Scenario A\nScenario B", msgs[1][:content]
    assert_includes msgs[2][:content], 'Transcript:'
  end

  test "scenario message falls back to a placeholder when description is blank" do
    @problem.update_columns(description: '')
    fresh = Llm::VivaGradeAssist.new(submission: @submission)
    msgs  = fresh.send(:messages_array)
    assert_equal '(no scenario provided)', msgs[1][:content]
  end

  test "transcript labels student turns as USER:, not STUDENT:" do
    transcript = @assist.send(:transcript_payload)
    assert_includes transcript, 'USER: my answer'
    refute_includes transcript, 'STUDENT:'
    assert_includes transcript, 'ASSISTANT: first question'
    assert_includes transcript, 'ASSISTANT: follow-up'
  end

  test "system prompt explains the two-user-message layout" do
    sys = @assist.send(:grading_system_prompt)
    assert_includes sys, 'two user messages'
    assert_includes sys, 'scenario'
    assert_includes sys, 'transcript'
  end

  test "system/processing/error turns are filtered from the transcript" do
    @submission.viva_turns.create!(role: :system,    status: :ok,         content: '(interview start)')
    @submission.viva_turns.create!(role: :assistant, status: :processing, content: nil)
    @submission.viva_turns.create!(role: :assistant, status: :error,      content: 'LLM error: timeout')
    transcript = @assist.send(:transcript_payload)
    refute_includes transcript, '(interview start)'
    refute_includes transcript, 'timeout'
  end
end
