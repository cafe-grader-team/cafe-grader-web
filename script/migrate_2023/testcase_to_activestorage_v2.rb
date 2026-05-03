# Fixed version of testcase_to_activestorage.rb. Differences from the original:
#   * answer attachment uses filename: 'answer.txt' (was 'input.txt')
#   * iterates with find_each (was Testcase.all.each — would OOM on large DBs)
#   * skips testcases that already have both blobs attached (idempotent re-runs)
#   * skips testcases whose input/sol columns are NULL (StringIO.new(nil) raises)

def migrate_one_testcase(testcase)
  if testcase.inp_file.attached? && testcase.ans_file.attached?
    puts "  already attached, skipping"
    return
  end
  if testcase.input.nil? || testcase.sol.nil?
    puts "  input or sol is nil, skipping"
    return
  end

  testcase.inp_file.attach(io: StringIO.new(testcase.input), filename: 'input.txt',  content_type: 'text/plain', identify: false)
  testcase.ans_file.attach(io: StringIO.new(testcase.sol),   filename: 'answer.txt', content_type: 'text/plain', identify: false)
end

Testcase.find_each.with_index do |tc, idx|
  puts "Importing Testcase #{idx}: ##{tc.id}"
  migrate_one_testcase(tc)
end
