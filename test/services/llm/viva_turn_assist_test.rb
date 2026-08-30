require "test_helper"

# Phase A (2026-07-21 context-policy design) makes Llm::VivaTurnAssist's
# private #exam_policy? always return false — every session now runs the
# practice branch of #apply_alert_policy, and the practice/exam toggle that
# used to pick the branch is gone. The warn-then-terminate exam branch is still real
# code, kept for Phase B (which will key #exam_policy? off the session's
# governing-contest snapshot instead), so it stays regression-tested here by
# forcing the selector on via this subclass rather than a mode flag.
class ExamPolicyStubVivaTurnAssist < Llm::VivaTurnAssist
  def exam_policy?
    true
  end
end

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
    # Viva requires a non-blank viva_prompt (examiner briefing) on the problem;
    # assemble_system_prompt raises without it. Content doesn't matter for these tests.
    @problem.update!(viva_prompt: 'You are a viva interviewer.')
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

  test "system prompt is just viva_prompt content + [[VIVA_DONE]] directive" do
    sys = @assist.send(:assemble_system_prompt)
    # the test setup sets viva_prompt to 'You are a viva interviewer.'
    assert_includes sys, 'You are a viva interviewer.'
    assert_includes sys, '[[VIVA_DONE]]'
    # Binding-token rule: announcing the end without the token strands the session.
    assert_includes sys, 'never announce the end without it'
    # No-LaTeX rule: safe_markdown renders $...$ as raw symbols.
    assert_includes sys, 'Do NOT use LaTeX'
    # backend no longer injects scenario-handling guidance — that's the prompt's job
    refute_includes sys, 'first user message contains the scenario'
  end

  test "system prompt layers in fixed order: conduct, briefing, security, done" do
    @problem.update!(viva_prompt: "# Rubric\ncorrectness: 100")
    @problem.tags << Tag.create!(name: 'b-conduct', kind: :viva_conduct, params: 'CONDUCT-B')
    @problem.tags << Tag.create!(name: 'a-conduct', kind: :viva_conduct, params: 'CONDUCT-A')
    svc = Llm::VivaTurnAssist.new(submission: @submission, turn: @placeholder)
    prompt = svc.send(:assemble_system_prompt)
    order = [prompt.index('CONDUCT-A'), prompt.index('CONDUCT-B'),
             prompt.index('# Rubric'), prompt.index('SECURITY'), prompt.index('[[VIVA_DONE]]')]
    assert_equal order.sort, order, "layers out of order: #{order.inspect}"
    assert order.all?, "a layer is missing: #{order.inspect}"
  end

  test "grounding material is added to first user message when grounding materials exist" do
    grounding = GroundingMaterial.create!(title: 'test_grounding', body: 'Reference: trees have nodes and edges.')
    @problem.grounding_materials << grounding

    msgs = @assist.send(:messages_array)
    user_msg = msgs[1]
    # With grounding, the first user message becomes a content array
    assert_kind_of Array, user_msg[:content]
    grounding_part = user_msg[:content].find { |p| p[:type] == 'text' && p[:text].include?('Grounding Material') }
    assert grounding_part, 'expected a Grounding Material text part in the first user message'
    assert_includes grounding_part[:text], 'trees have nodes'
  end

  test "handle_response raises ResponseError when choices array is empty" do
    response = Struct.new(:body).new('{"choices":[]}')
    err = assert_raises(Llm::Request::ResponseError) do
      @assist.send(:handle_response, response)
    end
    assert_match(/choices\[0\]\.message\.content/, err.message)
  end

  test "handle_response raises ResponseError when message content is missing" do
    response = Struct.new(:body).new('{"choices":[{"message":{}}]}')
    assert_raises(Llm::Request::ResponseError) do
      @assist.send(:handle_response, response)
    end
  end

  test "handle_response raises ResponseError when content is whitespace-only" do
    response = Struct.new(:body).new('{"choices":[{"message":{"content":"   \n  "}}]}')
    assert_raises(Llm::Request::ResponseError) do
      @assist.send(:handle_response, response)
    end
  end

  def alert_response_body(text)
    {choices: [{message: {content: text}}], model: 'stub', usage: {prompt_tokens: 1, completion_tokens: 1}}.to_json
  end

  test "default (practice) policy: alert logs a flag, injects notice, never terminates" do
    svc = Llm::VivaTurnAssist.new(submission: @submission, turn: @placeholder)
    result = svc.send(:handle_response, Struct.new(:body).new(alert_response_body("deflection [[VIVA_ALERT]]")))
    refute result[:done]
    assert @placeholder.reload.alerted
    assert_nil @submission.reload.viva_terminated_at
    assert_equal 'submitted', @submission.status
    assert @submission.viva_turns.where(role: :system).last.content.include?('practice mode')
  end

  test "exam_policy? branch: first strike warns, second terminates and grades" do
    svc = ExamPolicyStubVivaTurnAssist.new(submission: @submission, turn: @placeholder)
    r1 = svc.send(:handle_response, Struct.new(:body).new(alert_response_body("deflect [[VIVA_ALERT]]")))
    refute r1[:done]
    assert_nil @submission.reload.viva_terminated_at
    assert @submission.viva_turns.where(role: :system).last.content.include?('WARNING')

    turn2 = @submission.viva_turns.create!(role: :assistant, status: :processing, content: nil)
    svc2 = ExamPolicyStubVivaTurnAssist.new(submission: @submission, turn: turn2)
    r2 = svc2.send(:handle_response, Struct.new(:body).new(alert_response_body("deflect again [[VIVA_ALERT]]")))
    assert r2[:done]
    assert @submission.reload.viva_terminated_at.present?
    assert_equal 'evaluating', @submission.status
  end

  test "alerts recorded under the practice branch do not carry over as strikes once exam_policy? flips true" do
    # Two alerted turns recorded via the real (Phase A: always-practice) class.
    svc_a = Llm::VivaTurnAssist.new(submission: @submission, turn: @placeholder)
    svc_a.send(:handle_response, Struct.new(:body).new(alert_response_body("deflect [[VIVA_ALERT]]")))

    turn_b = @submission.viva_turns.create!(role: :assistant, status: :processing, content: nil)
    svc_b = Llm::VivaTurnAssist.new(submission: @submission, turn: turn_b)
    svc_b.send(:handle_response, Struct.new(:body).new(alert_response_body("deflect again [[VIVA_ALERT]]")))

    # Sanity: the reasons the next assertions matter actually hold — two
    # alerted turns are genuinely on record, and no exam warning has ever
    # been issued. A test that skipped this would pass vacuously even if
    # apply_alert_policy still counted raw alerts across the policy flip.
    assert_equal 2, @submission.viva_turns.where(alerted: true).count
    refute @submission.viva_turns.where(role: :system)
                       .exists?(content: Llm::VivaTurnAssist::EXAM_WARNING_NOTICE)

    # Simulate a flip to the exam branch (Phase B: keyed on the session's
    # governing-contest snapshot) by switching to the stub subclass.
    turn_c = @submission.viva_turns.create!(role: :assistant, status: :processing, content: nil)
    svc_c = ExamPolicyStubVivaTurnAssist.new(submission: @submission, turn: turn_c)
    r_c = svc_c.send(:handle_response, Struct.new(:body).new(alert_response_body("deflect once more [[VIVA_ALERT]]")))
    refute r_c[:done], "first exam-branch alert must warn (not terminate) even though 2 prior alerts exist from the practice branch"
    assert_nil @submission.reload.viva_terminated_at
    assert_equal 'submitted', @submission.status
    assert @submission.viva_turns.where(role: :system).last.content.include?('WARNING')

    turn_d = @submission.viva_turns.create!(role: :assistant, status: :processing, content: nil)
    svc_d = ExamPolicyStubVivaTurnAssist.new(submission: @submission, turn: turn_d)
    r_d = svc_d.send(:handle_response, Struct.new(:body).new(alert_response_body("deflect yet again [[VIVA_ALERT]]")))
    assert r_d[:done], "second exam-branch alert, after the exam-branch warning was issued, must terminate"
    assert @submission.reload.viva_terminated_at.present?
    assert_equal 'evaluating', @submission.status
  end

  test "system prompt carries the soft-cap pacing directive" do
    @problem.update!(viva_soft_cap: 7)
    svc = Llm::VivaTurnAssist.new(submission: @submission, turn: @placeholder)
    assert_includes svc.send(:assemble_system_prompt), 'within about 7 questions'
  end

  test "clean DONE still finishes without alert" do
    svc = Llm::VivaTurnAssist.new(submission: @submission, turn: @placeholder)
    result = svc.send(:handle_response, Struct.new(:body).new(alert_response_body("bye [[VIVA_DONE]]")))
    assert result[:done]
    refute @placeholder.reload.alerted
    assert_nil @submission.reload.viva_terminated_at
  end

  test "handle_response strips every occurrence of a doubled sentinel, not just the first" do
    svc = Llm::VivaTurnAssist.new(submission: @submission, turn: @placeholder)
    text = "deflect [[VIVA_ALERT]] more deflecting [[VIVA_ALERT]] bye [[VIVA_DONE]] [[VIVA_DONE]]"
    result = svc.send(:handle_response, Struct.new(:body).new(alert_response_body(text)))
    assert result[:done]
    assert result[:alerted]
    clean = @placeholder.reload.content
    refute_includes clean, Llm::VivaTurnAssist::ALERT_SENTINEL, 'no ALERT sentinel should leak into student-visible content'
    refute_includes clean, Llm::VivaTurnAssist::DONE_SENTINEL, 'no DONE sentinel should leak into student-visible content'
  end
end
