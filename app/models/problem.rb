class Problem < ActiveRecord::Base

  belongs_to :description

  validates_presence_of :name
  validates_format_of :name, :with => /^\w+$/
  validates_presence_of :full_name
  
  def self.find_available_problems
    find(:all, :conditions => {:available => true}, :order => "date_added DESC")
  end

  def self.new_from_import_form_params(params)
    problem = Problem.new

    # form error checking

    time_limit_s = params[:time_limit]
    memory_limit_s = params[:memory_limit]

    time_limit_s = '1' if time_limit_s==''
    memory_limit_s = '32' if memory_limit_s==''

    time_limit = time_limit_s.to_i
    memory_limit = memory_limit_s.to_i

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

    if not problem.valid?
      return problem
    end

    importer = TestdataImporter.new

    if not importer.import_from_file(problem.name, 
                                             file, 
                                             time_limit, 
                                             memory_limit)
      problem.errors.add_to_base('Import error.')
    end

    problem.full_score = 100
    problem.date_added = Time.new
    problem.test_allowed = true
    problem.output_only = false
    problem.available = false
    return problem, importer.log_msg
  end

end
