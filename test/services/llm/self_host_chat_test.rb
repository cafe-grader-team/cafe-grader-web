require 'test_helper'

class Llm::SelfHostChatTest < ActiveSupport::TestCase
  FAKE_MODELS = {
    qwen:  {base_url: 'http://dgx.test:8000', completion_path: '/v1/chat/completions', model: 'qwen-test', max_tokens: 100},
    gemma: {base_url: 'http://a100.test:8000', completion_path: '/v1/chat/completions', model: 'gemma-test', max_tokens: 8192}
  }.freeze

  FakeResponse = Struct.new(:body)

  # Captures post/get without network. Mirrors the house style: hand-rolled
  # fakes over HTTP-stub gems.
  class FakeConnection
    attr_reader :posts
    def initialize(get_body: nil) = (@posts = []; @get_body = get_body)
    def post(path)
      req = Struct.new(:headers, :body).new({}, nil)
      yield req
      @posts << [path, req]
      FakeResponse.new('{"choices":[{"message":{"content":"ok"}}]}')
    end
    def get(_path) = FakeResponse.new(@get_body)
  end

  def with_self_host_config(models: FAKE_MODELS, default: 'qwen')
    prev_m = Rails.configuration.llm[:self_hosted_models]
    prev_d = Rails.configuration.llm[:self_hosted_default]
    Rails.configuration.llm[:self_hosted_models] = models
    Rails.configuration.llm[:self_hosted_default] = default
    yield
  ensure
    Rails.configuration.llm[:self_hosted_models] = prev_m
    Rails.configuration.llm[:self_hosted_default] = prev_d
  end

  def chat_with_fake(model_key: nil, get_body: nil)
    chat = Llm::SelfHostChat.new(model_key: model_key)
    fake = FakeConnection.new(get_body: get_body)
    chat.instance_variable_set(:@connection, fake)
    [chat, fake]
  end

  test "resolves default key, explicit key, and rejects unknown key" do
    with_self_host_config do
      assert_equal 'qwen-test', Llm::SelfHostChat.new.model_name
      assert_equal 'gemma-test', Llm::SelfHostChat.new(model_key: 'gemma').model_name
      assert_raises(Llm::SelfHostChat::ConfigError) { Llm::SelfHostChat.new(model_key: 'gpt4') }
    end
  end

  test "raises ConfigError when unconfigured" do
    with_self_host_config(models: nil, default: nil) do
      assert_raises(Llm::SelfHostChat::ConfigError) { Llm::SelfHostChat.new }
    end
  end

  test "chat payload: no repetition_penalty, max_tokens floor, stream false" do
    with_self_host_config do
      chat, fake = chat_with_fake
      chat.chat([{role: 'user', content: 'hi'}])
      path, req = fake.posts.first
      assert_equal '/v1/chat/completions', path
      payload = JSON.parse(req.body)
      assert_equal 'qwen-test', payload['model']
      assert_equal 4096, payload['max_tokens'], 'configured 100 must be floored to 4096'
      assert_equal false, payload['stream']
      refute payload.key?('repetition_penalty')
      assert_equal 'application/json', req.headers['Content-Type']
    end
  end

  test "max_tokens above the floor is respected" do
    with_self_host_config do
      chat, fake = chat_with_fake(model_key: 'gemma')
      chat.chat([])
      _path, req = fake.posts.first
      assert_equal 8192, JSON.parse(req.body)['max_tokens']
    end
  end

  test "connection uses the 600s self-host read timeout; factory default stays 300" do
    with_self_host_config do
      opts = Llm::SelfHostChat.new.send(:connection).options
      assert_equal 600, opts.read_timeout
      assert_equal 600, opts.timeout
      assert_equal 300, Llm::Request.connection('http://x.test').options.read_timeout
    end
  end

  test "verify_model! passes on match and raises on mismatch" do
    with_self_host_config do
      chat, _ = chat_with_fake(get_body: '{"data":[{"id":"qwen-test"}]}')
      assert chat.verify_model!
      chat2, _ = chat_with_fake(get_body: '{"data":[{"id":"something-else"}]}')
      assert_raises(Llm::SelfHostChat::ConfigError) { chat2.verify_model! }
    end
  end
end
