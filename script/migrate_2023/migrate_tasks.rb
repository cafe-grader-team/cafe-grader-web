# iterates over all directories in ../judge/ev
# for any directory with maching problem name
#   1. import each testcases into the problem new live dataset
#   2. parse all_tests.cfg for problem info
#   3. read any manager and store in active storage
#   4. read any checker
# if we migrate from pre-2023 but on some machine, we might need to drop some table first
#
# drop table active_storage_attachments, active_storage_variant_records, active_storage_blobs, jobs, datasets, evaluations, worker_datasets;

BASE_EV_DIRECTORY_GLOB = Rails.root.join '../judge/ev/*'
BASE_TASK_PDF_DIR = Rails.root.join 'data','tasks'
#BASE_EV_DIRECTORY = '/home/dae/old-evaluator/judge/ev/*'

def import_all_testcase(prob_ev_dir,problem)
  ds = Dataset.create(problem: problem,name: 'default')

  testcases_root = prob_ev_dir + 'test_cases'
  num = 1
  loop do
    file_root = testcases_root + "#{num}"
    break unless File.exist? file_root
    inp = File.read(file_root + "input-#{num}.txt").gsub(/\r$/, '')
    ans = File.read(file_root + "answer-#{num}.txt").gsub(/\r$/, '')
    puts "  got test case ##{num} of size #{inp.size} and #{ans.size}"

    tc = Testcase.create(num: num,code_name: num, weight: 10,group: num,dataset: ds)
    tc.inp_file.attach(io: StringIO.new(inp), filename: 'input.txt', content_type: 'text/plain',  identify: false)
    tc.ans_file.attach(io: StringIO.new(ans), filename: 'answer.txt', content_type: 'text/plain',  identify: false)
    tc.save
    num += 1
  end
  problem.live_dataset = ds
  problem.save
  return ds
end

# read all_test cfg file and return a hash information
def parse_all_test_cfg(filename,ds)
  on_run = false
  run = nil
  tests = nil
  scores = nil
  result = {}
  File.foreach(filename).each do |line|
    #time limit
    md = /time_limit_each\s+(\d+\.?\d*)/.match line
    result[:time_limit] = md[1].to_f if md

    # mem limit
    md = /mem_limit_each\s+(\d+\.?\d*)/.match line
    result[:mem_limit] = md[1].to_f if md

    # score_each
    md = /score_each\s+(\d+\.?\d*)/.match line
    result[:score_each] = md[1].to_f if md

    #run detect
    md = /run\s+(\d+)\s+do/.match line
    if (md && !on_run)
      run = md[1].to_i
      on_run = true
      tests = nil
      scores = nil
    end

    #test on run
    md = /tests\s+([\d,\s]*)/.match line
    if (md && on_run)
      tests = md[1].split(',').map { |x| x.to_i}
    end

    #score on run
    md = /scores\s+([\d,\s]*)/.match line
    if (md && on_run)
      scores = md[1].split(',').map { |x| x.to_i}
    end

    md = /end/.match line
    if (md && on_run)
      result[:group] = true if tests && tests.count > 1
      on_run = false
      result[run] = {tests: tests,scores: scores, errors: []}
      result[run][:errors] << "no test" unless tests
      result[run][:errors] << "no scores" unless scores
      tests.each do |num|
        ds.testcases.where(num: num).update(group: run,weight: scores[0], group_name: 'group '+run.to_s)
      end
    end
  end
  ds.memory_limit = result[:mem_limit]
  ds.time_limit =  result[:time_limit]
  ds.score_type = 'group_min' if result[:group]
  ds.save
  return result
end

def read_managers_from_ev(prob_ev_dir,ds)
  pi = ProblemImporter.new
  pi.import_dataset_from_dir(prob_ev_dir,ds.problem.name,
                             full_name: ds.problem.full_name,
                             dataset: ds,
                             do_testcase: false,
                             do_statement: false,
                             do_checker: false,
                            )
  pp pi.log if pi.got.count > 0
end

