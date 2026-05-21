require "test_helper"

# RequestJob is the abstract base for every LLM job (viva turn, viva grade,
# comment hint). Its perform method has a defensive contract: if the
# underlying service raises a NON-retryable exception, the job must still
# call on_retries_exhausted so the concrete subclass can mark its
# placeholder record as :error — without that, the placeholder is stuck
# in :processing forever and the UI shows an eternal spinner.
#
# Retryable exceptions (Faraday timeouts, deadlocks, AR timeouts) must
# pass through unchanged so retry_on handles them. We assert both paths.
class Llm::RequestJobTest < ActiveJob::TestCase
  # Minimal concrete subclass: records calls to on_retries_exhausted and
  # lets us inject any exception we want via service_class.
  class FakeJob < Llm::RequestJob
    @@exhausted_calls = []

    def self.exhausted_calls
      @@exhausted_calls
    end

    def self.reset!
      @@exhausted_calls = []
    end

    def service_class
      @service_class || raise("set service_class first")
    end

    def initialize(service_class: nil, **)
      super()
      @service_class = service_class
    end

    private

    def on_retries_exhausted(error)
      @@exhausted_calls << [error.class, error.message]
    end
  end

  class BoomService
    def self.call(**) = raise RuntimeError, "kaboom"
  end

  class FaradayTimeoutService
    def self.call(**) = raise Faraday::TimeoutError, "slow"
  end

  setup do
    FakeJob.reset!
  end

  test "non-retryable exception fires on_retries_exhausted before propagating" do
    submission = submissions(:add1_by_admin)
    error = assert_raises(RuntimeError) do
      FakeJob.new(service_class: BoomService).perform(submission, foo: :bar)
    end
    assert_equal "kaboom", error.message
    assert_equal [[RuntimeError, "kaboom"]], FakeJob.exhausted_calls,
      "non-retryable exception should call on_retries_exhausted once"
  end

  test "retryable exception passes through unchanged (does not fire on_retries_exhausted)" do
    submission = submissions(:add1_by_admin)
    assert_raises(Faraday::TimeoutError) do
      FakeJob.new(service_class: FaradayTimeoutService).perform(submission, foo: :bar)
    end
    assert_empty FakeJob.exhausted_calls,
      "retryable exception must defer to retry_on; on_retries_exhausted only runs from RETRY_EXHAUSTED lambda"
  end
end
