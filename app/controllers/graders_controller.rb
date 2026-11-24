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
    @sq_failed_count = SolidQueue::Job.failed.count

    # Solid Queue processes as they registered themselves. A worker's queues
    # and thread pool here are the EFFECTIVE values after any per-host
    # override (config/solid_queue.env), so this is where to confirm what a
    # host really runs — config/queue.yml is only the default. Stale = no
    # heartbeat within Solid Queue's own prune threshold.
    @job_workers = SolidQueue::Process.order(:kind, :name).to_a
    @job_worker_stale_after = SolidQueue.process_alive_threshold

    # Combined tile count: stuck mid-interview turns (VivaTurn.stuck) +
    # stuck mid-grading submissions (Submission.stale_evaluating) — two
    # stages of the same "viva LLM job never resolved" failure mode.
    # Both render as sections on stuck_viva_turns.
    @stuck_viva_turn_count  = VivaTurn.stuck.count
    @stale_evaluating_count = Submission.stale_evaluating.count
    @stuck_viva_count       = @stuck_viva_turn_count + @stale_evaluating_count

    # Sessions where the examiner flagged a suspected jailbreak attempt
    # (design D3). Log-only for now — surfaced here so admins have a
    # single landing page, deep-linking to the calibration instrument.
    @viva_alert_count = VivaTurn.where(role: :assistant, alerted: true).distinct.count(:submission_id)

    # Disk space (issue #25): the web host's app and storage directories are
    # measured now; each judge host's figure is the newest heartbeat row that
    # reported one. Rows: [label, free MB or nil, heartbeat time or nil].
    @disk_rows = [
      ['web: app', GraderProcess.free_disk_mb(Rails.root), nil],
      ['web: storage', GraderProcess.free_disk_mb(Rails.root.join('storage')), nil]
    ] + GraderProcess.disk_by_host
    @lowest_disk_mb = @disk_rows.filter_map { |_, mb, _| mb }.min
    @low_disk_count = @disk_rows.count { |_, mb, _| GraderProcess.low_disk?(mb) }

    @submission_limit = [20, 100, 500].include?(params[:limit].to_i) ? params[:limit].to_i : 20
    @submission = Submission.order("id desc").limit(@submission_limit).includes(:user, :problem)

    # Viva submissions are LLM-graded (async, off the judge-worker queue) —
    # a not-yet-graded one sitting with graded_at nil is normal mid-interview
    # state, not a stuck job. Submission.judge_backlog excludes them; the
    # navbar badge reads the same scope.
    @backlog_submission = Submission.judge_backlog.includes(:user, :problem)

    @wait_compile_job_count = Job.where(job_type: :compile, status: :wait).count
    @wait_eval_job_count = Job.where(job_type: :evaluate, status: :wait).count
  end

  def stuck_viva_turns
    @turns = VivaTurn.stuck
                     .includes(submission: %i[user problem])
                     .order("viva_turns.updated_at desc")
    @stale_evaluating = Submission.stale_evaluating
                           .includes(:user, :problem)
                           .order(updated_at: :desc)
  end

  # One row per submission (viva session) that has at least one
  # examiner-flagged assistant turn (VivaTurn#alerted — design D3). The
  # calibration instrument for the practice month: instructors skim
  # these to judge whether the detection prompt is too sensitive or too
  # lenient. `alerted` sits on the ASSISTANT turn that detected the
  # attempt; the student text that triggered it is the immediately
  # preceding student-role turn, so each row surfaces that utterance
  # alongside the timestamp of the session's most recent alert.
  #
  # N+1 avoidance: one query for the flagged submission ids, one
  # preload of (user, problem, viva_turns) for just those submissions,
  # then the per-session "walk the preloaded turns" lookup happens in
  # Ruby. Fine at practice-month scale.
  VivaAlertRow = Struct.new(:submission, :alert_count, :latest_alert_at, :utterance, keyword_init: true)

  def viva_alerts
    flagged_ids = VivaTurn.where(role: :assistant, alerted: true).distinct.pluck(:submission_id)

    @alerts = Submission.where(id: flagged_ids)
                         .includes(:user, :problem, :viva_turns)
                         .map do |sub|
      turns         = sub.viva_turns.to_a # preloaded, already ordered by sequence
      alerted_turns = turns.select { |t| t.assistant? && t.alerted? }
      latest_alert  = alerted_turns.max_by(&:sequence)
      trigger       = turns.select { |t| t.student? && t.sequence < latest_alert.sequence }.max_by(&:sequence)

      VivaAlertRow.new(
        submission:      sub,
        alert_count:     alerted_turns.size,
        latest_alert_at: latest_alert.updated_at,
        utterance:       trigger&.content
      )
    end.sort_by { |row| -row.latest_alert_at.to_i }
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

  # Retry and Retry All requeue only what Job.split_retryable allows: a row
  # whose submission was deleted, rejudged or graded since stays an error.
  def retry_error_job
    job = Job.find(params[:job_id])
    if Job.split_retryable([job]).first.any?
      job.update(status: :wait, result: nil)
      @toast = { title: "Grader", body: "Job ##{job.id} re-queued." }
    else
      @toast = { title: "Grader", type: :warning,
                 body: "Job ##{job.id} not re-queued: its submission was deleted, rejudged or graded since." }
    end
    respond_to do |format|
      format.turbo_stream { render "turbo_toast" }
      format.html { redirect_to grader_processes_path, flash: { notice: @toast[:body] } }
    end
  end

  def retry_all_error_jobs
    retryable, skipped = Job.split_retryable(Job.where(status: :error).select(:id, :arg, :job_type, :parent_job_id).to_a)
    count = Job.where(id: retryable.map(&:id), status: :error).update_all(status: :wait, result: nil)
    body = "#{count} error #{'job'.pluralize(count)} re-queued."
    body += " #{skipped.size} skipped: their submission was deleted, rejudged or graded since." if skipped.any?
    @toast = { title: "Grader", body: body }
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
