
def migrate_one_testcase(testcase)
  testcase.inp_file.attach(io: StringIO.new(testcase.input), filename: 'input.txt', content_type: 'text/plain',  identify: false)
  testcase.ans_file.attach(io: StringIO.new(testcase.sol), filename: 'input.txt', content_type: 'text/plain',  identify: false)
end

Testcase.all.each.with_index do |tc,idx|
  puts "Importing Testcase #{idx}: ##{tc.id}"
  migrate_one_testcase(tc)
end
