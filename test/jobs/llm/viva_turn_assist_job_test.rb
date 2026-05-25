require "test_helper"

# Composite end-to-end test for the stuck-turn recovery wiring.
#
# Llm::RequestJob's unit suite already exercises the rescue logic with
# a hand-rolled FakeJob (test/jobs/llm/request_job_test.rb). This file
# closes the loop one layer up: it drives the *real* VivaTurnAssistJob
# through ActiveJob's perform pipeline with a fake faulty service
# swapped in via config, and asserts the placeholder VivaTurn
# transitions from :processing to :error in the database.
#
# This is the closest thing we have to "simulate the LLM API failing
# in production" without actually hitting a live provider.
class Llm::VivaTurnAssistJobTest < ActiveJob::TestCase
  # Stand-in for a real LLM service (Llm::VivaTurnGenieAssist etc.)
  # that always fails. Its full constant name is interpolated into
  # Rails.configuration.llm[:viva_turn_service], which the job
  # resolves via .constantize at perform time.
  class BoomService
    def self.call(**)
      raise StandardError, "simulated LLM 500"
    end
  end

  setup do
    @submission = submissions(:add1_by_john)
    @placeholder = @submission.viva_turns.create!(
      role: :assistant, status: :processing, content: nil
    )
  end

  test "non-retryable LLM failure marks the placeholder turn :error" do
    # Drive the job through its perform method directly (skipping the
    # queue adapter) so the exception path is observable in this test.
    # The behavior under test — perform's rescue branch calling
    # on_retries_exhausted — is identical regardless of how perform
    # was invoked.
    with_viva_turn_service(BoomService.name) do
      assert_raises(StandardError) do
        Llm::VivaTurnAssistJob.new.perform(@submission, turn: @placeholder)
      end
    end

    @placeholder.reload
    assert_predicate @placeholder, :error?,
      "expected the placeholder turn to be flipped to :error after the job's rescue branch fired"
    assert_match(/StandardError|simulated LLM 500/, @placeholder.content.to_s,
      "error content should surface the underlying exception for the UI and the operator")
  end

  test "successful service call leaves the job's :error rescue dormant" do
    # Sanity-check the negative: a service that returns cleanly must
    # NOT mark the turn :error. Guards against accidentally firing
    # on_retries_exhausted on success in some future refactor.
    success_service = Class.new do
      def self.call(submission:, turn:, **)
        turn.update!(status: :ok, content: "ok from fake service")
      end
    end
    stub_const("Llm::VivaTurnAssistJobTest::SuccessService", success_service)

    with_viva_turn_service("Llm::VivaTurnAssistJobTest::SuccessService") do
      Llm::VivaTurnAssistJob.new.perform(@submission, turn: @placeholder)
    end

    @placeholder.reload
    assert_predicate @placeholder, :ok?
    assert_equal "ok from fake service", @placeholder.content
  end

  private

  def with_viva_turn_service(class_name)
    prev = Rails.configuration.llm[:viva_turn_service]
    Rails.configuration.llm[:viva_turn_service] = class_name
    yield
  ensure
    Rails.configuration.llm[:viva_turn_service] = prev
  end

  # Anonymous Class.new objects don't have a name, so they can't be
  # resolved via constantize. We bolt them onto a known constant path
  # for the duration of the test, then unbind.
  def stub_const(path, klass)
    parts = path.split("::")
    name  = parts.pop
    parent = parts.inject(Object) { |o, c| o.const_get(c) }
    parent.const_set(name, klass)
    @stubbed_consts ||= []
    @stubbed_consts << [parent, name]
  end

  teardown do
    Array(@stubbed_consts).each { |parent, name| parent.send(:remove_const, name) if parent.const_defined?(name, false) }
  end
end
