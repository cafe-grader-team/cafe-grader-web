# lib/tasks/replay.rake
namespace :problems do
  desc "Validate import/export by replaying submissions (cafe->cafe, dev only). " \
       "Usage: rake problems:replay_validate[ex00e2+a58_proj_algo,100]"
  task :replay_validate, %i[names limit] => :environment do |_t, args|
    names = (args[:names] || "ex00e2+a58_proj_algo+a57_m4_gaa").split("+")
    limit = (args[:limit] || 100).to_i
    puts "Replay validation (dev, no CMS contact). Cleanup backstop if interrupted:"
    puts "  bin/rails 'problems:replay_purge'\n\n"

    overall_ok = true
    names.each do |name|
      problem = Problem.find_by(name: name)
      unless problem
        puts "SKIP #{name}: not found"; next
      end
      report = Replay::SubmissionReplay.run(problem, limit: limit)
      if report[:skipped]
        puts format("%-22s SKIP — %s", name, report[:skip_reason])
        next
      end
      bad = report[:mismatch] + report[:structural] + report[:suspect]   # errored is env, NOT a failure
      overall_ok &&= bad.zero?
      puts format("%-22s replayed=%-4d stale=%-4d exact=%-4d benign=%-4d MISMATCH=%-3d STRUCT=%-3d SUSPECT=%-3d errored=%-3d buckets=%s",
                  name, report[:replayed], report[:skipped_stale], report[:exact],
                  report[:benign], report[:mismatch], report[:structural], report[:suspect], report[:errored],
                  report[:buckets].inspect)
      report[:mismatch_details].each do |d|
        puts "   ! sub ##{d[:orig_submission_id]} #{d[:verdict]} pts #{d[:orig_points]}->#{d[:new_points]} " \
             "gc #{d[:orig_gc].inspect}->#{d[:new_gc].inspect}"
      end
      if report[:errored].positive?
        langs = report[:error_details].group_by { |e| e[:language] }.transform_values(&:size)
        puts "   ~ #{report[:errored]} not gradable in this env (cgroup/lang): #{langs.inspect}"
      end
    end
    puts "\n#{overall_ok ? 'PASS — no non-benign differences' : 'FAIL — investigate mismatches above'}"
  end

  desc "Purge all replay-validation artifacts (_rc_ problems + replay_bot submissions)."
  task replay_purge: :environment do
    n = Replay::SubmissionReplay.purge!
    puts "Purged #{n} throwaway _rc_ problems and all replay_bot submissions."
  end
end
