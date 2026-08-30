require "test_helper"

class Llm::GroundingExtractAssistTest < ActiveSupport::TestCase
  setup do
    @gm = GroundingMaterial.create!(title: "extract me")
    @gm.files.attach(io: StringIO.new("%PDF-1.4 fake"), filename: "slides.pdf", content_type: "application/pdf")
    @assist = Llm::GroundingExtractAssist.new(grounding_material: @gm)
  end

  test "messages_array is a single user message with instruction text + a PDF part" do
    msgs = @assist.send(:messages_array)
    assert_equal 1, msgs.length
    assert_equal 'user', msgs.first[:role]

    content = msgs.first[:content]
    assert_kind_of Array, content
    text_part = content.find { |p| p[:type] == 'text' }
    pdf_part  = content.find { |p| p[:type] == 'image_url' }

    assert text_part, 'expected an instruction text part'
    assert_includes text_part[:text], 'faithful-but-compact'
    assert pdf_part, 'expected a PDF image_url part'
    assert_includes pdf_part[:image_url], 'data:application/pdf;base64,'
  end

  test "messages_array includes one PDF part per attached file" do
    @gm.files.attach(io: StringIO.new("%PDF-1.4 fake 2"), filename: "more.pdf", content_type: "application/pdf")
    fresh = Llm::GroundingExtractAssist.new(grounding_material: @gm.reload)
    content = fresh.send(:messages_array).first[:content]
    pdf_parts = content.select { |p| p[:type] == 'image_url' }
    assert_equal 2, pdf_parts.length
  end

  test "prepare_data uses the generous MAX_TOKENS constant" do
    data = @assist.send(:prepare_data)
    assert_equal Llm::GroundingExtractAssist::MAX_TOKENS, data[:max_tokens]
  end

  def response_body(text)
    {choices: [{message: {content: text}}], model: 'stub', usage: {prompt_tokens: 1, completion_tokens: 1}}.to_json
  end

  test "handle_response writes the draft into extraction_draft and never touches body" do
    @assist.send(:handle_response, Struct.new(:body).new(response_body("# Extracted\n\nSome markdown.")))
    @gm.reload
    assert_equal "# Extracted\n\nSome markdown.", @gm.extraction_draft
    assert_nil @gm.body
  end

  test "handle_response strips surrounding whitespace" do
    @assist.send(:handle_response, Struct.new(:body).new(response_body("\n\n  # Extracted  \n\n")))
    assert_equal "# Extracted", @gm.reload.extraction_draft
  end

  test "handle_response raises ResponseError when content is missing" do
    assert_raises(Llm::Request::ResponseError) do
      @assist.send(:handle_response, Struct.new(:body).new('{"choices":[{"message":{}}]}'))
    end
    refute @gm.reload.extraction_draft.present?, 'a raised ResponseError should not have written a draft'
  end

  test "handle_error leaves a readable EXTRACTION FAILED note in extraction_draft, never in body" do
    @assist.instance_variable_set(:@error, "boom: simulated failure")
    @assist.send(:handle_error)
    @gm.reload
    assert_includes @gm.extraction_draft, "EXTRACTION FAILED"
    assert_includes @gm.extraction_draft, "boom: simulated failure"
    assert_nil @gm.body
  end

  test "execute_call raises NotImplementedError on the abstract base" do
    assert_raises(NotImplementedError) do
      @assist.send(:execute_call, {})
    end
  end
end
