
def filter_filename_for_testrun(testrun, filename_list)
  l = []
  regex = Regexp.new("^(#{testrun}[a-z]*|#{testrun}-.*)$")
  filename_list.each do |filename|
    if regex.match(filename)
      l << filename
    end
  end
  l
end

def build_testrun_info(num_testruns, input_filename_list)
  info = []
  num_testcases = 0
  num_testruns.times do |i|
    r = i+1
    testrun_info = []
    filenames = filter_filename_for_testrun(r, input_filename_list)
    filenames.each do |fname|
      num_testcases += 1
      testrun_info << [num_testcases,fname]
    end
    info << testrun_info
  end
  info
end

