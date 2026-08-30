require "test_helper"

class VivaGroundingAssemblyTest < ActiveSupport::TestCase
  test "encode_pdf_part returns nil for nil input and for an attached non-pdf file" do
    assert_nil Llm::Request.encode_pdf_part(nil)

    # A real, attached, non-PDF ActiveStorage::Attachment. GroundingMaterial validation
    # is PDF-only (image/png is no longer a valid upload), so this attaches directly
    # to bypass that validation purely to exercise the encoder's own defense-in-depth
    # content_type guard on the raw-attachment path (no #attached? method).
    gm = GroundingMaterial.create!(title: "t")
    gm.files.attach(io: StringIO.new("fakepng"), filename: "a.png", content_type: "image/png")
    assert_nil Llm::Request.encode_pdf_part(gm.files.first)
  end

  # D4 send-time rule, model-level unit coverage: no body -> file parts still
  # sent (today's/existing behavior, pinned).
  test "grounding_file_parts encodes attached pdf as image_url when body is blank" do
    gm = GroundingMaterial.create!(title: "t")
    gm.files.attach(io: StringIO.new("%PDF-1.4 fake"), filename: "a.pdf", content_type: "application/pdf")
    parts = gm.grounding_file_parts
    assert_equal 1, parts.length
    assert_equal "image_url", parts.first[:type]
    assert parts.first[:image_url].start_with?("data:application/pdf;base64,")
  end

  # D4 send-time rule, model-level unit coverage: once body is present, the
  # PDF is redundant at send time and grounding_file_parts must skip it.
  test "grounding_file_parts returns no parts once body is present, even with files attached" do
    gm = GroundingMaterial.create!(title: "t", body: "Shortest paths and priority queues.")
    gm.files.attach(io: StringIO.new("%PDF-1.4 fake"), filename: "a.pdf", content_type: "application/pdf")
    assert_equal [], gm.grounding_file_parts
  end

  # D4: material WITH body -> its file parts must be absent from BOTH the
  # viva turn's first user message and the grade scenario content, while its
  # body text is still present (system prompt for grading; user content part
  # for the turn side).
  test "material with a saved body: PDF excluded from both the turn's first user message and the grade scenario content" do
    submission = submissions(:add1_by_admin)
    submission.viva_turns.destroy_all
    placeholder = submission.viva_turns.create!(role: :assistant, status: :processing)

    problem = submission.problem
    problem.update_columns(description: "Scenario A")
    problem.update!(viva_prompt: "You are a viva interviewer.")

    gm = grounding_materials(:gm_dijkstra) # fixture already has a body
    problem.grounding_materials << gm unless problem.grounding_materials.include?(gm)
    gm.files.attach(io: StringIO.new("%PDF-1.4 dijkstra"), filename: "dijkstra.pdf", content_type: "application/pdf")

    turn_msgs = Llm::VivaTurnAssist.new(submission: submission, turn: placeholder).send(:messages_array)
    turn_user_content = turn_msgs[1][:content]
    assert_kind_of Array, turn_user_content, "expected a content-part array once grounding text is attached"
    assert turn_user_content.any? { |p| p[:type] == "text" && p[:text].include?(gm.body) },
      "grounding body text should be present in the first user message"
    refute turn_user_content.any? { |p| p[:type] == "image_url" },
      "material has a saved body — its PDF must not be re-sent on the turn side"

    submission.viva_turns.where.not(id: placeholder.id).destroy_all
    placeholder.update!(status: :ok, content: "first question")
    submission.viva_turns.create!(role: :student, status: :ok, content: "my answer")

    grade_msgs = Llm::VivaGradeAssist.new(submission: submission).send(:messages_array)
    system_msg = grade_msgs.find { |m| m[:role] == "system" }
    assert_includes system_msg[:content], gm.body, "grounding body text should be embedded in the grader's system prompt"

    user_parts = grade_msgs.select { |m| m[:role] == "user" }.flat_map { |m| Array(m[:content]) }
    refute user_parts.any? { |c| c.is_a?(Hash) && c[:type] == "image_url" },
      "material has a saved body — its PDF must not be re-sent on the grade side either"
  end

  # D4: material WITHOUT body -> file parts still present on both send
  # paths (existing/today's behavior, pinned).
  test "material without a body: PDF still sent on both the turn and grade side" do
    submission = submissions(:add1_by_admin)
    submission.viva_turns.destroy_all
    placeholder = submission.viva_turns.create!(role: :assistant, status: :processing)

    problem = submission.problem
    problem.update_columns(description: "Scenario A")
    problem.update!(viva_prompt: "You are a viva interviewer.")

    gm = grounding_materials(:gm_empty)
    assert gm.body.blank?, "fixture must have no body for this case"
    problem.grounding_materials << gm unless problem.grounding_materials.include?(gm)
    gm.files.attach(io: StringIO.new("%PDF-1.4 empty"), filename: "empty.pdf", content_type: "application/pdf")

    turn_msgs = Llm::VivaTurnAssist.new(submission: submission, turn: placeholder).send(:messages_array)
    turn_user_content = turn_msgs[1][:content]
    assert_kind_of Array, turn_user_content
    assert turn_user_content.any? { |p| p[:type] == "image_url" }, "no-body material should still send its PDF on the turn side"
    refute turn_user_content.any? { |p| p[:type] == "text" && p[:text].include?("Grounding Material") },
      "no body means no grounding text block"

    submission.viva_turns.where.not(id: placeholder.id).destroy_all
    placeholder.update!(status: :ok, content: "first question")
    submission.viva_turns.create!(role: :student, status: :ok, content: "my answer")

    grade_msgs = Llm::VivaGradeAssist.new(submission: submission).send(:messages_array)
    user_parts = grade_msgs.select { |m| m[:role] == "user" }.flat_map { |m| Array(m[:content]) }
    assert user_parts.any? { |c| c.is_a?(Hash) && c[:type] == "image_url" },
      "no-body material should still send its PDF on the grade side"
  end

  # D4: one problem with BOTH kinds attached -> mixed correctly, per material.
  test "problem with both a body material and a file-only material: mixed correctly on both send paths" do
    submission = submissions(:add1_by_admin)
    submission.viva_turns.destroy_all
    placeholder = submission.viva_turns.create!(role: :assistant, status: :processing)

    problem = submission.problem
    problem.update_columns(description: "Scenario A")
    problem.update!(viva_prompt: "You are a viva interviewer.")

    with_body = grounding_materials(:gm_dijkstra)
    with_body.files.attach(io: StringIO.new("%PDF-1.4 dijkstra"), filename: "dijkstra.pdf", content_type: "application/pdf")
    without_body = grounding_materials(:gm_empty)
    without_body.files.attach(io: StringIO.new("%PDF-1.4 empty"), filename: "empty.pdf", content_type: "application/pdf")

    problem.grounding_materials << with_body unless problem.grounding_materials.include?(with_body)
    problem.grounding_materials << without_body unless problem.grounding_materials.include?(without_body)

    turn_msgs = Llm::VivaTurnAssist.new(submission: submission, turn: placeholder).send(:messages_array)
    turn_user_content = turn_msgs[1][:content]
    assert turn_user_content.any? { |p| p[:type] == "text" && p[:text].include?(with_body.body) },
      "body text of the with-body material should be present"
    image_parts = turn_user_content.select { |p| p[:type] == "image_url" }
    assert_equal 1, image_parts.length, "only the file-only material's PDF should be sent on the turn side"

    submission.viva_turns.where.not(id: placeholder.id).destroy_all
    placeholder.update!(status: :ok, content: "first question")
    submission.viva_turns.create!(role: :student, status: :ok, content: "my answer")

    grade_msgs = Llm::VivaGradeAssist.new(submission: submission).send(:messages_array)
    system_msg = grade_msgs.find { |m| m[:role] == "system" }
    assert_includes system_msg[:content], with_body.body

    user_image_parts = grade_msgs.select { |m| m[:role] == "user" }.flat_map { |m| Array(m[:content]) }
                                  .select { |c| c.is_a?(Hash) && c[:type] == "image_url" }
    assert_equal 1, user_image_parts.length, "only the file-only material's PDF should be sent on the grade side too"
  end
end
