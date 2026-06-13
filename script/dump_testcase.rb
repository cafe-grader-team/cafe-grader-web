
def check_problem(prob_names)
  not_found = []
  prob_names.each do |name|
    not_found << name if Problem.where(name: name).count == 0
  end
  if not_found.count > 0
    puts "Following problem names cannot be found\n   #{not_found.join ' '}"
    exit 0
  end
end

def dump(problem,root_path)
  puts "Doing problem #{problem.name}"
  p = Pathname.new(root_path).join(problem.name).expand_path
  puts "  Creating directory #{p}"
  FileUtils.mkdir_p(p)
  #testcase
  problem.testcases.each do |tc|
    input_path =  p + "test_cases/#{tc.num}/input-#{tc.num}.txt"
    answer_path = p + "test_cases/#{tc.num}/answer-#{tc.num}.txt"
    FileUtils.mkdir_p(input_path.split[0])
    File.write(input_path,tc.input)
    File.write(answer_path,tc.sol)
    puts "  testcase #{tc.num}"
  end
  all_tests_path = p + "test_cases/all_tests.cfg"
  File.write(all_tests_path,problem.build_legacy_config_file)

  #lockfile
  lock_file_path = p + 'lockfile'
  File.write(lock_file_path,'')

  #script folder
  # this is DEFAULT
  script_path = p + 'script/check'
  FileUtils.mkdir_p(script_path.split[0])
  FileUtils.copy_file(@options[:check_path],script_path)
end

#main
@options = {
  all: false,
  output_dir: '../judge/ev_dump/',
  check_path: '../judge/scripts/std-script/check.text',
}
option_parser = OptionParser.new(ARGV)
option_parser.banner = "Usage: rails example.rb [options] prob_1 prob_2 ..."
option_parser.on("-a",'--all', 'Dump all problems')
option_parser.on('-o', '--output dir','Destination directory, relative to rails root')
option_parser.on('-c', '--check-script dir','Path to the standard check script file, relative to rails root')

#we first remove '--' and parse into options
args = option_parser.order!(ARGV, into: @options)

if args.count == 0 && @options[:all] == false
  puts option_parser.help
  puts "\n  you need to specify problem names!!!"
end

puts '--------- final ------------'
p @options
p args

puts "working dir = #{Dir.pwd}"
p = Pathname.new(Dir.pwd) + @options[:output_dir]
puts "output root path is #{p.expand_path}"

#check problem
check_problem(args)

if @options[:all]
  probs = Problem.all
else
  probs = Problem.where(name: args)
end

probs.each do |p|
  dump(p,@options[:output_dir])
end
puts "done!"
