require 'test_helper'
# Object#stub. Without this, credentials.stub(...) silently no-ops: the call
# falls into EncryptedConfiguration#method_missing, which ignores the block.
require 'minitest/mock'

class Llm::AiGatewayTransportTest < ActiveSupport::TestCase
  FAKE_CONFIG = {
    display_name: 'Test Gateway',
    base_url: 'http://gateway.test',
    completion_path: '/v1/chat/completions',
    models_path: '/v1/models',
    default_model: 'model-a',
    default_models: {viva_turn: 'model-b'},
    models: ['model-a', 'model-b']
  }.freeze

  FakeResponse = Struct.new(:body, :headers)

  # Captures posts without network. Mirrors the house style: hand-rolled
  # fakes over HTTP-stub gems.
  class FakeConnection
    attr_reader :posts
    def initialize(headers: {}) = (@posts = []; @response_headers = headers)
    def post(path)
      req = Struct.new(:headers, :body).new({}, nil)
      yield req
      @posts << [path, req]
      FakeResponse.new('{"choices":[{"message":{"content":"ok"}}]}', @response_headers)
    end
  end

  # Records WARN lines so the "no cost source anywhere" path can be asserted
  # rather than assumed. Swallows every other logger call.
  # NOTE: no respond_to_missing? override. Minitest's #stub calls its
  # replacement when it responds to :call, so a blanket "yes" here would make
  # Rails.stub(:logger, log) install nil instead of this object.
  class CapturingLogger
    attr_reader :warnings
    def initialize = @warnings = []
    def warn(msg = nil) = @warnings << (msg || yield)
    def method_missing(*) = nil
  end

  # Minimal hosts exercising the mixin without domain records. ProbeBase
  # stands in for the assist bases' @model management.
  class ProbeBase
    def initialize(model: nil) = @model = model
    def model = @model
  end

  class AssistProbe < ProbeBase
    include Llm::AiGatewayTransport
    GATEWAY_ROLE = :assist
  end

  class VivaTurnProbe < ProbeBase
    include Llm::AiGatewayTransport
    GATEWAY_ROLE = :viva_turn
  end

  def with_gateway_config(cfg = FAKE_CONFIG)
    prev = Rails.configuration.llm[:ai_gateway]
    Rails.configuration.llm[:ai_gateway] = cfg
    yield
  ensure
    Rails.configuration.llm[:ai_gateway] = prev
  end

  # Drives execute_call against a FakeConnection and hands back [probe, request].
  def post_through(headers: {}, payload: {model: 'model-a', messages: []})
    fake  = FakeConnection.new(headers: headers)
    probe = AssistProbe.new(model: 'model-a')
    Rails.application.credentials.stub(:dig, 'sk-test') do
      Llm::Request.stub(:connection, fake) { probe.send(:execute_call, payload) }
    end
    [probe, fake.posts.first.last]
  end

  test "convert_pdf_parts rewrites PDF image_url parts to file blocks, leaves others" do
    payload = {
      model: 'model-a',
      messages: [
        {role: 'system', content: 'plain string content'},
        {role: 'user', content: [
          {type: 'text', text: 'look at this'},
          {type: 'image_url', image_url: 'data:application/pdf;base64,AAA'},
          {type: 'image_url', image_url: {url: 'data:application/pdf;base64,BBB'}},
          {type: 'image_url', image_url: 'data:image/png;base64,CCC'}
        ]}
      ]
    }
    Llm::AiGatewayTransport.convert_pdf_parts(payload)

    parts = payload[:messages][1][:content]
    assert_equal 'text', parts[0][:type]
    assert_equal({type: 'file', file: {filename: 'document-1.pdf', file_data: 'data:application/pdf;base64,AAA'}}, parts[1])
    assert_equal({type: 'file', file: {filename: 'document-2.pdf', file_data: 'data:application/pdf;base64,BBB'}}, parts[2])
    assert_equal 'image_url', parts[3][:type], 'non-PDF image parts must pass through'
    assert_equal 'plain string content', payload[:messages][0][:content]
  end

  test "execute_call posts transformed payload with bearer auth and captures the cost header" do
    with_gateway_config do
      fake = FakeConnection.new(headers: {'x-litellm-response-cost' => '0.00123'})
      json = {model: 'model-a',
              messages: [{role: 'user', content: [
                {type: 'image_url', image_url: 'data:application/pdf;base64,AAA'}
              ]}]}.to_json
      probe = AssistProbe.new(model: 'model-a')
      Rails.application.credentials.stub(:dig, 'sk-test') do
        Llm::Request.stub(:connection, fake) do
          probe.send(:execute_call, json)
        end
      end

      path, req = fake.posts.first
      assert_equal '/v1/chat/completions', path
      assert_equal 'Bearer sk-test', req.headers['Authorization']
      assert_equal 'file', req.body[:messages][0][:content][0][:type], 'JSON-string payloads must also get the PDF rewrite'
      assert_in_delta 0.00123, probe.send(:compute_cost, {}), 1e-9
    end
  end

  test "gateway_default_model prefers the role override and falls back to default_model" do
    with_gateway_config do
      assert_equal 'model-b', VivaTurnProbe.new(model: 'x').send(:gateway_default_model)
      assert_equal 'model-a', AssistProbe.new(model: 'x').send(:gateway_default_model)
    end
    with_gateway_config(FAKE_CONFIG.except(:default_model, :default_models)) do
      assert_raises(Llm::AiGatewayTransport::ConfigError) do
        AssistProbe.new(model: 'x').send(:gateway_default_model)
      end
    end
  end

  test "initialize backfills the configured default only when the base left @model blank" do
    with_gateway_config do
      assert_equal 'model-a', AssistProbe.new.model
      assert_equal 'model-b', VivaTurnProbe.new.model
      assert_equal 'explicit', AssistProbe.new(model: 'explicit').model
    end
  end

  test "provider_name and gateway_models come from config; unconfigured raises ConfigError" do
    with_gateway_config do
      assert_equal 'Test Gateway', AssistProbe.new.send(:provider_name)
      assert_equal ['model-a', 'model-b'], AssistProbe.gateway_models
    end
    with_gateway_config(nil) do
      assert_raises(Llm::AiGatewayTransport::ConfigError) { AssistProbe.gateway_config }
    end
  end

  test "compute_cost falls back to usage.cost in the body when the header is absent" do
    with_gateway_config do
      probe, = post_through(headers: {})
      assert_in_delta 0.0042, probe.send(:compute_cost, {'cost' => 0.0042}), 1e-9
      assert_in_delta 0.0042, probe.send(:compute_cost, {cost: 0.0042}), 1e-9,
                      'symbol-keyed usage hashes resolve too'
    end
  end

  test "the cost header wins over a body usage.cost, and a header of exactly 0 is authoritative" do
    with_gateway_config do
      probe, = post_through(headers: {'x-litellm-response-cost' => '0.5'})
      assert_in_delta 0.5, probe.send(:compute_cost, {'cost' => 0.0042}), 1e-9

      # A gateway that genuinely charged nothing must NOT fall through to the
      # body or the warning - that is the reason execute_call keeps the raw
      # header string instead of calling .to_f on it.
      zero, = post_through(headers: {'x-litellm-response-cost' => '0'})
      log = CapturingLogger.new
      Rails.stub(:logger, log) do
        assert_in_delta 0.0, zero.send(:compute_cost, {'cost' => 9.99}), 1e-9
      end
      assert_empty log.warnings
    end
  end

  test "no cost source anywhere records 0.0 and warns instead of silently zeroing" do
    with_gateway_config do
      probe, = post_through(headers: {})
      log = CapturingLogger.new
      Rails.stub(:logger, log) do
        assert_in_delta 0.0, probe.send(:compute_cost, {'prompt_tokens' => 10}), 1e-9
      end
      assert_equal 1, log.warnings.size
      assert_match(/no per-call cost/, log.warnings.first)
      assert_match(/model-a/, log.warnings.first, 'the warning must name the model')
    end
  end

  test "usage_in_body opts the request into body cost reporting; off for LiteLLM" do
    with_gateway_config do
      _, req = post_through
      assert_nil req.body[:usage],
                 'a LiteLLM payload must not gain an unknown top-level usage key'
    end

    with_gateway_config(FAKE_CONFIG.merge(usage_in_body: true)) do
      _, req = post_through
      assert_equal({include: true}, req.body[:usage])
    end

    # An explicit usage block from the caller is left alone.
    with_gateway_config(FAKE_CONFIG.merge(usage_in_body: true)) do
      _, req = post_through(payload: {model: 'model-a', messages: [], usage: {include: false}})
      assert_equal({include: false}, req.body[:usage])
    end
  end
end
