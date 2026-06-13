class GradersController < ApplicationController
  before_action :set_problem, only: [:edit_job_type, :set_enabled, :update
                                    ]

  before_action :admin_authorization

  def index
    @graders = GraderProcess.all
    @wait_count = Job.where(status: :wait).group(:job_type).count
    @error_count = Job.where(status: :error).count
    @error_jobs = Job.where(status: :error).order(updated_at: :desc).limit(50) if @error_count > 0

    # "External signals" — surfaced here so admins have a single
    # landing page for "anything broken right now?" The deep-links
    # point at the existing specialized pages.
    @sq_failed_count  = SolidQueue::Job.failed.count
    @stuck_viva_count = VivaTurn.stuck.count

    @submission_limit = [20, 100, 500].include?(params[:limit].to_i) ? params[:limit].to_i : 20
    @submission = Submission.order("id desc").limit(@submission_limit).includes(:user, :problem)
    @backlog_submission = Submission.where('graded_at is null').includes(:user, :problem)

    @wait_compile_job_count = Job.where(job_type: :compile, status: :wait).count
    @wait_eval_job_count = Job.where(job_type: :evaluate, status: :wait).count
  end

  def stuck_viva_turns
    @turns = VivaTurn.stuck
                     .includes(submission: %i[user problem])
                     .order("viva_turns.updated_at desc")
  end

  def edit_job_type
    if @grader.job_type.blank?
      @job_type = Job.job_types.keys
    else
      @job_type = @grader.job_type.split
    end
  end

  def update
    result = []
    Job.job_types.each do |k, v|
      param_name = "jt-#{k}"
      result << k if params[param_name] == 'on'
    end
    @grader.update(job_type: result.join(' '))

    # i don't know why but when submit is made via form's input{type: 'submit'}, we don't need to call turbo_stream.replace
    # see "set_enabled" which is acticated by form's button element. There, we NEED explicit call to turbo_stream.replace
    render partial: 'grader', locals: {grader: @grader}
    # render turbo_stream: turbo_stream.replace( helpers.dom_id(@grader), partial: 'grader', locals: {grader: @grader})
  end

  def set_enabled
    @grader.update(enabled: params[:enabled])

    # render partial: 'grader', locals: {grader: @grader}
    render turbo_stream: turbo_stream.replace(helpers.dom_id(@grader), partial: 'grader', locals: {grader: @grader})
  end

  def retry_error_job
    job = Job.find(params[:job_id])
    job.update(status: :wait, result: nil)
    @toast = { title: "Grader", body: "Job ##{job.id} re-queued." }
    respond_to do |format|
      format.turbo_stream { render "turbo_toast" }
      format.html { redirect_to grader_processes_path, flash: { notice: @toast[:body] } }
    end
  end

  def retry_all_error_jobs
    count = Job.where(status: :error).update_all(status: :wait, result: nil)
    @toast = { title: "Grader", body: "#{count} error #{'job'.pluralize(count)} re-queued." }
    respond_to do |format|
      format.turbo_stream { render "turbo_toast" }
      format.html { redirect_to grader_processes_path, flash: { notice: @toast[:body] } }
    end
  end

  def clear_all_error_jobs
    count = Job.where(status: :error).delete_all
    @toast = { title: "Grader", body: "#{count} error #{'job'.pluralize(count)} cleared." }
    respond_to do |format|
      format.turbo_stream { render "turbo_toast" }
      format.html { redirect_to grader_processes_path, flash: { notice: @toast[:body] } }
    end
  end

  # solid_queue dashboard
  QUEUE_STATUSES = %w[all pending failed finished].freeze

  def queues
    @status = QUEUE_STATUSES.include?(params[:status]) ? params[:status] : 'all'
    @statuses = QUEUE_STATUSES
  end

  def queues_query
    jobs_scope = SolidQueue::Job.all
    case params[:status]
    when 'failed'
      jobs_scope = jobs_scope.failed
    when 'finished'
      jobs_scope = jobs_scope.finished
    when 'pending'
      jobs_scope = jobs_scope.where(finished_at: nil).where.missing(:failed_execution)
    end

    raw_jobs = jobs_scope.includes(:failed_execution).order(created_at: :desc).first(500)
    @jobs = raw_jobs.map { |job| Llm::RequestJobPresenter.new(job) }
  end

  private

    def set_problem
      @grader = GraderProcess.find(params[:id])
    end
end
