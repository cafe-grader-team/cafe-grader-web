require "test_helper"

class JobTest < ActiveSupport::TestCase
  # --- Enums ---

  test "status enum values" do
    assert jobs(:job_waiting).wait?
    assert jobs(:job_processing).process?
    assert jobs(:job_success).success?
    assert jobs(:job_error).error?
  end

  test "job_type enum values" do
    job = Job.new(job_type: :compile)
    assert job.jt_compile?
  end

  # --- Scopes ---

  test "oldest_waiting returns only waiting jobs" do
    waiting = Job.oldest_waiting
    assert waiting.all?(&:wait?)
    assert_includes waiting, jobs(:job_waiting)
    assert_not_includes waiting, jobs(:job_success)
  end

  test "finished returns success and error jobs" do
    finished = Job.finished
    assert_includes finished, jobs(:job_success)
    assert_includes finished, jobs(:job_error)
    assert_not_includes finished, jobs(:job_waiting)
  end

  # --- Class methods ---

  test "add_compiling_job creates a compile job" do
    sub = submissions(:add1_by_admin)
    ds = datasets(:ds_add)
    assert_difference "Job.count" do
      Job.add_compiling_job(sub, ds, 0)
    end
    job = Job.last
    assert job.jt_compile?
    assert_equal sub.id, job.arg
  end

  test "add_compiling_job raises without dataset" do
    sub = submissions(:add1_by_admin)
    assert_raises(GraderError) do
      Job.add_compiling_job(sub, nil, 0)
    end
  end

  test "has_waiting_job returns true when waiting jobs exist" do
    assert Job.has_waiting_job
  end

  test "clean_old_job removes old finished jobs" do
    jobs(:job_success).update(updated_at: 2.days.ago)
    assert_difference "Job.count", -1 do
      Job.clean_old_job(1.day)
    end
  end

  test "clean_old_job keeps error jobs for 30 days, then removes them" do
    jobs(:job_error).update(updated_at: 29.days.ago)
    assert_no_difference "Job.count" do
      Job.clean_old_job(1.day)
    end
    jobs(:job_error).update(updated_at: 31.days.ago)
    assert_difference "Job.count", -1 do
      Job.clean_old_job(1.day)
    end
  end

  test "clean_old_job never touches waiting or processing jobs" do
    Job.where(status: [:wait, :process]).update_all(updated_at: 90.days.ago)
    assert_no_difference "Job.where(status: [:wait, :process]).count" do
      Job.clean_old_job(1.day)
    end
  end

  test "clean_old_job returns the number of rows removed" do
    jobs(:job_success).update(updated_at: 2.days.ago)
    jobs(:job_error).update(updated_at: 31.days.ago)
    assert_equal 2, Job.clean_old_job(1.day)
  end

  # --- Chains and Retry ---

  test "chain_id is the compile job's own id, and the parent's for its evaluate and score jobs" do
    compile = Job.create!(job_type: :compile, arg: 1)
    assert_equal compile.id, compile.chain_id
    assert_equal compile.id, Job.new(job_type: :evaluate, parent_job_id: compile.id).chain_id
    assert_equal compile.id, Job.new(job_type: :score, parent_job_id: compile.id).chain_id
  end

  test "split_retryable skips the error row of a submission graded since, even with no newer rows left" do
    sub = submissions(:add1_by_admin)
    compile = Job.create!(job_type: :compile, arg: sub.id, status: :success)
    failed = Job.create!(job_type: :evaluate, arg: sub.id, parent_job_id: compile.id, status: :error)

    sub.update!(status: :grader_error)
    assert_equal [[failed], []], Job.split_retryable([failed])

    sub.update!(status: :done) # a later chain finished; its rows were cleaned away
    assert_equal [[], [failed]], Job.split_retryable([failed])
  end

  test "split_retryable skips the error row of a deleted submission" do
    failed = Job.create!(job_type: :compile, arg: 0, status: :error)
    assert_equal [[], [failed]], Job.split_retryable([failed])
  end

  # --- Rejudge: supersede and chain check ---

  test "a rejudge errors the submission's waiting and processing jobs and starts a new chain" do
    sub = submissions(:add1_by_admin)
    compile = Job.create!(job_type: :compile, arg: sub.id, status: :success)
    waiting = Job.create!(job_type: :evaluate, arg: sub.id, parent_job_id: compile.id, status: :wait)
    running = Job.create!(job_type: :evaluate, arg: sub.id, parent_job_id: compile.id, status: :process)
    other = Job.create!(job_type: :compile, arg: submissions(:add1_by_john).id, status: :wait)

    sub.add_judge_job(datasets(:ds_add))

    [waiting, running].each do |job|
      assert_equal 'error', job.reload.status
      assert_equal 'superseded by rejudge', job.result
    end
    assert_equal 'success', compile.reload.status, 'finished rows are history, left alone'
    assert_equal 'wait', other.reload.status, 'another submission is untouched'
    new_compile = Job.where(arg: sub.id, job_type: :compile).order(:id).last
    assert_equal 'wait', new_compile.status
    assert_not Job.chain_current?(sub.id, compile.id)
    assert Job.chain_current?(sub.id, new_compile.id)
  end

  test "chain_current? sees a newer chain through its evaluate rows after its compile row is cleaned" do
    sub = submissions(:add1_by_admin)
    old_compile = Job.create!(job_type: :compile, arg: sub.id, status: :success)
    new_compile = Job.create!(job_type: :compile, arg: sub.id, status: :success)
    Job.create!(job_type: :evaluate, arg: sub.id, parent_job_id: new_compile.id, status: :error)
    new_compile.delete

    assert_not Job.chain_current?(sub.id, old_compile.id)
    assert Job.chain_current?(sub.id, nil), 'a row with no chain runs as before'
  end

  test "jobs carries the arg index that supersede! and chain_current? look up by" do
    assert ActiveRecord::Base.connection.index_exists?(:jobs, :arg, name: "index_jobs_on_arg")
  end

  # The judge polls and claims on `status` many times a second; without this
  # index every poll is a full scan and every claim locks the whole table
  # (see the 2026-09-08 migration). Guard against it being dropped.
  test "jobs carries the status/priority/id index the judge poll relies on" do
    assert ActiveRecord::Base.connection.index_exists?(:jobs, [:status, :priority, :id], name: "index_jobs_on_status_priority_id"),
      "index_jobs_on_status_priority_id is missing from jobs"
  end
end
