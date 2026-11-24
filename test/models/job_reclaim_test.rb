require 'test_helper'

# Job.reclaim_orphaned! — returning judge jobs stranded in :process by a
# grader that died mid-job. A job enters :process in take_oldest_waiting_job
# and leaves it only through Job#report, so a grader killed in between (OOM,
# kill -9, host reboot, the watchdog's stalled-KILL branch) left the job —
# and its submission's whole grading chain — stuck forever. Surfaced
# 2026-08-29 hardening the watchdog; the prod-copy dev database carried 126
# such rows, the oldest 564 days old.
class JobReclaimTest < ActiveSupport::TestCase
  setup do
    @gp = GraderProcess.create!(worker_id: 1, box_id: 3, enabled: true)
    @other_gp = GraderProcess.create!(worker_id: 1, box_id: 4, enabled: true)
    @sub = submissions(:add1_by_admin)
    @sub.update_columns(status: Submission.statuses[:evaluating])
  end

  # Claim a job the way take_oldest_waiting_job does, then backdate it to
  # simulate the grader having died `age` ago without reporting.
  def orphan(age: 10.minutes, grader: @gp, arg: @sub.id, result: nil, job_type: :evaluate)
    job = Job.create!(job_type: job_type, arg: arg, priority: 0,
                      status: :process, grader_process: grader, result: result)
    job.update_columns(updated_at: age.ago)
    job
  end

  # --- the core case ------------------------------------------------------

  test 'a job whose grader died returns to the queue and is picked up again' do
    job = orphan
    Job.where.not(id: job.id).delete_all # so the queue has exactly one candidate

    assert_equal({requeued: 1, abandoned: 0}, Job.reclaim_orphaned!(grader_process_ids: [@gp.id]))
    assert job.reload.wait?, 'the orphaned job should be waiting again'
    assert_match(/reclaimed/, job.result)
    assert_match(/worker 1 box 3/, job.result, 'the message should name the grader that lost it')

    assert_equal job, Job.take_oldest_waiting_job(@gp), 'a grader must be able to claim it again'
    assert job.reload.process?
  end

  test 'the submission is left mid-flight so the requeued job can finish it' do
    orphan
    Job.reclaim_orphaned!(grader_process_ids: [@gp.id])
    assert @sub.reload.evaluating?, 'requeueing must not touch the submission — the retry will grade it'
  end

  # --- what it must not touch ---------------------------------------------

  test 'a job claimed moments ago is left alone' do
    job = orphan(age: 5.seconds)
    assert_equal({requeued: 0, abandoned: 0}, Job.reclaim_orphaned!(grader_process_ids: [@gp.id]))
    assert job.reload.process?, 'the older_than floor closes the gap between the ps snapshot and this query'
  end

  test 'only the grader processes it is given are swept' do
    mine = orphan(grader: @gp)
    theirs = orphan(grader: @other_gp)

    Job.reclaim_orphaned!(grader_process_ids: [@gp.id])
    assert mine.reload.wait?
    assert theirs.reload.process?, "another host's box is not this watchdog's to judge"
  end

  test 'a fleet-wide sweep with no id list reaches every grader' do
    mine = orphan(grader: @gp)
    theirs = orphan(grader: @other_gp)

    Job.reclaim_orphaned!(older_than: 1.minute)
    assert mine.reload.wait?
    assert theirs.reload.wait?
  end

  test 'jobs that are not in :process are never considered' do
    %i[wait success error].each do |status|
      job = orphan
      job.update_columns(status: Job.statuses[status], updated_at: 10.minutes.ago)
      Job.reclaim_orphaned!(older_than: 1.minute)
      assert_equal status.to_s, job.reload.status
    end
  end

  # --- dead-lettering -----------------------------------------------------

  test 'a job whose submission already finished is dropped, and the grade left alone' do
    @sub.update_columns(status: Submission.statuses[:done], points: 90,
                        grader_comment: 'PPPPP')
    job = orphan

    assert_equal({requeued: 0, abandoned: 1}, Job.reclaim_orphaned!(older_than: 1.minute))
    assert job.reload.error?, 'rerunning would overwrite a settled grade'
    assert_match(/already done/, job.result)

    @sub.reload
    assert @sub.done?
    assert_equal 90, @sub.points
    assert_equal 'PPPPP', @sub.grader_comment
  end

  test 'a job stuck past MAX_RECLAIM_AGE is dropped and its submission flagged' do
    job = orphan(age: Job::MAX_RECLAIM_AGE + 1.hour)

    assert_equal({requeued: 0, abandoned: 1}, Job.reclaim_orphaned!(older_than: 1.minute))
    assert job.reload.error?
    assert_match(/stuck since/, job.result)

    @sub.reload
    assert @sub.grader_error?, 'the student must stop seeing "evaluating" forever'
    assert_equal 0, @sub.points
    assert_match(/rejudge/i, @sub.grader_comment)
  end

  test 'a job whose submission is gone is dropped without raising' do
    job = orphan(arg: 0)
    assert_equal({requeued: 0, abandoned: 1}, Job.reclaim_orphaned!(older_than: 1.minute))
    assert job.reload.error?
    assert_match(/no longer exists/, job.result)
  end

  # --- the attempt budget -------------------------------------------------

  test 'a job that keeps killing its grader is dropped instead of requeued forever' do
    job = orphan
    (1...Job::RECLAIM_ATTEMPT_LIMIT).each do |n|
      Job.reclaim_orphaned!(older_than: 1.minute)
      assert job.reload.wait?, "attempt #{n} should still requeue"
      assert_match(/retry #{n}:/, job.result)
      job.update_columns(status: Job.statuses[:process], updated_at: 10.minutes.ago)
    end

    Job.reclaim_orphaned!(older_than: 1.minute)
    assert job.reload.error?, "attempt #{Job::RECLAIM_ATTEMPT_LIMIT} must give up"
    assert_match(/#{Job::RECLAIM_ATTEMPT_LIMIT} times/, job.result)
    assert @sub.reload.grader_error?
  end

  test 'the budget is shared with the in-grader retry counter' do
    # check_and_run_job writes the same "retry N" prefix when it catches an
    # exception; a job that has already burned attempts there must not get a
    # fresh allowance just because it died a different way this time.
    job = orphan(result: 'retry 2: RuntimeError: boom')
    Job.reclaim_orphaned!(older_than: 1.minute)
    assert job.reload.error?
    refute job.wait?
  end
end
