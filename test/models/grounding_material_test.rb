require "test_helper"

class GroundingMaterialTest < ActiveSupport::TestCase
  test "requires a title" do
    gm = GroundingMaterial.new(body: "x")
    assert_not gm.valid?
    assert gm.errors[:title].present?
  end

  test "grounding_text wraps body under a heading, nil when blank" do
    assert_nil GroundingMaterial.new(body: "").grounding_text
    gm = GroundingMaterial.new(body: "hello")
    assert_equal "## Grounding Material\n\nhello", gm.grounding_text
  end

  test "estimated_tokens recomputed from body after commit" do
    gm = GroundingMaterial.create!(title: "t", body: "a" * 40)
    assert_equal 10, gm.reload.estimated_tokens # 40 chars / 4
  end

  # D4 send-time rule: file bytes are only ever sent when body is blank, so
  # the estimate must count file bytes ONLY in that case. (files.attach
  # bypasses the after_commit recompute — see GroundingMaterialsController's
  # refresh_estimated_tokens comment — so this asserts compute_estimated_tokens
  # directly, same as the controller does to refresh the persisted column.)
  test "estimated_tokens counts file bytes when body is blank" do
    gm = GroundingMaterial.create!(title: "t")
    gm.files.attach(io: StringIO.new("x" * 4000), filename: "a.pdf", content_type: "application/pdf")
    gm.reload
    assert_equal (4000.0 / GroundingMaterial::BYTES_PER_PROXY_TOKEN).round, gm.compute_estimated_tokens
  end

  # D4 send-time rule: once body is present, the PDF is never re-sent, so its
  # bytes must NOT inflate the estimate — body-only tokens, even with a large
  # file attached.
  test "estimated_tokens counts body only once body is present, ignoring attached file size" do
    gm = GroundingMaterial.create!(title: "t", body: "a" * 40)
    gm.files.attach(io: StringIO.new("x" * 40_000), filename: "a.pdf", content_type: "application/pdf")
    gm.reload
    assert_equal 10, gm.compute_estimated_tokens # 40 chars / 4, file bytes excluded
  end

  test "rejects non-pdf/image files" do
    gm = GroundingMaterial.new(title: "t")
    gm.files.attach(io: StringIO.new("x"), filename: "a.txt", content_type: "text/plain")
    assert_not gm.valid?
    assert gm.errors[:files].present?
  end

  test "has_and_belongs_to_many problems" do
    # prob_viva, not prob_add: prob_add backs submissions(:add1_by_admin),
    # reused by the Llm::VivaTurnAssist / VivaGradeAssist specs with plain-
    # string message assertions that a grounding association would break
    # (see the comment on prob_viva in test/fixtures/problems.yml).
    assert_includes grounding_materials(:gm_dijkstra).problems, problems(:prob_viva)
  end
end
