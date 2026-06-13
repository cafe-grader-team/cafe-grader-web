# this script sync (with rsync) active storages Attachment
# in *attachments* from the remote host to this machine

remote_rails_root = 'cafe_grader/web'
remote_host = '10.0.5.80'

# prefix dir
REMOTE_BASE = "#{remote_host}:#{remote_rails_root}/storage"


# sync a single attachment
# skip if null
def sync_single_attachment(attachment)
  return nil unless attachment
  key = attachment.blob.key
  src = [REMOTE_BASE, key[0..1], key[2..3], key].join '/'
  dst = Rails.root.join 'storage', key[0..1], key[2..3], key
  dst.dirname.mkpath
  cmd = "rsync #{src} #{dst}"

  # execute
  `#{cmd}`
  return cmd
end

def sync_collection(attachments)
  count = attachments.count
  attachments.each.with_index do |att, idx|
    executed_cmd = sync_single_attachment(att)
    puts "#{idx + 1}/#{count} #{cmd}"
  end
end

def sync_problem(problem)
  puts "statement #{problem.statement.blob.key}" if problem.statement.attached? && sync_single_attachment(problem.statement)
  puts "attachment #{problem.attachment.blob.key}" if problem.attachment.attached? && sync_single_attachment(problem.attachment)

  problem.datasets.each do |ds|
    # checker
    puts "  checker #{ds.checker.attachment.blob.filename}" if sync_single_attachment(ds.checker.attachment)
    ds.managers.each { |m| puts "  managers [#{m.blob.filename}]" if sync_single_attachment(m) }
    ds.initializers.each { |m| puts "  initializer [#{m.blob.filename}]" if sync_single_attachment(m) }
    ds.data_files.each { |m| puts "  data files [#{m.blob.filename}]" if sync_single_attachment(m) }
    ds.testcases.each do |tc|
      puts "  input #{tc.code_name} #{tc.inp_file.blob.key}" if sync_single_attachment tc.inp_file
      puts "  ans   #{tc.code_name} #{tc.inp_file.blob.key}" if sync_single_attachment tc.ans_file
    end
  end
end


# this sync everything except compiled file
# attachments = ActiveStorage::Attachment.where.not(name: 'compiled_files').includes(:blob)
# sync_collection(attachments)

sync_problem(Problem.find(1590))
