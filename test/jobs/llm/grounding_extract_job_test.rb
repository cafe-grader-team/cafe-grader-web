require "test_helper"

# Mirrors test/jobs/llm/viva_turn_assist_job_test.rb: drives the *real*
# GroundingExtractJob through ActiveJob's perform pipeline with a fake
# service swapped in via config/llm.yml's grounding_extract_service key,
# and asserts the failure/success behavior against the GroundingMaterial
# record (which has no placeholder turn — the draft column itself carries
# the failure state via the "EXTRACTION FAILED:" prefix convention).
class Llm::GroundingExtractJobTest < ActiveJob::TestCase
  class BoomService
    def self.call(**)
      raise StandardError, "simulated LLM 500"
    end
  end

  setup do
    @gm = GroundingMaterial.create!(title: "job test material")
    @gm.files.attach(io: StringIO.new("%PDF-1.4 fake"), filename: "slides.pdf", content_type: "application/pdf")
  end

  test "blank grounding_extract_service falls back to the abstract base, which raises NotImplementedError" do
    with_grounding_extract_service(nil) do
      assert_raises(NotImplementedError) do
        Llm::GroundingExtractJob.new.perform(@gm)
      end
    end
    assert_includes @gm.reload.extraction_draft.to_s, "EXTRACTION FAILED"
  end

  test "non-retryable LLM failure marks extraction_draft with a readable failure note" do
    with_grounding_extract_service(BoomService.name) do
      assert_raises(StandardError) do
        Llm::GroundingExtractJob.new.perform(@gm)
      end
    end

    @gm.reload
    assert_match(/EXTRACTION FAILED.*retries exhausted/, @gm.extraction_draft.to_s)
    assert_match(/StandardError|simulated LLM 500/, @gm.extraction_draft.to_s)
  end

  test "successful service call leaves the job's failure-note rescue dormant" do
    success_service = Class.new do
      def self.call(grounding_material:, **)
        grounding_material.update!(extraction_draft: "ok from fake service")
      end
    end
    stub_const("Llm::GroundingExtractJobTest::SuccessService", success_service)

    with_grounding_extract_service("Llm::GroundingExtractJobTest::SuccessService") do
      Llm::GroundingExtractJob.new.perform(@gm)
    end

    assert_equal "ok from fake service", @gm.reload.extraction_draft
  end

  private

  def with_grounding_extract_service(class_name)
    prev = Rails.configuration.llm[:grounding_extract_service]
    Rails.configuration.llm[:grounding_extract_service] = class_name
    yield
  ensure
    Rails.configuration.llm[:grounding_extract_service] = prev
  end

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
