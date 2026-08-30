module Replay
  # Cafe->cafe behavioral validation of the import/export path. Exports a
  # problem, re-imports it as a throwaway (_rc_ prefix), replays a sample of the
  # original's submissions through the real grader, and diffs each fresh grade
  # against the original's STORED grade. Everything created is destroyed on exit.
  # Dev diagnostic only — never touches CMS.
  module SubmissionReplay
    module_function

    RC_PREFIX = '_rc_'

    # Languages that grade reliably on this box; others fail for environment
    # reasons (e.g. cgroup-v2 unconfigured). Override via REPLAY_GRADABLE_LANGS.
    GRADABLE_LANGS = (ENV['REPLAY_GRADABLE_LANGS'] || 'cpp,c').split(',').map(&:strip).freeze

    def replay_bot
      User.find_or_create_by!(login: 'replay_bot') do |u|
        u.full_name = 'Replay Bot (import/export validation)'
        u.password = SecureRandom.hex(16)
      end
    end

    def run(problem, limit: 100)
      sample = ReplaySampler.sample(problem, limit: limit, languages: GRADABLE_LANGS)
      clone = nil
      report = { problem: problem.name, replayed: 0, skipped_stale: sample[:skipped_stale],
                 buckets: sample[:buckets], exact: 0, benign: 0, mismatch: 0,
                 structural: 0, errored: 0, suspect: 0, mismatch_details: [], error_details: [],
                 skipped: false, skip_reason: nil }
      unless problem.live_dataset
        report[:skipped] = true
        report[:skip_reason] = 'problem has no live dataset'
        return report
      end
      begin
        clone = import_clone(problem)
      rescue ActiveStorage::FileNotFoundError => e
        report[:skipped] = true
        report[:skip_reason] = "ActiveStorage blobs not present locally " \
          "(#{e.message.to_s[0, 100]}); run \"sync:problem[#{problem.id}]\" first"
        return report
      end
      begin
        bot = replay_bot
        sample[:submissions].each do |orig|
          fresh = nil
          begin
            fresh = build_submission(bot, clone, orig)
            res = ReplayGrader.grade_sync(fresh, clone.live_dataset)
            diff = ReplayDiff.classify(orig.grader_comment, orig.points, res[:grader_comment], res[:points])
            tally(report, diff, orig, res)
          rescue StandardError => e
            report[:errored] += 1
            report[:error_details] << { orig_submission_id: orig.id, language: orig.language&.name,
                                        new_status: 'exception', new_gc: e.message }
          ensure
            # Judge Job rows reference the submission by integer `arg` (no FK), so
            # they are NOT cascade-destroyed with the problem — delete them here.
            Job.where(arg: fresh.id).delete_all if fresh
            report[:replayed] += 1
          end
        end
      ensure
        clone&.destroy   # cascades datasets/testcases/submissions/evaluations + purges blobs
        GraderProcess.where(box_id: ReplayGrader::REPLAY_BOX_ID,
                            worker_id: ReplayGrader::REPLAY_WORKER_ID).delete_all
      end
      report
    end

    # Export `problem` to a temp dir and re-import it as a fresh _rc_ problem.
    def import_clone(problem)
      Dir.mktmpdir("replay") do |dump|
        ProblemExporter.new.export_problem_to_dir(problem, base_dir: dump, zip: false)
        exported = File.join(dump, problem.name.parameterize)
        pi = ProblemImporter.new
        pi.import_dataset_from_dir(exported, "#{RC_PREFIX}#{SecureRandom.hex(6)}",
                                   full_name: "replay of #{problem.name}", user: replay_bot,
                                   do_solutions: false)
        pi.problem
      end
    end

    def build_submission(bot, clone, orig)
      s = Submission.new(user: bot, problem: clone, language: orig.language,
                         source_filename: orig.source_filename, submitted_at: Time.zone.now, tag: :default)
      s.source = orig.source
      s.save!(validate: false)   # replaying already-valid sources; skip submit-auth validation
      s
    end

    def tally(report, diff, orig, res)
      # A fresh compile/grader error the ORIGINAL submission didn't have could be
      # an environment limitation on this box (e.g. cgroup unavailable for
      # non-gradable languages), not an import/export defect — bucket apart,
      # exclude from the verdict. But a GRADABLE language freshly erroring is
      # SUSPECT: it can indicate a real import/export defect (e.g. a lost
      # checker surfacing as grader_error) and must fail the verdict.
      fresh = res[:status].to_s
      if %w[grader_error compilation_error].include?(fresh) && orig.status.to_s != fresh
        lang = orig.language&.name
        if GRADABLE_LANGS.include?(lang)
          # A gradable language should NOT newly error — SUSPECT (a real
          # import/export defect can surface as grader_error). Fails the verdict.
          report[:suspect] += 1
          report[:mismatch_details] << {
            orig_submission_id: orig.id, verdict: :suspect_error,
            orig_points: orig.points, new_points: res[:points],
            orig_gc: orig.grader_comment, new_gc: res[:grader_comment],
            positions: [], note: "fresh #{fresh} on gradable language '#{lang}'"
          }
        else
          report[:errored] += 1
          report[:error_details] << { orig_submission_id: orig.id, language: lang,
                                      new_status: fresh, new_gc: res[:grader_comment] }
        end
        return
      end
      report[diff[:verdict]] += 1
      return unless %i[mismatch structural].include?(diff[:verdict])
      report[:mismatch_details] << {
        orig_submission_id: orig.id, verdict: diff[:verdict],
        orig_points: orig.points, new_points: res[:points],
        orig_gc: orig.grader_comment, new_gc: res[:grader_comment],
        positions: diff[:positions], note: diff[:note]
      }
    end

    # Destroy every throwaway artifact (backstop for interrupted runs).
    def purge!
      Submission.joins(:user).where(users: { login: 'replay_bot' }).find_each do |s|
        Job.where(arg: s.id).delete_all   # judge jobs have no FK to the submission
        s.destroy
      end
      # the dedicated replay grader_process row (created by ReplayGrader)
      GraderProcess.where(box_id: ReplayGrader::REPLAY_BOX_ID,
                          worker_id: ReplayGrader::REPLAY_WORKER_ID).delete_all
      scope = Problem.where("name LIKE ?", "#{Problem.sanitize_sql_like(RC_PREFIX)}%")
      count = scope.count
      scope.find_each(&:destroy)
      count
    end
  end
end