def read_default_checker(judge_script_dir =  Rails.root.join('../judge/scripts') )
  return unless @default_checker_text.nil?
  @default_checker_text = File.read(judge_script_dir + 'templates' + 'check.text').gsub(/\r$/, '')
  @default_checker_float = File.read(judge_script_dir + 'templates' + 'check.float').gsub(/\r$/, '')
  @default_checker_int = File.read(judge_script_dir + 'templates' + 'check.integer').gsub(/\r$/, '')
end

def cmp_default_checker(prob_checker, default_checker)
  return true if default_checker == prob_checker
  return true if default_checker == prob_checker.gsub('#!/usr/bin/ruby','#!/usr/bin/env ruby')
  return false
end

def read_checker_from_ev(prob_ev_dir,ds)
  read_default_checker
  check_file = prob_ev_dir + 'script' + 'check'
  unless check_file.exist?
    puts "skipping #{prob_ev_dir} because no check"
    return
  end
  my_checker = File.read(check_file).gsub(/\r$/, '')
  prob_name = prob_ev_dir

  md = /REAL_CHECK_SCRIPT = "(.*)"/.match(my_checker)

  if cmp_default_checker(my_checker , @default_checker_text)
    ds.evaluation_type = 'default'
    puts "Problem #{prob_name} has " + Rainbow("text checker").color(:deeppink)
  elsif cmp_default_checker(my_checker , @default_checker_float)
    ds.evaluation_type = 'relative'
    puts "Problem #{prob_name} has " + Rainbow("float checker").color(:seagreen)
  elsif cmp_default_checker(my_checker , @default_checker_int)
    ds.evaluation_type = 'default'
    puts "Problem #{prob_name} has " + Rainbow("int checker").color(:orange)
  elsif md
    ds.evaluation_type = 'custom_cafe'
    actual_checker = File.read(check_file.dirname + md[1])
    ds.checker.attach(io: StringIO.new(actual_checker),filename: md[1], content_type: 'application/octet-stream')
    puts "Problem #{prob_name} has " + Rainbow("CUSTOM CMS checker").color(:skyblue)
  else
    ds.evaluation_type = 'custom_cafe'
    ds.checker.attach(io: StringIO.new(my_checker),filename: 'checker', content_type: 'application/octet-stream')
    puts "Problem #{prob_name} has " + Rainbow("CUSTOM checker").color(:skyblue)
  end

  ds.save
end


def do_dir(prob_ev_dir)

  p = Problem.where(name: prob_ev_dir.basename.to_s).first
  unless p
    puts "cannot find Problem with name #{prob_ev_dir.basename.to_s}"
    return
  end

  #now p is the problem with the same name as the ev sub-dir
  ds = p.live_dataset

  # import all testcases in ev/{prob}/test_cases/xxx into a new live dataset ds
  ds = import_all_testcase(prob_ev_dir,p)

  r = parse_all_test_cfg(prob_ev_dir + 'test_cases/all_tests.cfg',ds)
  puts "Problem #{p.name} (#{p.id}) has grouped testcase" if (r[:group])

  # read manager
  read_managers_from_ev(prob_ev_dir,ds)

  # read checker
  read_checker_from_ev(prob_ev_dir,ds)
end

def main
  # re-import testcases and checker and managers as new Dataset
  Dir[BASE_EV_DIRECTORY_GLOB].each do |ev_dir|
    prob_ev_dir = Pathname.new ev_dir
    do_dir(prob_ev_dir)
  end

  # import pdf
  Problem.where.not(description_filename: nil).each do |p|
    file = BASE_TASK_PDF_DIR + p.id.to_s + p.description_filename
    if file.exist?
      p.statement.attach(io: File.open(file), filename: p.description_filename)
      puts "found pdf for #{p.name} at #{file.basename}"
    end
  end

  # re-seed language
  Language.seed

  # clear grader process
  GraderProcess.delete_all

  #puts "Recalculate old scores"
  Submission.joins(:problem).where('problems.full_score > 1').update_all("submissions.points = submissions.points/problems.full_score * 100")
  puts "DONE"
end

def tmp_test
  Dir[BASE_EV_DIRECTORY_GLOB].each do |ev_dir|
    prob_ev_dir = Pathname.new ev_dir
    p = Problem.where(name: prob_ev_dir.basename.to_s).first
    next unless p
    read_checker_from_ev(prob_ev_dir,p.live_dataset)
  end
end

# This runs the main migration
main
