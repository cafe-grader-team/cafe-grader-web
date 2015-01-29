class Submission < ActiveRecord::Base

  belongs_to :language
  belongs_to :problem
  belongs_to :user

  before_validation :assign_problem
  before_validation :assign_language

  validates_presence_of :source
  validates_length_of :source, :maximum => 100_000, :allow_blank => true, :message => 'too long'
  validates_length_of :source, :minimum => 1, :allow_blank => true, :message => 'too short'

  validates_presence_of :output
  validates_length_of :output, :maximum => 100_000, :allow_blank => true, :message => 'too long'
  validates_length_of :output, :minimum => 1, :allow_blank => true, :message => 'too short'

  validate :must_have_valid_problem
  validate :must_specify_language

  before_save :assign_latest_number_if_new_recond

  def self.find_last_by_user_and_problem(user_id, problem_id)
    last_sub = find(:first, 
                    :conditions => {:user_id => user_id,
                      :problem_id => problem_id},
                    :order => 'number DESC')
    return last_sub
  end

  def self.find_all_last_by_problem(problem_id)
    # need to put in SQL command, maybe there's a better way
    Submission.find_by_sql("SELECT * FROM submissions " +
			   "WHERE id = " +
			   "(SELECT MAX(id) FROM submissions AS subs " +
			   "WHERE subs.user_id = submissions.user_id AND " +
                           "problem_id = " + problem_id.to_s + " " +
			   "GROUP BY user_id) " +
                           "ORDER BY user_id")
  end

  def self.find_in_range_by_user_and_problem(user_id, problem_id,since_id,until_id)
    records = Submission.where(problem_id: problem_id,user_id: user_id)
    records = records.where('id >= ?',since_id) if since_id > 0
    records = records.where('id <= ?',until_id) if until_id > 0
    records.all
  end

  def self.find_last_for_all_available_problems(user_id)
    submissions = Array.new
    problems = Problem.find_available_problems
    problems.each do |problem|
      sub = Submission.find_last_by_user_and_problem(user_id, problem.id)
      submissions << sub if sub!=nil
    end
    submissions
  end

  def self.find_by_user_problem_number(user_id, problem_id, number)
    Submission.find(:first,
                    :conditions => {
                      :user_id => user_id,
                      :problem_id => problem_id,
                      :number => number
                    })
  end

  def self.find_all_by_user_problem(user_id, problem_id)
    Submission.find(:all,
                    :conditions => {
                      :user_id => user_id,
                      :problem_id => problem_id,
                    })
  end

  def download_filename
    if self.problem.output_only
      return self.source_filename
    else
      timestamp = self.submitted_at.localtime.strftime("%H%M%S")
      return "#{self.problem.name}-#{timestamp}.#{self.language.ext}"
    end
  end

  protected

  def self.find_option_in_source(option, source)
    if source==nil
      return nil
    end
    i = 0
    source.each_line do |s|
      if s =~ option
	words = s.split
	return words[1]
      end
      i = i + 1
      if i==10
	return nil
      end
    end
    return nil
  end

  def self.find_language_in_source(source, source_filename="")
    langopt = find_option_in_source(/^LANG:/,source)
    if langopt
      return (Language.find_by_name(langopt) || 
              Language.find_by_pretty_name(langopt))
    else
      if source_filename
        return Language.find_by_extension(source_filename.split('.').last)
      else
        return nil
      end
    end
  end

  def self.find_problem_in_source(source, source_filename="")
    prob_opt = find_option_in_source(/^TASK:/,source)
    if problem = Problem.find_by_name(prob_opt)
      return problem
    else
      if source_filename
        return Problem.find_by_name(source_filename.split('.').first)
      else
        return nil
      end
    end
  end

  def assign_problem
    if self.problem_id!=-1
      begin
        self.problem = Problem.find(self.problem_id)
      rescue ActiveRecord::RecordNotFound
        self.problem = nil
      end
    else
      self.problem = Submission.find_problem_in_source(self.source,
                                                       self.source_filename)
    end
  end

  def assign_language
    self.language = Submission.find_language_in_source(self.source,
                                                       self.source_filename)
  end

  # validation codes
  def must_specify_language
    return if self.source==nil

    # for output_only tasks
    return if self.problem!=nil and self.problem.output_only
    
    if self.language==nil
      errors.add('source',"must specify programming language") unless self.language!=nil
    end
  end

  def must_have_valid_problem
    return if self.source==nil
    if self.problem==nil
      errors.add('problem',"must be specified.")
    elsif (!self.problem.available) and (self.new_record?)
      errors.add('problem',"must be valid.")
    end
  end

  # callbacks
  def assign_latest_number_if_new_recond
    return if !self.new_record?
    latest = Submission.find_last_by_user_and_problem(self.user_id, self.problem_id)
    self.number = (latest==nil) ? 1 : latest.number + 1;
  end

end
