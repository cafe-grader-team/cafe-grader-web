require "test_helper"

class LlmQueueAssignmentTest < ActiveSupport::TestCase
  test "viva turn and grade jobs enqueue on the viva queue" do
    assert_equal "viva", Llm::VivaTurnAssistJob.new.queue_name
    assert_equal "viva", Llm::VivaGradeAssistJob.new.queue_name
  end

  test "assist jobs stay on the default queue" do
    assert_equal "default", Llm::AiGatewayAssistJob.new.queue_name
  end
end
