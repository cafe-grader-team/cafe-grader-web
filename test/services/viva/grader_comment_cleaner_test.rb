require 'test_helper'

class Viva::GraderCommentCleanerTest < ActiveSupport::TestCase
  NARRATIVE = 'Your performance in this viva was outstanding. ' * 5

  def viva_sub(status:, grader_comment:, terminated: false)
    sub = Submission.new(user: users(:john), problem: problems(:prob_viva), language: languages(:Language_c),
                         source: 'viva', submitted_at: 2.hours.ago, number: Submission.count + 1,
                         status: status, points: 80, graded_at: (1.hour.ago unless status == :grader_error),
                         grader_comment: grader_comment, viva_terminated_at: (1.hour.ago if terminated))
    sub.save!(validate: false)
    VivaGrade.create!(submission: sub, total_points: 80, narrative: NARRATIVE)
    sub
  end

  setup do
    @out        = StringIO.new
    @copy       = viva_sub(status: :done, grader_comment: NARRATIVE)
    @terminated = viva_sub(status: :done, grader_comment: "Note: #{NARRATIVE}", terminated: true)
    @already    = viva_sub(status: :done, grader_comment: 'viva')
    @edited     = viva_sub(status: :done, grader_comment: 'hand-edited verdict')
    @errored    = viva_sub(status: :grader_error, grader_comment: "Grader error: #{NARRATIVE}")
  end

  test 'dry run reports everything in scope and changes nothing' do
    counts = Viva::GraderCommentCleaner.new(apply: false, io: @out).run
    assert_equal({rewrite: 2, already: 1, skip: 1}, counts.slice(:rewrite, :already, :skip))
    report = @out.string
    assert_match(/DRY RUN/, report)
    assert_match(/REWRITE\s+##{@copy.id} .*-> 'viva'$/m, report)
    assert_match(/REWRITE\s+##{@terminated.id} .*-> 'viva:terminated'/, report)
    assert_match(/ALREADY\s+##{@already.id}/, report)
    assert_match(/SKIP\s+##{@edited.id}/, report)
    refute_match(/##{@errored.id}\b/, report, 'non-done rows are out of scope')
    assert_equal NARRATIVE, @copy.reload.grader_comment
    assert_equal "Note: #{NARRATIVE}", @terminated.reload.grader_comment
  end

  test 'apply rewrites narrative copies to the marker and leaves everything else alone' do
    Viva::GraderCommentCleaner.new(apply: true, io: @out).run
    assert_equal 'viva',            @copy.reload.grader_comment
    assert_equal 'viva:terminated', @terminated.reload.grader_comment
    assert_equal 'viva',            @already.reload.grader_comment
    assert_equal 'hand-edited verdict', @edited.reload.grader_comment
    assert_equal "Grader error: #{NARRATIVE}", @errored.reload.grader_comment
    assert_equal NARRATIVE, @copy.viva_grade.reload.narrative, 'the narrative itself is never touched'
  end

  test 'apply is idempotent' do
    Viva::GraderCommentCleaner.new(apply: true, io: @out).run
    counts = Viva::GraderCommentCleaner.new(apply: true, io: StringIO.new).run
    assert_equal 0, counts[:rewrite]
    assert_equal 3, counts[:already]
    assert_equal 1, counts[:skip]
  end
end
