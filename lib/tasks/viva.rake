namespace :viva do
  desc 'Move per-problem llm_prompt tags into problems.viva_prompt; re-kind shared ones to viva_conduct. Report-only unless APPLY=1.'
  task migrate_prompt_tags: :environment do
    Current.actor_note = 'Rake: viva:migrate_prompt_tags'
    Viva::PromptTagMigrator.new(apply: ENV['APPLY'] == '1').run
  end
end

namespace :viva do
  desc 'Import a viva-scenario kit directory (manifest.yml + scenario/briefing .md files) into viva_exam problems. Report-only unless APPLY=1. Usage: bin/rails viva:import DIR=/path/to/kit [APPLY=1]'
  task import: :environment do
    dir = ENV['DIR'].presence or abort 'usage: bin/rails viva:import DIR=/path/to/kit [APPLY=1]'
    Current.actor_note = "Rake: viva:import #{File.basename(dir)}"
    ok = Viva::KitImporter.new(dir, apply: ENV['APPLY'] == '1').run
    exit(1) unless ok
  end
end

namespace :viva do
  desc 'Rewrite done viva submissions whose grader_comment holds a copy of the LLM narrative (pre-marker grading path) to the compact viva marker. Report-only unless APPLY=1. Usage: bin/rails viva:clean_grader_comments [APPLY=1]'
  task clean_grader_comments: :environment do
    Current.actor_note = 'Rake: viva:clean_grader_comments'
    Viva::GraderCommentCleaner.new(apply: ENV['APPLY'] == '1').run
  end
end

namespace :viva do
  usage = 'usage: bin/rails viva:regrade PROBLEM=<name|id> [CONTEST=<name|id>] [MODEL=<model>] [ALL=1] [REPLACE=1] [LIMIT=<n>] [APPLY=1]'

  desc 'Queue one more grader run for every stale session of a viva problem (never-lower unless REPLACE=1; stale only unless ALL=1). Report-only unless APPLY=1. ' + usage
  task regrade: :environment do
    key = ENV['PROBLEM'].presence or abort usage
    problem = Viva::Regrader.find_problem(key) or abort "no problem named or numbered #{key}"
    contest = nil
    if ENV['CONTEST'].present?
      contest = Viva::Regrader.find_contest(ENV['CONTEST']) or abort "no contest named or numbered #{ENV['CONTEST']}"
    end
    Current.actor_note = "Rake: viva:regrade #{problem.name}"
    regrader = Viva::Regrader.new(problem: problem, contest: contest, model: ENV['MODEL'].presence,
                                  never_lower: ENV['REPLACE'] != '1', all: ENV['ALL'] == '1',
                                  limit: ENV['LIMIT'].present? ? ENV['LIMIT'].to_i : nil)
    ENV['APPLY'] == '1' ? regrader.apply! : regrader.report
  rescue ArgumentError => e
    abort e.message
  end

  desc 'Progress and outcome of a viva:regrade batch: counts, old/new/final means, per-target rows; CSV=<path> writes them. Usage: bin/rails viva:regrade_status BATCH=<id> [CSV=<path>]'
  task regrade_status: :environment do
    batch_id = ENV['BATCH'].presence or abort 'usage: bin/rails viva:regrade_status BATCH=<id> [CSV=<path>]'
    Current.actor_note = "Rake: viva:regrade_status #{batch_id}"
    st = Viva::Regrader.status(batch_id)
    st.print($stdout)
    if ENV['CSV'].present?
      File.write(ENV['CSV'], st.to_csv)
      puts "wrote #{st.rows.size} row(s) to #{ENV['CSV']}"
    end
  rescue ArgumentError => e
    abort e.message
  end

  desc 'Put every submission a viva:regrade batch changed back to its earlier grade (nothing is deleted). Report-only unless APPLY=1. Usage: bin/rails viva:regrade_revert BATCH=<id> [APPLY=1]'
  task regrade_revert: :environment do
    batch_id = ENV['BATCH'].presence or abort 'usage: bin/rails viva:regrade_revert BATCH=<id> [APPLY=1]'
    Current.actor_note = "Rake: viva:regrade_revert #{batch_id}"
    Viva::Regrader.revert(batch_id, apply: ENV['APPLY'] == '1')
  rescue ArgumentError => e
    abort e.message
  end
end
