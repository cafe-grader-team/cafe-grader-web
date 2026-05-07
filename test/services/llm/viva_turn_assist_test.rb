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
    # Viva requires at least one llm_prompt tag on the problem; assemble_system_prompt
    # raises without it. Content doesn't matter for these tests.
    prompt_tag = Tag.find_or_create_by!(name: 'test_llm_prompt') do |t|
      t.kind = :llm_prompt
      t.params = 'You are a viva interviewer.'
    end
    @problem.tags << prompt_tag unless @problem.tags.include?(prompt_tag)
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
    @submission.viva_turns.create!(role: :assistant, status: :ok, content: 'next question')
    msgs = @assist.send(:messages_array)

    # consolidate_role_runs merges the consecutive user turns (scenario + answer)
    user_msg      = msgs.find { |m| m[:role] == 'user' && m[:content].include?('my answer') }
    assistant_msg = msgs.find { |m| m[:role] == 'assistant' && m[:content] == 'next question' }
    assert user_msg,      'expected a user message containing "my answer"'
    assert assistant_msg, 'expected the assistant message'
    # sanity: DB row still has student role
    assert student.student?
  end

  test "current placeholder turn is excluded from the message list" do
    msgs = @assist.send(:messages_array)
    refute msgs.any? { |m| m[:content] == '' }, 'placeholder content should not appear'
    # only system + scenario user; nothing else yet
    assert_equal 2, msgs.length
  end

  test "system prompt is just llm_prompt tag content + [[VIVA_DONE]] directive" do
    sys = @assist.send(:assemble_system_prompt)
    # the test setup attaches a tag with params 'You are a viva interviewer.'
    assert_includes sys, 'You are a viva interviewer.'
    assert_includes sys, '[[VIVA_DONE]]'
    # backend no longer injects scenario-handling guidance — that's the prompt's job
    refute_includes sys, 'first user message contains the scenario'
  end

  test "grounding material is added to first user message when viva_grounding tags exist" do
    grounding_tag = Tag.find_or_create_by!(name: 'test_viva_grounding') do |t|
      t.kind = :viva_grounding
      t.params = 'Reference: trees have nodes and edges.'
    end
    @problem.tags << grounding_tag unless @problem.tags.include?(grounding_tag)

    msgs = @assist.send(:messages_array)
    user_msg = msgs[1]
    # With grounding, the first user message becomes a content array
    assert_kind_of Array, user_msg[:content]
    grounding_part = user_msg[:content].find { |p| p[:type] == 'text' && p[:text].include?('Grounding Material') }
    assert grounding_part, 'expected a Grounding Material text part in the first user message'
    assert_includes grounding_part[:text], 'trees have nodes'
  end
end
