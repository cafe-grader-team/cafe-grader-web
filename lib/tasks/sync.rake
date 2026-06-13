namespace :sync do
  # Updated description to mention the configurable environment variables
  desc "
  Sync Active Storage attachments from a remote host for a specific problem.
  Configuration can be overridden with environment variables.
  - REMOTE_HOST (default: 10.0.5.80)
  - REMOTE_RAILS_ROOT (default: cafe_grader/web)
  "

  # Task to sync attachments for a single problem by its ID
  # Usage: rails "sync:problem[problem_id]"
  # Example: REMOTE_HOST=other.host rails "sync:problem[1590]"
  task :problem, [:id] => :environment do |_task, args|
    unless args[:id]
      puts 'Error: Please provide a problem ID.'
      puts 'Usage: rails "sync:problem[id]"'
      next
    end

    problem = Problem.find_by(id: args[:id])

    unless problem
      puts "Error: Problem with ID=#{args[:id]} not found."
      next
    end

    remote_host = ENV['REMOTE_HOST'] || '10.0.5.80'
    remote_rails_root = ENV['REMOTE_RAILS_ROOT'] || 'cafe_grader/web'

    remote_base = "#{remote_host}:#{remote_rails_root}/storage"

    puts "--> Syncing attachments for Problem ##{problem.id} from #{remote_host}"
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
