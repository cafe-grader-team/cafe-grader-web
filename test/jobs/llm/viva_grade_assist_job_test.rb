require "test_helper"

# Failure paths of the grade job's on_retries_exhausted (grade history, spec
# docs/superpowers/specs/2026-09-23-viva-grade-history-design.md): a transport
# error that exhausted its retries never reached the service's handle_error,
# so the job records the failed run itself — and a submission that already
# has a valid grade keeps it.
class Llm::VivaGradeAssistJobTest < ActiveJob::TestCase
  class TimeoutService
    def self.call(**) = raise Faraday::TimeoutError, 'execution expired'
  end

  class BoomService
    def self.call(**) = raise StandardError, 'simulated 500'
  end

  # A real grade service whose provider always answers with a non-grade
  # reply: the re-ask fails too, so Llm::VivaGradeAssist#handle_error runs.
  class NonGradeService < Llm::VivaGradeAssist
    def provider_name = 'scripted'

    def execute_call(_data)
      body = {model: 'scripted', choices: [{message: {content: '{"ask": 1}'}, finish_reason: 'stop'}], usage: {}}.to_json
      Struct.new(:body).new(body)
    end
  end

  def viva_language
    Language.find_or_create_by!(name: 'viva') { |l| l.pretty_name = 'Viva Exam' }
  end

  setup do
    @submission = Submission.create!(user: users(:john), problem: problems(:prob_viva), language: viva_language,
                                     status: :evaluating, submitted_at: Time.zone.now)
  end

  def with_grade_service(class_name)
    prev = Rails.configuration.llm[:viva_grade_service]
    Rails.configuration.llm[:viva_grade_service] = class_name
    yield
  ensure
    Rails.configuration.llm[:viva_grade_service] = prev
  end

  # perform re-raises a retryable error for retry_on; production runs the
  # exhausted hook after the last attempt, so this drives it the same way.
  # A non-retryable error goes through perform's own rescue branch.
  def exhaust(class_name, **job_args)
    job = Llm::VivaGradeAssistJob.new
    with_grade_service(class_name) do
      assert_raises(StandardError) { job.perform(@submission, **job_args) }
    end
    job.send(:on_retries_exhausted, Faraday::TimeoutError.new('execution expired')) if class_name == TimeoutService.name
    job
  end

  test "exhausted transport retries on a first grading record an error run and grader_error" do
    exhaust(TimeoutService.name, model: 'm1', batch_id: 'b1')
    @submission.reload
    assert_equal 'grader_error', @submission.status
    assert_match(/retries exhausted.*TimeoutError/, @submission.grader_comment)
    run = @submission.viva_grades.order(:id).last
    assert_equal 'error', run.superseded_reason
    assert_equal ['m1', 'b1'], [run.llm_model, run.batch_id]
    assert_match(/TimeoutError/, run.error)
    assert_nil @submission.viva_grade
  end

  test "exhausted transport retries over a valid grade record the run and keep the grade" do
    @submission.viva_grades.create!(total_points: 55, graded_at: 1.hour.ago, llm_model: 'old')
    @submission.update!(status: :done, points: 55)
    exhaust(TimeoutService.name)
    @submission.reload
    assert_equal 'done', @submission.status
    assert_equal 55, @submission.points
    assert_equal 55, @submission.viva_grade.total_points
    assert_equal 'error', @submission.viva_grades.order(:id).last.superseded_reason
    assert_equal 2, @submission.viva_grades.count
  end

  test "a non-retryable failure over a valid grade does not add a second error run" do
    problems(:prob_viva).update!(viva_prompt: 'Grade fairly.')
    @submission.viva_grades.create!(total_points: 55, graded_at: 1.hour.ago, llm_model: 'old')
    @submission.update!(status: :done, points: 55)
    exhaust(NonGradeService.name, batch_id: 'b2')
    @submission.reload
    assert_equal 'done', @submission.status
    assert_equal 55, @submission.points
    assert_equal 55, @submission.viva_grade.total_points
    assert_equal 2, @submission.viva_grades.count, 'the service records the failed run once; the job adds none'
    run = @submission.viva_grades.order(:id).last
    assert_equal ['error', 'b2'], [run.superseded_reason, run.batch_id]
    assert_match(/schema check/, run.error)
  end

  test "a non-retryable failure on a first grading still lands in grader_error" do
    exhaust(BoomService.name)
    assert_equal 'grader_error', @submission.reload.status
  end
end
