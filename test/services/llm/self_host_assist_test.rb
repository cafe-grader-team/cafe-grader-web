require 'test_helper'

class Llm::SelfHostAssistTest < ActiveSupport::TestCase
  FAKE_MODELS = {
    qwen: {base_url: 'http://dgx.test:8000', completion_path: '/v1/chat/completions', model: 'qwen-test', max_tokens: 4096}
  }.freeze

  FakeResponse = Struct.new(:body)

  setup do
    @submission = submissions(:add1_by_john)
    @submission.problem.tags.create!(name: 'nm-prompt', kind: 'llm_prompt', params: 'You are a tutor.')
    @comment = @submission.comments.create!(user: users(:john), kind: 'llm_assist',
                                            title: 't', body: 'b', cost: 0, status: 'processing')
  end

  def with_self_host_config
    prev_m = Rails.configuration.llm[:self_hosted_models]
    prev_d = Rails.configuration.llm[:self_hosted_default]
    Rails.configuration.llm[:self_hosted_models] = FAKE_MODELS
    Rails.configuration.llm[:self_hosted_default] = 'qwen'
    yield
  ensure
    Rails.configuration.llm[:self_hosted_models] = prev_m
    Rails.configuration.llm[:self_hosted_default] = prev_d
  end

  test "model_key_for maps served name to entry key" do
    with_self_host_config do
      assert_equal :qwen, Llm::SelfHostAssist.model_key_for('qwen-test')
      assert_nil Llm::SelfHostAssist.model_key_for('unknown')
    end
  end

  test "execute_call raises ResponseError for an unregistered served name" do
    with_self_host_config do
      assist = Llm::SelfHostAssist.new(submission: @submission, comment: @comment, model: 'unknown')
      assert_raises(Llm::Request::ResponseError) do
        assist.send(:execute_call, {messages: []}.to_json)
      end
    end
  end

  test "handle_response writes the comment from a self-host shaped reply (reasoning_content tolerated)" do
    with_self_host_config do
      assist = Llm::SelfHostAssist.new(submission: @submission, comment: @comment, model: 'qwen-test')
      body = {choices: [{message: {content: 'Here is a hint.', reasoning_content: 'thinking...'}}],
              usage: {prompt_tokens: 10, completion_tokens: 5}}.to_json
      assist.send(:handle_response, FakeResponse.new(body))
      @comment.reload
      assert_equal 'ok', @comment.status
      assert_equal 'Here is a hint.', @comment.body
      assert_equal Llm::CommentAssist.assist_cost, @comment.cost
      assert_includes @comment.remark, 'self-host'
      assert_equal 0.0, @comment.llm_cost.to_f
      assert_equal [10, 5], [@comment.prompt_tokens, @comment.completion_tokens]
    end
  end

  test "job resolves the service class" do
    assert_equal Llm::SelfHostAssist, Llm::SelfHostAssistJob.new.send(:service_class)
  end

  test "non-retryable failure marks the comment once, without retries-exhausted wording" do
    with_self_host_config do
      assert_raises(Llm::Request::ResponseError) do
        Llm::SelfHostAssistJob.perform_now(@submission, model: 'unknown', comment: @comment)
      end
      @comment.reload
      assert_equal 'error', @comment.status
      assert_equal 'Assistant Error', @comment.title
      assert_equal 1, @comment.body.scan('Request failed').size
      refute_includes @comment.body, 'retries exhausted'
    end
  end
end
