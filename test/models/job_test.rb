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
end
