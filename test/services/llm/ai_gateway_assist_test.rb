require 'test_helper'

class Llm::AiGatewayAssistTest < ActiveSupport::TestCase
  GATEWAY_CONFIG = {
    display_name: 'Test Gateway',
    base_url: 'http://gateway.test',
    completion_path: '/v1/chat/completions',
    default_model: 'claude-sonnet-4-5',
    models: ['claude-sonnet-4-5', 'gemini-4-argon']
  }.freeze

  setup do
    @submission = submissions(:add1_by_john)
    @submission.problem.tags.create!(name: 'ca-prompt', kind: 'llm_prompt', params: 'You are a tutor.')
  end

  def with_gateway_config(cfg = GATEWAY_CONFIG)
    prev = Rails.configuration.llm[:ai_gateway]
    Rails.configuration.llm[:ai_gateway] = cfg
    yield
  ensure
    Rails.configuration.llm[:ai_gateway] = prev
  end

  # The payload exactly as execute_call posts it (PDF parts rewritten to `file`).
  def posted_payload(model: 'claude-sonnet-4-5')
    data = Llm::AiGatewayAssist.preview(redact: false, submission: @submission, comment: Comment.new, model: model)
    Llm::AiGatewayTransport.convert_pdf_parts(data)
  end

  def marked_parts(payload)
    payload[:messages].flat_map { |m| Array(m[:content]) }.select { |p| p.is_a?(Hash) && p.key?(:cache_control) }
  end

  test "a Claude model's boundary part carries the cache marker, right after the statement PDF, and nothing else does" do
    @submission.problem.statement.attach(io: StringIO.new('%PDF-1.4 test'), filename: 's.pdf', content_type: 'application/pdf')
    with_gateway_config do
      payload = posted_payload
      parts = payload[:messages].last[:content]
      assert_equal 'file', parts[0][:type]
      assert_equal Llm::CommentAssist::PROBLEM_MATERIAL_END, parts[1][:text]
      assert_equal({type: 'ephemeral'}, parts[1][:cache_control])
      assert_equal [parts[1]], marked_parts(payload), 'one marker: the student-specific parts must stay outside the stored part'
    end
  end

  test "prompt_cache: false keeps the boundary sentence but drops the marker" do
    with_gateway_config(GATEWAY_CONFIG.merge(prompt_cache: false)) do
      payload = posted_payload
      assert payload[:messages].last[:content].any? { |p| p[:text] == Llm::CommentAssist::PROBLEM_MATERIAL_END }
      assert_empty marked_parts(payload)
    end
  end

  # The Gateway answered HTTP 400 for every Gemini request whose material was
  # under Gemini's explicit-cache minimum (4,096 tokens) — a problem with no
  # statement PDF, like this fixture's.
  test "a Gemini model gets the boundary sentence without the marker, even with little material" do
    refute @submission.problem.statement.attached?, 'the case that failed had no statement PDF'
    with_gateway_config do
      payload = posted_payload(model: 'gemini-4-argon')
      assert_equal 'gemini-4-argon', payload[:model]
      assert payload[:messages].last[:content].any? { |p| p[:text] == Llm::CommentAssist::PROBLEM_MATERIAL_END }
      assert_empty marked_parts(payload)
    end
  end
end
