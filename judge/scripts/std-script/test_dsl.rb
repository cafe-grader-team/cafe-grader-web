class DSLNode
  def DSLNode.scalar_attr(*names)
    names.each do |name|
      define_method name do |*a|        
        if a.length == 0
          instance_variable_get( "@#{name}" )
        else
          instance_variable_set( "@#{name}", a[0] )
        end
      end
    end
  end

  def DSLNode.array_attr(*names)
    names.each do |name|
      define_method name do |*a|
        if a.length == 0
          instance_variable_get( "@#{name}" )
        else
          instance_variable_set( "@#{name}", a )
        end
      end
    end
  end
end

class Problem < DSLNode
  def initialize
    @runs = []
    @tests = []
  end

  def Problem.getter(name, plural_name, each_name)
    eval "def get_#{name}(index) \n \
      if defined?(@tests) and @tests[index] != nil \n \
        if @tests[index].#{name} != nil \n \                    
          return @tests[index].#{name} \n \
        end \n \
      end \n \
      \n \
      (1..@runs.length-1).each do |i| \n \
        run = @runs[i] \n \
        k = run.tests.index(index) \n \
        if k == nil \n \
          next \n \
        end \n \
        \n \
        if run.#{plural_name} != nil && run.#{plural_name}[k] != nil \n \
          return run.#{plural_name}[k] \n \
        end \n \
        \n \
        if run.#{each_name} != nil \n \
          return run.#{each_name} \n \
        end \n \
      end \n \
      \n \
      if @#{each_name} != nil \n \
        return @#{each_name} \n \
      else \n \
        raise 'The problem is malformed (possibly in more than one way)!' \n \
      end \n \
    end"
  end

  scalar_attr :num_tests, :full_score, :score_each, :time_limit_each, :mem_limit_each
  array_attr :runs, :tests
  getter "score", "scores", "score_each"
  getter "mem_limit", "mem_limits", "mem_limit_each"
  getter "time_limit", "time_limits", "time_limit_each"

  def run(index, &block)
    new_run = Run.new
    new_run.instance_eval &block
    @runs[index] = new_run
  end

  def test(index, &block)
    new_test = Test.new
    new_test.instance_eval &block
    @tests[index] = new_test
  end

  def read_test(index)
    filename = ENV['PROBLEM_HOME'] + "/test_cases/#{index}/test.cfg"
    if File.exists?(filename)
      @tests[index] ||= Test.new
      content = File.read(filename)
      @tests[index].instance_eval content
    end
  end

  def Problem.set_instance(prob)
    @instance = prob
  end

  def Problem.get_instance
    return @instance
  end

  def well_formed?
    # Check if run 1 to run @runs.length are present.
    (1..(@runs.length-1)).each do |i|
      if @runs[i] == nil
        puts "run #{i} is not present"
        return false
      end
    end

    # Check if all tests are in one and only one run.
    test_present = []
    (1..(@num_tests)).each do |i|
      test_present[i] = false
    end
    (1..(@runs.length-1)).each do |j|
      run = @runs[j]
      if run.tests!=nil
        run.tests.each do |t|
          if test_present[t] == false
            test_present[t] = true
          else
            puts "test #{t} is present in more than one run"
            return false
          end
        end
      end
    end
    (1..(@num_tests)).each do |i|
      if test_present[i] == false
        puts "test #{i} is not present"
        return false
      end
    end

    # Check if we can find the score, mem limit, and time limit for all tests.
    (1..(@num_tests)).each do |i|
      begin
        get_score i
      rescue
        puts "cannot get score for test #{i}"
        return false
      end

      begin
        get_mem_limit i
      rescue
        puts "cannot get mem limit for test #{i}"
        return false
      end

      begin
        get_time_limit i
      rescue
        puts "cannot get time limit for test #{i}"
        return false
      end  
    end

    return true
  end
end

class Run < DSLNode
  scalar_attr :score_each, :time_limit_each, :mem_limit_each
  array_attr :tests, :scores, :time_limits, :mem_limits
end

class Test < DSLNode
  scalar_attr :score, :time_limit, :mem_limit  
end

def problem(&blk)
  prob = Problem.new
  prob.instance_eval &blk
  Problem.set_instance prob
  p = Problem.get_instance
  (1..(p.num_tests)).each do |i|
    p.read_test i
  end
  p.well_formed?
end
