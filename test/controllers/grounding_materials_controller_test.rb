require "test_helper"

class GroundingMaterialsControllerTest < ActionDispatch::IntegrationTest
  include ActiveJob::TestHelper

  # sign_in_as(user, password) is defined in test/test_helper.rb (see
  # tags_controller_test.rb). No blanket `setup` sign-in here: the
  # authorization tests below deliberately vary who (if anyone) is signed in.

  # --- Authorization ---

  test "unauthenticated is redirected" do
    get grounding_materials_path
    assert_redirected_to login_main_path
  end

  test "normal user cannot access index" do
    sign_in_as("john", "hello")
    get grounding_materials_path
    assert_redirected_to list_main_path
  end

  # --- Admin happy paths ---

  test "index lists materials" do
    sign_in_as("admin", "admin")
    get grounding_materials_path
    assert_response :success
    assert_select "td", text: "Dijkstra notes"
  end

  test "new renders the form" do
    sign_in_as("admin", "admin")
    get new_grounding_material_path
    assert_response :success
  end

  test "edit renders the form" do
    sign_in_as("admin", "admin")
    get edit_grounding_material_path(grounding_materials(:gm_dijkstra))
    assert_response :success
  end

  test "create with title" do
    sign_in_as("admin", "admin")
    assert_difference "GroundingMaterial.count", 1 do
      post grounding_materials_path, params: { grounding_material: { title: "New ref", body: "b" } }
    end
    assert_redirected_to grounding_materials_path
  end

  test "delete_file purges an attachment" do
    sign_in_as("admin", "admin")
    gm = GroundingMaterial.create!(title: "t")
    gm.files.attach(io: StringIO.new("%PDF"), filename: "a.pdf", content_type: "application/pdf")
    blob_id = gm.files.first.id
    assert_difference -> { gm.files.count }, -1 do
      delete delete_file_grounding_material_path(gm, blob_id: blob_id)
    end
  end

  # --- Extraction (D4) ---

  test "extract sets extraction_requested_at, clears any prior draft, and enqueues the job" do
    sign_in_as("admin", "admin")
    gm = GroundingMaterial.create!(title: "t", extraction_draft: "stale draft")
    gm.files.attach(io: StringIO.new("%PDF"), filename: "a.pdf", content_type: "application/pdf")

    assert_enqueued_with(job: Llm::GroundingExtractJob, args: [gm]) do
      post extract_grounding_material_path(gm)
    end

    gm.reload
    assert gm.extraction_requested_at.present?
    assert_nil gm.extraction_draft
    assert_redirected_to edit_grounding_material_path(gm)
    assert_equal 'Extraction started — refresh this page in a minute or two.', flash[:notice]
  end

  test "extract without an attached file redirects with an alert and does not enqueue" do
    sign_in_as("admin", "admin")
    gm = GroundingMaterial.create!(title: "no files")

    assert_no_enqueued_jobs do
      post extract_grounding_material_path(gm)
    end

    assert_nil gm.reload.extraction_requested_at
    assert_redirected_to edit_grounding_material_path(gm)
    assert_equal 'Attach at least one PDF before extracting.', flash[:alert]
  end

  test "edit view shows the extract button only when a PDF is attached" do
    sign_in_as("admin", "admin")
    gm = GroundingMaterial.create!(title: "no files yet")
    get edit_grounding_material_path(gm)
    assert_response :success
    assert_select "form[action=?]", extract_grounding_material_path(gm), count: 0

    gm.files.attach(io: StringIO.new("%PDF"), filename: "a.pdf", content_type: "application/pdf")
    get edit_grounding_material_path(gm)
    assert_response :success
    assert_select "form[action=?]", extract_grounding_material_path(gm), count: 1
  end

  test "edit view shows the draft panel and in-progress line appropriately" do
    sign_in_as("admin", "admin")
    gm = GroundingMaterial.create!(title: "with draft", extraction_draft: "# Draft text")
    gm.files.attach(io: StringIO.new("%PDF"), filename: "a.pdf", content_type: "application/pdf")
    get edit_grounding_material_path(gm)
    assert_select "pre", text: /Draft text/

    gm.update!(extraction_draft: nil, extraction_requested_at: Time.current)
    get edit_grounding_material_path(gm)
    assert_select "*", text: /Extraction in progress/
  end
end
