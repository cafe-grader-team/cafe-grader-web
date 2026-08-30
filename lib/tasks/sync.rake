namespace :sync do
  DEFAULT_REMOTE_HOST = '10.0.5.80'.freeze
  DEFAULT_REMOTE_RAILS_ROOT = 'cafe_grader/web'.freeze

  desc 'Sync a problem\'s Active Storage files from a remote host (override REMOTE_HOST / REMOTE_RAILS_ROOT); run with no id for help'
  task :problem, [:id] => :environment do |_task, args|
    # Resolve the remote source once, so the help text and the actual run agree.
    remote_host = ENV['REMOTE_HOST'] || DEFAULT_REMOTE_HOST
    remote_rails_root = ENV['REMOTE_RAILS_ROOT'] || DEFAULT_REMOTE_RAILS_ROOT
    remote_base = "#{remote_host}:#{remote_rails_root}/storage"
    host_note = ENV['REMOTE_HOST'] ? '(from REMOTE_HOST)' : '(default — set REMOTE_HOST to change)'
    root_note = ENV['REMOTE_RAILS_ROOT'] ? '(from REMOTE_RAILS_ROOT)' : '(default — set REMOTE_RAILS_ROOT to change)'

    unless args[:id]
      warn <<~USAGE
        Sync one problem's Active Storage files (testcases, checker, managers,
        initializers, data files, statement, attachment) from a remote server
        into this machine's storage/. Use it when the DB was migrated without
        the storage/ files (e.g. a local dev copy).

        Usage:
          rails "sync:problem[<problem_id>]"

        Remote source currently resolves to:
          REMOTE_HOST       = #{remote_host}  #{host_note}
          REMOTE_RAILS_ROOT = #{remote_rails_root}  #{root_note}
          rsync source      = #{remote_base}/<key>

        Override the server / path with environment variables:
          REMOTE_HOST=192.168.1.10 rails "sync:problem[1590]"
          REMOTE_HOST=user@host REMOTE_RAILS_ROOT=apps/cafe/web rails "sync:problem[1590]"

        (REMOTE_HOST may be a bare host or user@host; rsync connects over ssh.)
      USAGE
      next
    end

    problem = Problem.find_by(id: args[:id])
    unless problem
      warn "Error: Problem with ID=#{args[:id]} not found."
      next
    end

    puts "--> Syncing Problem ##{problem.id} (#{problem.name})"
    puts "    from  #{remote_base}  #{host_note}"
    puts "    (override with REMOTE_HOST / REMOTE_RAILS_ROOT — run 'rails sync:problem' with no id for help)"
    sync_problem(problem, remote_base: remote_base)

    puts '--> Sync complete.'
  end

  # Helper methods are now updated to accept the `remote_base` path.
  def sync_single_attachment(attachment, remote_base:)
    return unless attachment.is_a?(ActiveStorage::Attachment) || attachment.attached?

    blob = attachment.blob
    key = blob.key
    # Use the passed-in remote_base
    src = File.join(remote_base, key[0..1], key[2..3], key)
    dst = Rails.root.join('storage', key[0..1], key[2..3], key)

    dst.dirname.mkpath

    cmd = "rsync -ah --info=progress2 #{Shellwords.escape(src)} #{Shellwords.escape(dst)}"
    puts "    SYNC: #{blob.filename} (#{blob.content_type})"
    system(cmd)
  end

  def sync_collection(attachments, remote_base:)
    attachments.each do |att|
      sync_single_attachment(att, remote_base: remote_base)
    end
  end

  def sync_problem(problem, remote_base:)
    puts "  Statement:"
    sync_single_attachment(problem.statement, remote_base: remote_base)

    puts "  Attachment:"
    sync_single_attachment(problem.attachment, remote_base: remote_base)

    problem.datasets.each do |ds|
      puts "  Dataset ##{ds.id}:"
      puts "    Checker:"
      sync_single_attachment(ds.checker, remote_base: remote_base) if ds.checker.attached?

      puts "    Managers:"
      sync_collection(ds.managers, remote_base: remote_base) if ds.managers.attached?

      puts "    Initializers:"
      sync_collection(ds.initializers, remote_base: remote_base) if ds.initializers.attached?

      puts "    Data Files:"
      sync_collection(ds.data_files, remote_base: remote_base) if ds.data_files.attached?

      ds.testcases.each do |tc|
        puts "    Testcase #{tc.code_name}:"
        sync_single_attachment(tc.inp_file, remote_base: remote_base)
        sync_single_attachment(tc.ans_file, remote_base: remote_base)
      end
    end
  end
end
