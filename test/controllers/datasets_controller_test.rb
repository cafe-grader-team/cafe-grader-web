require "test_helper"

class DatasetsControllerTest < ActionDispatch::IntegrationTest
  # `viva` Language isn't in fixtures — find_or_create_by! so this works
  # whether or not another test already seeded it within this run.
  def viva_language
    Language.find_or_create_by!(name: "viva") { |l| l.pretty_name = "Viva Exam" }
  end

  test "bulk rejudge on a mixed dataset skips viva submissions" do
    sign_in_as("admin", "admin")

    problem = problems(:prob_viva)
    dataset = Dataset.create!(problem: problem, name: "VivaMixedDS",
                               time_limit: 1.0, memory_limit: 256,
                               score_type: 0, evaluation_type: 0)

    viva_sub = Submission.create!(user: users(:john), problem: problem, language: viva_language,
                                   status: :done, points: 100, grader_comment: "viva-graded",
                                   submitted_at: Time.zone.now)

    normal_sub = Submission.create!(user: users(:james), problem: problem, language: languages(:Language_c),
                                     source: "int main(){}", status: :done, points: 50,
                                     grader_comment: "P-", submitted_at: Time.zone.now)

    assert_difference "Job.count", 1 do
      post rejudge_dataset_path(dataset)
    end
    assert_response :success

    viva_sub.reload
    assert_equal 100, viva_sub.points.to_i
    assert_equal "viva-graded", viva_sub.grader_comment
    assert_not Job.exists?(arg: viva_sub.id)

    normal_sub.reload
    assert_nil normal_sub.points
    assert_nil normal_sub.grader_comment
    assert Job.exists?(arg: normal_sub.id)
  end
end
