module Llm
  # Wraps a SolidQueue::Job that was enqueued via Llm::RequestJob (or any of its
  # subclasses) for display on /grader_processes/queues and the report dashboard.
  # Surfaces user/problem/submission summary plus failure detail when the job
  # has a SolidQueue::FailedExecution.
  class RequestJobPresenter < SimpleDelegator
    attr_reader :user_name, :problem_name
    attr_reader :user_id, :problem_id
    attr_reader :points

    def initialize(job, submission = nil)
      __setobj__(job)

      @submission = submission
      @arguments = job.arguments['arguments']
      if @submission
        # The user and problem associations were eager-loaded (e.g.,
        # .includes(:user, :problem)) so these don't hit the database.
        @user_name = @submission.user.full_name
        @user_id = @submission.user.id
        @problem_name = @submission.problem.full_name
        @problem_id = @submission.problem.id
        @points = @submission.points
      end
    end

    def submission_id
      @submission&.id
    end

    def detail
      last_arg = @arguments.last
      last_arg.is_a?(Hash) ? last_arg : {}
    end

    # Normalize SolidQueue::Job#status — the gem returns either :finished or the
    # STI type string of the current execution row. Map to short symbols.
    STATUS_LABELS = {
      "SolidQueue::ReadyExecution"     => :ready,
      "SolidQueue::ClaimedExecution"   => :claimed,
      "SolidQueue::FailedExecution"    => :failed,
      "SolidQueue::ScheduledExecution" => :scheduled,
      "SolidQueue::BlockedExecution"   => :blocked
    }.freeze

    def status
      raw = __getobj__.status
      raw.is_a?(String) ? (STATUS_LABELS[raw] || raw) : raw
    end

    def failure
      fe = __getobj__.failed_execution
      return nil unless fe
      { exception_class: fe.exception_class, message: fe.message, backtrace: fe.backtrace }
    end

    def detail_html
      parts = []
      h = detail
      parts << "<strong>Model:</strong> #{ERB::Util.html_escape(h['model'].to_s)}" if h['model'].present?

      if (f = failure)
        cls = ERB::Util.html_escape(f[:exception_class].to_s)
        msg = ERB::Util.html_escape(f[:message].to_s)
        bt  = (f[:backtrace] || []).first(8).map { |line| ERB::Util.html_escape(line) }.join("<br>")
        parts << %(<div class="text-danger small mt-1"><strong>#{cls}</strong>: #{msg}) +
                 %(<details class="mt-1"><summary>Backtrace</summary>) +
                 %(<pre class="small mb-0 text-danger">#{bt}</pre></details></div>)
      end

      parts.join.html_safe
    end

    # Delegate the underlying job for Jbuilder
    def to_model
      __getobj__
    end
  end
end
