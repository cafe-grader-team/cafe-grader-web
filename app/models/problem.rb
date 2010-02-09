class Problem < ActiveRecord::Base

  belongs_to :description
  has_many :test_pairs, :dependent => :delete_all

  named_scope :level, lambda { |level|
    { :conditions => { :level => level }}
  }

  named_scope :unavailable, { :conditions => { :available => false }}


  validates_presence_of :name
  validates_format_of :name, :with => /^\w+$/
  validates_presence_of :full_name

  DEFAULT_TIME_LIMIT = 1
  DEFAULT_MEMORY_LIMIT = 32
  
  def test_pair_count
    @test_pair_count ||= test_pairs.size
  end

  def uses_random_test_pair?
    test_pair_count != 0
  end

  def random_test_pair(forbidden_numbers=nil)
    if forbidden_numbers.length < test_pair_count
      begin
        test_num = 1 + rand(test_pair_count)
      end while forbidden_numbers!=nil and forbidden_numbers.include? test_num
    else
      test_num = 1 + rand(test_pair_count)
    end
    test_pairs.find_by_number test_num
  end

  def self.find_available_problems
    find(:all, :conditions => {:available => true}, :order => "date_added DESC")
  end

  # TODO: may try to optimize this using cache
  def self.available_problem_count
    return Problem.find_available_problems.length
  end

  def self.create_from_import_form_params(params, old_problem=nil)
    problem = old_problem || Problem.new
    import_params = Problem.extract_params_and_check(params, problem)

    if not problem.valid?
      return problem, 'Error importing'
    end

    problem.full_score = 100
    problem.date_added = Time.new
    problem.test_allowed = true
    problem.output_only = false
    problem.available = false

    if not problem.save
      return problem, 'Error importing'
    end

    import_to_db = params.has_key? :import_to_db

    importer = TestdataImporter.new(problem)

    if not importer.import_from_file(import_params[:file], 
                                     import_params[:time_limit], 
                                     import_params[:memory_limit],
                                     import_to_db)
      problem.errors.add_to_base('Import error.')
    end

    return problem, importer.log_msg
  end

  protected

  def self.to_i_or_default(st, default)
    if st!=''
      st.to_i
    else
      default
    end
  end

  def self.extract_params_and_check(params, problem)
    time_limit = Problem.to_i_or_default(params[:time_limit],
                                         DEFAULT_TIME_LIMIT)
    memory_limit = Problem.to_i_or_default(params[:memory_limit],
                                           DEFAULT_MEMORY_LIMIT)

    if time_limit==0 and time_limit_s!='0'
      problem.errors.add_to_base('Time limit format errors.')
    elsif time_limit<=0 or time_limit >60
      problem.errors.add_to_base('Time limit out of range.')
    end

    if memory_limit==0 and memory_limit_s!='0'
      problem.errors.add_to_base('Memory limit format errors.')
    elsif memory_limit<=0 or memory_limit >512
      problem.errors.add_to_base('Memory limit out of range.')
    end

    if params[:file]==nil or params[:file]==''
      problem.errors.add_to_base('No testdata file.')
    end

    file = params[:file]

    if problem.errors.length!=0
      return problem
    end

    problem.name = params[:name]
    if params[:full_name]!=''
      problem.full_name = params[:full_name]
    else
      problem.full_name = params[:name]
    end

    return {
      :time_limit => time_limit,
      :memory_limit => memory_limit,
      :file => file
    }      
  end

end
