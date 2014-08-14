class Problem < ActiveRecord::Base

  belongs_to :description
  has_and_belongs_to_many :contests, :uniq => true
  has_many :test_pairs, :dependent => :delete_all

  validates_presence_of :name
  validates_format_of :name, :with => /^\w+$/
  validates_presence_of :full_name

  scope :available, :conditions => {:available => true}

  DEFAULT_TIME_LIMIT = 1
  DEFAULT_MEMORY_LIMIT = 32

  def self.find_available_problems
    Problem.available.all(:order => "date_added DESC")
  end

  def self.create_from_import_form_params(params, old_problem=nil)
    org_problem = old_problem || Problem.new
    import_params, problem = Problem.extract_params_and_check(params, 
                                                              org_problem)

    if !problem.errors.empty?
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
                                     import_params[:checker_name],
                                     import_to_db)
      problem.errors.add_to_base('Import error.')
    end

    return problem, importer.log_msg
  end

  def self.download_file_basedir
    return "#{Rails.root}/data/tasks"
  end
  
  protected

  def self.to_i_or_default(st, default)
    if st!=''
      result = st.to_i
    end
    result ||= default 
  end

  def self.to_f_or_default(st, default)
    if st!=''
      result = st.to_f
    end
    result ||= default
  end

  def self.extract_params_and_check(params, problem)
    time_limit = Problem.to_f_or_default(params[:time_limit],
                                         DEFAULT_TIME_LIMIT)
    memory_limit = Problem.to_i_or_default(params[:memory_limit],
                                           DEFAULT_MEMORY_LIMIT)

    if time_limit<=0 or time_limit >60
      problem.errors.add_to_base('Time limit out of range.')
    end

    if memory_limit==0 and params[:memory_limit]!='0'
      problem.errors.add_to_base('Memory limit format errors.')
    elsif memory_limit<=0 or memory_limit >512
      problem.errors.add_to_base('Memory limit out of range.')
    end

    if params[:file]==nil or params[:file]==''
      problem.errors.add_to_base('No testdata file.')
    end

    checker_name = 'text'
    if ['text','float'].include? params[:checker]
      checker_name = params[:checker]
    end

    file = params[:file]

    if !problem.errors.empty?
      return nil, problem
    end

    problem.name = params[:name]
    if params[:full_name]!=''
      problem.full_name = params[:full_name]
    else
      problem.full_name = params[:name]
    end

    return [{
              :time_limit => time_limit,
              :memory_limit => memory_limit,
              :file => file,
              :checker_name => checker_name
            },
            problem]
  end

end
