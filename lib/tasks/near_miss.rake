# Near-Miss Grading batch instrument (v1 — CLI only).
# Spec: docs/superpowers/specs/2026-07-30-near-miss-grading-design.md
namespace :near_miss do
  desc <<~DESC
    Run bounded LLM repair over a contest's failing submissions.
    Usage: rake near_miss:repair CONTEST=<id> [PROBLEM=<id>] [SUBMISSION=<id>]
             [SCOPE=latest|all] [MIN_SCORE=] [MAX_SCORE=] [BUDGET_LINES=2]
             [BUDGET_CHARS=20] [ROUNDS=3] [SERVICE=<self-host key>] [RUN=<label>]
             [LIMIT=<n>] [DRY=1]
  DESC
  task repair: :environment do
    abort 'CONTEST=<id> or SUBMISSION=<id> is required' if ENV['CONTEST'].blank? && ENV['SUBMISSION'].blank?

    budget_lines = (ENV['BUDGET_LINES'].presence || 2).to_i
    budget_chars = (ENV['BUDGET_CHARS'].presence || 20).to_i
    rounds       = (ENV['ROUNDS'].presence || 3).to_i
    scope        = ENV['SCOPE'].presence || 'latest'
    model_key    = ENV['SERVICE'].presence
    abort "SCOPE must be latest|all, got #{scope}" unless %w[latest all].include?(scope)

    if ENV['SUBMISSION'].present?
      target_ids = [Submission.regular.find(ENV['SUBMISSION']).id]
      run_label  = ENV['RUN'].presence || "sub#{target_ids.first}-#{Time.zone.today}"
    else
      contest = Contest.find(ENV['CONTEST'])
      problems = contest.problems
      problems = problems.where(id: ENV['PROBLEM']) if ENV['PROBLEM'].present?
      target_ids = SubmissionRepair.batch_targets(
        problems: problems, users: contest.users, scope: scope,
        min_score: ENV['MIN_SCORE'].presence, max_score: ENV['MAX_SCORE'].presence)
      run_label = ENV['RUN'].presence || "contest#{contest.id}-#{Time.zone.today}"

      skipped_raw_sum = problems.joins('LEFT JOIN datasets live_ds ON live_ds.id = problems.live_dataset_id')
                                .where('live_ds.score_type = ? OR live_ds.id IS NULL', Dataset.score_types[:raw_sum])
      if skipped_raw_sum.any?
        puts "NOTE: skipped problems (raw_sum scoring or no live dataset — no defined full score): " \
             "#{skipped_raw_sum.pluck(:name).join(', ')}"
      end
    end

    target_ids = target_ids.first(ENV['LIMIT'].to_i) if ENV['LIMIT'].present?

    puts "Near-Miss repair batch"
    puts "  run label:  #{run_label}"
    puts "  targets:    #{target_ids.size} submissions"
    puts "  budget:     #{budget_lines} lines / #{budget_chars} chars, rounds: #{rounds}"
    puts "  service:    #{model_key || '(self_hosted_default)'}"

    if ENV['DRY'].present?
      by_problem = Submission.where(id: target_ids).joins(:problem).group('problems.name').count
      by_problem.each { |name, n| puts "    #{name}: #{n}" }
      puts 'DRY run — nothing enqueued.'
      next
    end

    # Model-identity guard (spec section 8.1): abort before enqueueing if the
    # endpoint serves a different model than configured. Only meaningful when
    # the configured repair service is the self-host provider — a Genie-class
    # service ignores the self_hosted_models registry entirely (and SERVICE=
    # would be an unknown key there). A missing/blank service key still gets
    # the guard when self-host config exists; it then fails in the job.
    repair_service = Rails.configuration.llm[:submission_repair_service].to_s
    self_host_service = repair_service.blank? || repair_service == 'Llm::SubmissionRepairSelfHostAssist'
    if self_host_service && Rails.configuration.llm[:self_hosted_models].present?
      chat = Llm::SelfHostChat.new(model_key: model_key)
      chat.verify_model!
      puts "  verified:   #{chat.model_key} serves #{chat.model_name}"
    end

    result = SubmissionRepair.enqueue_batch!(
      submission_ids: target_ids, budget_lines: budget_lines,
      budget_chars: budget_chars, rounds: rounds, run_label: run_label,
      model_key: model_key)
    puts "enqueued #{result[:enqueued]}, skipped #{result[:skipped]} (already attempted in this run label)"
    puts "watch progress: SubmissionRepair.where(run_label: '#{run_label}').group(:status).count"
  end

  desc 'Report on repair runs. Usage: rake near_miss:report RUN=<label>[,<label>...]  (or CONTEST=<id>)'
  task report: :environment do
    labels = ENV['RUN'].to_s.split(',').map(&:strip).reject(&:empty?)
    if labels.empty? && ENV['CONTEST'].present?
      prefix = "contest#{ENV['CONTEST']}-"
      labels = SubmissionRepair.where('run_label LIKE ?', "#{prefix}%").distinct.pluck(:run_label)
    end
    abort 'RUN=<label>[,<label>...] or CONTEST=<id> is required' if labels.empty?

    report = SubmissionRepair.report_for(labels)
    abort "no attempts found for #{labels.join(', ')}" if report.empty?

    require 'csv'
    csv_path = Rails.root.join('tmp', "near_miss_report_#{Time.zone.now.strftime('%Y%m%d_%H%M%S')}.csv")
    CSV.open(csv_path, 'w') do |csv|
      csv << %w[run_label problem targets accepted over_budget no_change failed ungradeable rescued
                rescue_rate mean_gap median_gap categories median_size tokens_in tokens_out cost]
      report.each do |label, per_problem|
        puts "\n=== run: #{label} ==="
        per_problem.each do |pname, s|
          sizes = s[:sizes].sort
          median_size = SubmissionRepair.median(sizes)
          st = s[:statuses]
          puts format('  %-24s targets=%-4d accepted=%-4d over_budget=%-4d no_change=%-4d failed=%-4d',
                      pname, s[:targets], st['accepted'].to_i, st['over_budget'].to_i,
                      st['no_change'].to_i, st['failed'].to_i)
          puts format('  %-24s UNGRADEABLE=%d (shadows without a judge outcome — excluded from gap stats)',
                      '', s[:ungradeable]) if s[:ungradeable].positive?
          puts format('  %-24s rescued=%d (rate %.1f%%)  gap mean=%s median=%s  median_size=%s chars',
                      '', s[:rescued], s[:rescue_rate] * 100,
                      s[:mean_gap] || '-', s[:median_gap] || '-', median_size || '-')
          puts "  #{' ' * 24} categories: #{s[:categories].map { |k, v| "#{k}=#{v}" }.join(' ')}" if s[:categories].any?
          s[:compliance].sort.each do |round, c|
            puts format('  %-24s round %d budget compliance: %d/%d', '', round, c[:within], c[:total])
          end
          puts format('  %-24s tokens in/out: %d/%d  cost: $%.4f', '', s[:tokens_in], s[:tokens_out], s[:cost])
          csv << [label, pname, s[:targets], st['accepted'].to_i, st['over_budget'].to_i,
                  st['no_change'].to_i, st['failed'].to_i, s[:ungradeable], s[:rescued], s[:rescue_rate],
                  s[:mean_gap], s[:median_gap], s[:categories].to_json, median_size,
                  s[:tokens_in], s[:tokens_out], s[:cost]]
        end
      end
    end
    puts "\nCSV: #{csv_path}"
  end
end
