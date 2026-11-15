namespace :engine do
  desc 'Grade one existing submission end to end on this host (real isolate), report, then restore it. SUB=<id>|auto [BOX=99]'
  task smoke: :environment do
    sub_id = ENV['SUB'] or abort 'usage: bin/rails engine:smoke SUB=<submission id>|auto [BOX=99]   (pick a submission you are happy to see re-evaluated, or SUB=auto to let EngineSmokePicker choose; its stored grade is restored afterwards)'
    box = Integer(ENV.fetch('BOX', '99'))
    fmt = ->(g) { "#{g[:status]} points=#{g[:points]} comment=#{g[:grader_comment].inspect}" }

    if sub_id == 'auto'
      # The deploy pipeline's mode. Two SKIPPED exits (0) are deliberate: a
      # web-only host grades nothing, and a fresh host has nothing to regrade;
      # neither should block a deploy. An explicit SUB=<id> never skips.
      worker_id = Rails.configuration.worker[:worker_id]
      if GraderProcess.where(worker_id: worker_id, enabled: true).none?
        puts "SKIPPED: no enabled grader boxes for worker #{worker_id} on this host — nothing grades here, nothing to smoke"
        exit 0
      end
      picker = EngineSmokePicker.new
      sub = picker.pick
      unless sub
        puts 'SKIPPED: no suitable submission on this host — need done, regular, non-viva, full score, ' \
             "#{EngineSmokePicker::LANGUAGE_ORDER.join('/')} still accepted by its problem, " \
             'graded after its live dataset last changed, ' \
             "slowest testcase within #{(EngineSmokePicker::RUNTIME_MARGIN * 100).to_i}% of the time limit, " \
             "testcases x limit <= #{EngineSmokePicker::MAX_BUDGET_SECONDS}s"
        exit 0
      end
      puts "auto-picked submission #{sub.id}: #{picker.describe(sub)}"
    else
      sub = Submission.find(Integer(sub_id))
    end

    report = EngineSmoke.new(sub, box_id: box).run

    puts "submission #{report.submission_id}: #{sub.language.name}, problem #{sub.problem_id} #{sub.problem.name}, dataset #{report.dataset_id}, box #{box}"
    puts "  stored grade: #{fmt.call(report.before)}"
    report.evaluations.each { |e| puts "  tc #{e[:testcase_id]}: #{e[:result]} score=#{e[:score]} time=#{e[:time]}ms" }
    puts "  this run:     #{fmt.call(report.after)}"
    if report.error
      puts "  ERROR #{report.error.class}: #{report.error.message}"
      puts report.error.backtrace.first(6).map { |l| "    #{l}" }
      puts '  submission restored to its stored grade'
      exit 1
    end
    identical = %i[status points grader_comment].all? { |k| report.before[k].to_s == report.after[k].to_s }
    puts(identical ? '  verdict identical to the stored grade' : '  verdict DIFFERS from the stored grade — check the dataset has not changed since, then investigate')
    puts '  submission restored to its stored grade'
    exit 2 unless identical
  end

  desc 'Show the per-language settings this host needs (worker.yml `isolate_options:`, `compiler_options:`, missing `compiler:` paths). WRITE=1 writes them to config/worker.yml'
  task detect: :environment do
    detected = SandboxDetect.new.all
    file = Rails.root.join('config', 'worker.yml')
    # per section, only the lines detection owns (the compiler section has many others)
    read = ->(conf) do
      SandboxDetect::OWNED.to_h { |section, langs| [section, (conf[section.to_sym] || {}).to_h.transform_keys(&:to_s).slice(*langs)] }
    end
    current = read.call(Rails.configuration.worker)
    show = ->(sections) do
      sections.each do |section, langs|
        next if langs.empty?
        puts "  #{section}:"
        langs.each { |lang, opts| puts %(    #{lang}: "#{opts}") }
      end
    end

    if detected.empty?
      puts 'detected: this host needs no extra options'
    else
      puts 'detected — this host needs, in the common section (`shared:`, or `default: &default` in an old file) of config/worker.yml:'
      show.call(detected)
    end
    if current.values.all?(&:empty?)
      puts 'config/worker.yml has none of these lines'
    else
      puts 'config/worker.yml has:'
      show.call(current)
    end

    # Only the lines detection owns are compared and written; a line a person
    # added for another language stays.
    changes = SandboxDetect::OWNED.flat_map do |section, langs|
      langs.filter_map do |lang|
        want = detected.dig(section, lang)
        [section, lang, want] unless current[section][lang].to_s == want.to_s
      end
    end
    if changes.empty?
      puts 'worker.yml is up to date'
      next
    end
    puts 'to change:'
    changes.each { |section, lang, want| puts "  #{section} #{lang}: #{current[section][lang].inspect} -> #{want.inspect}" }
    unless ENV['WRITE'] == '1'
      puts 'not written — run `bin/rails engine:detect WRITE=1` to update config/worker.yml, then restart the graders'
      exit 1
    end

    original = File.read(file)
    patched = changes.reduce(original) { |text, (section, lang, want)| WorkerConfigPatch.apply(text, lang, want, section: section) }
    File.write(file, patched)
    # Read the file back the way Rails does; put the old text back if the
    # edit did not produce exactly the detected values.
    reread = read.call(Rails.application.config_for(:worker))
    unless changes.all? { |section, lang, want| reread[section][lang].to_s == want.to_s }
      File.write(file, original)
      abort "the edit of #{file} did not read back as expected (#{reread.inspect}); file restored, nothing changed"
    end
    puts "written to #{file} — restart the graders to use it, then `bin/rails engine:langcheck`"
  end

  desc 'Compile and run a built-in program per language in the real sandbox. [ONLY=java,cpp] [BOX=99] [SKIP_WEB_ONLY=1]'
  task langcheck: :environment do
    box = Integer(ENV.fetch('BOX', '99'))
    worker_id = Rails.configuration.worker[:worker_id]
    # The deploy pipeline's mode, as in engine:smoke: a web-only host grades nothing.
    if ENV['SKIP_WEB_ONLY'] == '1' && GraderProcess.where(worker_id: worker_id, enabled: true).none?
      puts "SKIPPED: no enabled grader boxes for worker #{worker_id} on this host — nothing grades here"
      exit 0
    end
    languages = ENV['ONLY'] ? ENV['ONLY'].split(',').map(&:strip) : LangCheck.languages

    results = LangCheck.new(box_id: box).run(languages)
    label = { pass: 'PASS', fail: 'FAIL', not_configured: 'not configured' }
    results.each do |r|
      line = "  #{r.language.ljust(8)} #{label[r.verdict]}"
      line += " (#{r.phase})" if r.verdict == :fail
      line += " — #{r.detail}" if r.detail
      puts line
      puts "           isolate options: #{r.options}" if r.verdict == :fail && r.options.present?
    end

    judge = Compiler.new(worker_id, box)
    config_problems = SandboxDetect.new.problems(effective: ->(lang) { judge.isolate_options_by_lang(lang) })
    config_problems.each { |msg| puts "  CONFIG #{msg}" }

    failed = results.count { |r| r.verdict == :fail }
    puts "#{results.count { |r| r.verdict == :pass }} pass, #{failed} fail, " \
         "#{results.count { |r| r.verdict == :not_configured }} not configured (box #{box}); " \
         'not covered: digital, postgres, archive, text'
    exit 1 if failed.positive? || config_problems.any?
  end
end
