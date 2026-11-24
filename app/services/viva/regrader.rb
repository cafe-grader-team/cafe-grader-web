require 'csv'

module Viva
  # Batch regrade of one viva problem's sessions — behind bin/rails
  # viva:regrade, viva:regrade_status and viva:regrade_revert (design
  # docs/superpowers/specs/2026-09-23-viva-grade-history-design.md).
  # Report-first: #report describes, #apply! enqueues. Every run goes through
  # Submission#regrade_viva!, so the never-lower decision and the failure
  # handling are exactly the Re-run button's; there is no snapshot, finalize
  # or restore step — the grade history is the snapshot and .revert re-adopts.
  class Regrader
    Plan = Struct.new(:problem, :contest, :rubric_version, :model, :never_lower, :all, :limit,
                      :targets, :retries, :archived, :up_to_date, :open, :estimated_cost, :cost_samples,
                      keyword_init: true)
    Outcome = Struct.new(:submission_id, :login, :archived, :old, :new, :final, :outcome, keyword_init: true)

    # PROBLEM= / CONTEST= accept a numeric id or the unique name.
    def self.find_problem(key) = key.to_s.match?(/\A\d+\z/) ? Problem.find_by(id: key) : Problem.find_by(name: key)
    def self.find_contest(key) = key.to_s.match?(/\A\d+\z/) ? Contest.find_by(id: key) : Contest.find_by(name: key)

    def initialize(problem:, contest: nil, model: nil, never_lower: true, all: false, limit: nil, io: $stdout)
      raise ArgumentError, "#{problem.name} is not a viva problem" unless problem.viva_exam?
      if contest && !contest.problems.exists?(problem.id)
        raise ArgumentError, "problem #{problem.name} is not in contest #{contest.name}"
      end
      @problem     = problem
      @contest     = contest
      @model       = model.presence
      @never_lower = never_lower
      @all         = all
      @limit       = limit
      @io          = io
      begin
        @rubric_version = Llm::VivaGradeAssist.rubric_version_for(problem)
      rescue RuntimeError => e     # blank briefing: report it like the other argument errors
        raise ArgumentError, e.message
      end
    end

    # Sessions considered: the problem's real student sessions — archived
    # attempts included (an archived attempt can still be a student's max),
    # test-drives and near-miss shadows excluded by .regular — or, with a
    # contest, that contest's sessions of it (Contest#submissions: enrolled
    # users, inside the window with each user's start offset / extra time).
    def candidates
      base = @contest ? @contest.submissions : Submission.regular
      base.where(problem_id: @problem.id).order(:id)
    end

    # done sessions with no valid run under the current rubric_version, plus
    # grader_error sessions as retries; with all: every done session. A done
    # session is up to date when ANY valid run carries today's rubric — current
    # or not: a run kept as 'lower' already had its chance, and grading it
    # again would only draw more lottery tickets under never-lower. Open
    # (submitted) and grading (evaluating) sessions are skipped.
    def plan
      targets = []
      up_to_date = 0
      open = 0
      subs = candidates.to_a
      fresh = @all ? Set.new : graded_under_current_rubric(subs.map(&:id))
      subs.each do |sub|
        case sub.status.to_s
        when 'done'
          if fresh.include?(sub.id)
            up_to_date += 1
          else
            targets << sub
          end
        when 'grader_error'
          targets << sub
        else
          open += 1
        end
      end
      targets = targets.first(@limit) if @limit
      cost, samples = estimate_cost(targets.size)
      Plan.new(problem: @problem, contest: @contest, rubric_version: @rubric_version, model: @model,
               never_lower: @never_lower, all: @all, limit: @limit, targets: targets,
               retries: targets.count(&:grader_error?), archived: targets.count(&:viva_archived?),
               up_to_date: up_to_date, open: open, estimated_cost: cost, cost_samples: samples)
    end

    def report
      p = plan
      @io.puts "== DRY RUN viva:regrade #{@problem.name} (report only; run with APPLY=1 to execute) =="
      print_plan(p)
      p
    end

    # Viva sessions being interviewed right now, site-wide (every viva
    # problem, archived attempts excluded): their turns share the `viva`
    # queue with the batch's runs, which queue behind them (priority 10).
    def self.open_viva_sessions
      Submission.submitted.joins(:problem).merge(Problem.viva_exam).where(viva_archived_at: nil).count
    end

    # Queues one grader run per target under one batch id and writes the
    # batch's audit row on the problem — the durable record that
    # viva:regrade_status and viva:regrade_revert read the target list from.
    def apply!(now: Time.zone.now)
      p = plan
      batch_id = "regrade-#{@problem.id}-#{now.strftime('%Y%m%dT%H%M%S')}"
      @io.puts "== APPLYING viva:regrade #{@problem.name} as #{batch_id} =="
      print_plan(p)
      queued = []
      begin
        p.targets.each do |sub|
          sub.regrade_viva!(model: @model, never_lower: @never_lower, batch_id: batch_id)
          queued << sub.id
        rescue Submission::NotRegradable => e
          @io.puts "SKIP     ##{sub.id}: #{e.message}"
        end
      ensure
        # Written even when the loop aborts part-way: the runs already queued
        # will land, and status / revert find them only through this row.
        if queued.any?
          AuditLog.record!(auditable: @problem, action: 'viva_regrade', object_changes: {
            'batch_id'       => [nil, batch_id],
            'contest'        => [nil, @contest&.name],
            'model'          => [nil, @model || 'default'],
            'never_lower'    => [nil, @never_lower],
            'rubric_version' => [nil, @rubric_version],
            'targets'        => [nil, queued.size],
            'submission_ids' => [nil, queued]
          })
        end
      end
      @io.puts "queued #{queued.size} run(s) as batch #{batch_id}"
      if queued.any?
        @io.puts "watch:   bin/rails viva:regrade_status BATCH=#{batch_id}   (queue page: /grader_processes/queues)"
        @io.puts "revert:  bin/rails viva:regrade_revert BATCH=#{batch_id} APPLY=1"
      else
        @io.puts "nothing queued; no batch was recorded"
      end
      [batch_id, p]
    end

    # ---- status / revert start from a batch id ----

    # The batch's audit row. The problem id is in the batch id, so the lookup
    # is a scan of that problem's few viva_regrade rows — no JSON SQL.
    def self.find_batch_audit(batch_id)
      pid = batch_id.to_s[/\Aregrade-(\d+)-/, 1]
      raise ArgumentError, "#{batch_id} is not a viva:regrade batch id" unless pid
      AuditLog.where(auditable_type: 'Problem', auditable_id: pid, action: 'viva_regrade').order(:id)
              .detect { |a| a.object_changes.to_h.dig('batch_id', 1) == batch_id } or
        raise ArgumentError, "no viva_regrade audit row for batch #{batch_id}"
    end

    # Outcome names in the order viva:regrade_status prints them.
    OUTCOMES = %w[adopted lower error reverted replaced pending undecided].freeze

    class Status
      attr_reader :batch_id, :audit, :rows

      def initialize(batch_id:, audit:, rows:)
        @batch_id = batch_id
        @audit    = audit
        @rows     = rows
      end

      def problem = audit.auditable

      # counts by outcome; means over the targets that have a value; how many
      # targets ended up above / equal to / below their grade before the batch.
      def summary
        counts = rows.group_by(&:outcome).transform_values(&:size)
        movement = {up: 0, equal: 0, down: 0}
        rows.each do |r|
          next if r.old.nil? || r.final.nil?
          movement[r.final > r.old ? :up : (r.final < r.old ? :down : :equal)] += 1
        end
        {counts: counts, mean_old: mean(rows.map(&:old)), mean_new: mean(rows.map(&:new)),
         mean_final: mean(rows.map(&:final)), movement: movement}
      end

      def to_csv
        CSV.generate do |csv|
          csv << %w[submission_id login archived old new final outcome]
          rows.each { |r| csv << [r.submission_id, r.login, r.archived, r.old, r.new, r.final, r.outcome] }
        end
      end

      def print(io)
        s = summary
        oc = audit.object_changes.to_h
        io.puts "== batch #{batch_id} — problem #{problem&.name} (#{audit.created_at.to_fs(:db)}, #{audit.actor_note || audit.user&.login}) =="
        line = "model #{oc.dig('model', 1)} · #{oc.dig('never_lower', 1) ? 'never-lower' : 'replace'} · rubric #{oc.dig('rubric_version', 1).to_s[0, 12]}"
        line += " · contest #{oc.dig('contest', 1)}" if oc.dig('contest', 1)
        io.puts line
        io.puts 'outcomes  ' + OUTCOMES.map { |k| "#{k}=#{s[:counts][k] || 0}" }.join(' ')
        io.puts "means     old #{fmt(s[:mean_old])} · new #{fmt(s[:mean_new])} · final #{fmt(s[:mean_final])}"
        io.puts "movement  up=#{s[:movement][:up]} equal=#{s[:movement][:equal]} down=#{s[:movement][:down]}"
        io.puts format('%-10s %-14s %-8s %6s %6s %6s  %s', 'sub', 'login', 'archived', 'old', 'new', 'final', 'outcome')
        rows.each do |r|
          io.puts format('%-10d %-14s %-8s %6s %6s %6s  %s', r.submission_id, r.login.to_s, r.archived ? 'yes' : '',
                         fmt(r.old), fmt(r.new), fmt(r.final), r.outcome)
        end
      end

      private

      def mean(values)
        v = values.compact
        v.empty? ? nil : (v.sum / v.size.to_f).round(2)
      end

      def fmt(v) = v.nil? ? '—' : format('%.1f', v)
    end

    # Per target: old = the grade current before the batch, new = this batch's
    # run, final = the grade current now. Outcomes: adopted, lower, error,
    # reverted, replaced (adopted, then displaced by a later run), pending (no
    # run yet), undecided (run written, not decided). For a run that was
    # adopted at some point, old is the run it displaced (the row whose
    # superseded_by_id points at it), not whatever is current today.
    def self.status(batch_id)
      audit = find_batch_audit(batch_id)
      ids   = Array(audit.object_changes.to_h.dig('submission_ids', 1))
      runs  = VivaGrade.where(batch_id: batch_id).order(:id).group_by(&:submission_id)
      rows = Submission.where(id: ids).includes(:user, :viva_grade).order(:id).map do |sub|
        run = runs[sub.id]&.last
        predecessor = -> { VivaGrade.find_by(superseded_by_id: run.id, submission_id: sub.id) }
        outcome, old =
          if run.nil?                               then ['pending', sub.viva_grade]
          elsif run.current?                        then ['adopted', predecessor.call]
          # a revert re-adopts the predecessor, clearing its pointer; it is then run.superseded_by
          elsif run.superseded_reason == 'reverted' then ['reverted', predecessor.call || run.superseded_by]
          elsif run.superseded_reason == 'replaced' then ['replaced', predecessor.call]
          elsif run.superseded_reason.nil?          then ['undecided', sub.viva_grade]
          else                                           [run.superseded_reason, sub.viva_grade]   # lower | error
          end
        Outcome.new(submission_id: sub.id, login: sub.user&.login, archived: sub.viva_archived?,
                    old: old&.total_points&.to_f, new: run&.total_points&.to_f,
                    final: sub.viva_grade&.total_points&.to_f, outcome: outcome)
      end
      Status.new(batch_id: batch_id, audit: audit, rows: rows)
    end

    # Puts every submission the batch changed back to the grade it had before:
    # each current run of the batch is displaced (labelled 'reverted') by the
    # run it replaced. Runs stored as lower or error changed nothing and need
    # nothing; a run with no earlier valid grade behind it is kept. Nothing is
    # deleted. Report-only unless apply.
    def self.revert(batch_id, apply: false, io: $stdout, now: Time.zone.now)
      audit   = find_batch_audit(batch_id)
      problem = audit.auditable
      # Audit rows outlive their target by design; a batch whose problem was
      # destroyed has no grades left to revert and no problem to audit on.
      raise ArgumentError, "the problem of batch #{batch_id} no longer exists; nothing to revert" if problem.nil?
      io.puts(apply ? "== REVERTING batch #{batch_id} ==" : "== DRY RUN revert of batch #{batch_id} (report only; run with APPLY=1 to execute) ==")
      counts = Hash.new(0)
      VivaGrade.where(batch_id: batch_id).current.includes(:submission).order(:id).each do |run|
        old = VivaGrade.find_by(superseded_by_id: run.id, submission_id: run.submission_id)
        if old.nil? || old.failed?
          io.puts "KEEP     ##{run.submission_id}: no earlier valid grade to go back to (#{run.total_points} stays)"
          counts[:kept] += 1
          next
        end
        io.puts "#{apply ? 'REVERT  ' : 'WOULD   '} ##{run.submission_id}: #{run.total_points} -> #{old.total_points}"
        run.submission.adopt_viva_grade!(old, reason: 'reverted', now: now) if apply
        counts[:reverted] += 1
      end
      if apply
        AuditLog.record!(auditable: problem, action: 'viva_regrade_revert', object_changes: {
          'batch_id' => [nil, batch_id], 'reverted' => [nil, counts[:reverted]], 'kept' => [nil, counts[:kept]]
        })
      end
      io.puts "== #{apply ? 'done' : 'dry run'}: reverted=#{counts[:reverted]} kept=#{counts[:kept]} =="
      counts
    end

    private

    def print_plan(p)
      @io.puts format('%-10s %d %s', 'problem', p.problem.id, p.problem.name)
      @io.puts format('%-10s %s', 'contest', p.contest ? "#{p.contest.name} (#{p.contest.id}): enrolled users, sessions started inside the window" : '(none: every regular session of the problem)')
      @io.puts format('%-10s %s (sha256 of conduct tags + briefing + grounding text)', 'rubric', p.rubric_version[0, 12])
      @io.puts format('%-10s %s, model %s', 'grader', grader_class_name, p.model || 'default')
      @io.puts format('%-10s %s', 'rule', p.never_lower ? 'never-lower: a student keeps the higher grade' : 'REPLACE: the new run always becomes current')
      @io.puts format('%-10s %d   (retries after a grader error: %d, archived attempts: %d%s)', 'targets', p.targets.size, p.retries, p.archived, p.limit ? ", LIMIT=#{p.limit}" : '')
      @io.puts format('%-10s %d up to date under this rubric%s, %d open or grading', 'skipped', p.up_to_date, p.all ? '' : ' (ALL=1 to regrade anyway)', p.open)
      @io.puts format('%-10s %s', 'est. cost', p.estimated_cost ? format('USD %.2f (mean of %d past runs x %d)', p.estimated_cost, p.cost_samples, p.targets.size) : 'unknown (no past run has a cost)')
      open_now = self.class.open_viva_sessions
      @io.puts format('%-10s open viva sessions right now: %d (batch runs queue behind their turns)%s', 'WARNING', open_now,
                      open_now.positive? ? '; prefer a time when no exam is live' : '')
    end

    # Ids (a Set) of the given submissions that have a valid run under the
    # current rubric, current or not — one query. Reverted and error runs
    # never counted, so they do not make a session fresh.
    def graded_under_current_rubric(ids)
      return Set.new if ids.empty?
      VivaGrade.where(submission_id: ids, rubric_version: @rubric_version).where.not(total_points: nil)
               .where("viva_grades.superseded_reason IS NULL OR viva_grades.superseded_reason NOT IN ('reverted', 'error')")
               .distinct.pluck(:submission_id).to_set
    end

    def grader_class_name = Rails.configuration.llm[:viva_grade_service].presence || 'Llm::VivaGradeAssist'

    # Mean cost of the problem's past runs (every row, superseded included)
    # times the number of targets. [cost, samples]; [nil, 0] when unknown.
    def estimate_cost(n)
      scope = VivaGrade.joins(:submission).where(submissions: {problem_id: @problem.id}).where.not(cost: nil)
      samples = scope.count
      return [nil, 0] if samples.zero?
      [(scope.average(:cost).to_f * n).round(2), samples]
    end
  end
end
