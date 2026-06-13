class Job < ApplicationRecord
  enum :status, {wait: 0, process: 1, success: 2, error: 3}
  enum :job_type, {preprocess: 0, compile: 1, evaluate: 2, score: 3}, prefix: :jt

  scope :oldest_waiting, -> { where(status: :wait) }
  scope :finished, -> { where(status: [:success, :error]) }


  belongs_to :grader_process, optional: true

  # result should be EngineResponse::Result
  def report(result)
    update(status: result.status, result: result.result_description)
  end

  def to_text
    "Job #{id} type: #{job_type}, arg: #{arg}"
  end

  #
  # ---- class method
  #

  def self.add_grade_submission_job(submission, dataset, priority)
    # just add normal compile job
    self.add_compiling_job(submission, dataset, priority)
  end

  def self.add_compiling_job(submission, dataset, priority)
    raise GraderError.new("Sub ##{submission.id} does not have live dataset",
                          submission_id: submission.id) unless dataset
    Job.create(parent_job_id: nil,
               job_type: :compile,
               arg: submission.id,
               priority: priority,
               param: {dataset_id: dataset.id}.to_json)
  end

  def self.add_evaluation_jobs(submission, dataset, parent_job_id = nil, priority = 0)
    raise GraderError.new("Sub ##{submission.id} cannot find dataset #{dataset.id}",
                          submission_id: submission.id) unless dataset
    dataset.testcases.each do |testcase|
      Job.create(parent_job_id: parent_job_id,
                 job_type: :evaluate,
                 arg: submission.id,
                 priority: priority,
                 param: {testcase_id: testcase.id}.to_json)
    end
  end

  def self.add_scoring_job(submission, dataset, parent_job_id = nil, priority = 0)
    Job.create(parent_job_id: parent_job_id,
               job_type: :score,
               arg: submission.id,
               priority: priority,
               param: {dataset_id: dataset.id}.to_json)
  end

  def self.has_waiting_job(job_type = nil)
    q = Job.where(status: :wait)
    q = q.where(job_type: job_type) unless job_type.nil?
    return q.exists?
  end

  # fetch jobs from the queue, only for given job_type, if given
  def self.take_oldest_waiting_job(grader_process, job_type = nil)
    job = nil
    Job.transaction do
      # pick non-locked oldest_waiting
      # https://dev.mysql.com/doc/refman/8.0/en/innodb-locking-reads.html#innodb-locking-reads-nowait-skip-locked
      jobs = Job.lock("FOR UPDATE SKIP LOCKED").oldest_waiting
      jobs = jobs.where(job_type: job_type) unless job_type.nil?
      job = jobs.order('priority DESC, id ASC').first

      if job
        job.update(status: :process, grader_process: grader_process)
      end
    end
    return job
  end

  # check if all evaluation with the same parent of *job* are all finish
  def self.all_evaluate_job_complete(job)
    Job.where(parent_job_id: job.parent_job_id, job_type: :evaluate).where.not(status: :success).count == 0
  end

  # delete successful jobs older than x (errors are kept until admin clears them)
  def self.clean_old_job(x = 1.day)
    Job.where(status: :success).where('updated_at < ?', Time.zone.now - x).delete_all
  end
end
