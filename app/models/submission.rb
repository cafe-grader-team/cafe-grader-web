class Submission < ActiveRecord::Base

  belongs_to :language
  belongs_to :problem
  belongs_to :user

  validates_presence_of :source
  validates_length_of :source, :maximum => 100_000, :allow_blank => true, :message => 'too long'
  validates_length_of :source, :minimum => 1, :allow_blank => true, :message => 'too short'
  validate :must_specify_language
  validate :must_have_valid_problem

  before_save :assign_latest_number

  def self.find_last_by_user_and_problem(user_id, problem_id)
    last_sub = find(:first, 
                    :conditions => {:user_id => user_id,
                      :problem_id => problem_id},
                    :order => 'submitted_at DESC')
    return last_sub
  end

  def self.find_all_last_by_problem(problem_id)
    # need to put in SQL command, maybe there's a better way
    Submission.find_by_sql("SELECT * FROM submissions " +
			   "WHERE id = " +
			   "(SELECT MAX(id) FROM submissions AS subs " +
			   "WHERE subs.user_id = submissions.user_id AND " +
                           "problem_id = " + problem_id.to_s + " " +
			   "GROUP BY user_id)")
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

  def self.find_language_in_source(source)
    langopt = find_option_in_source(/^LANG:/,source)
    if language = Language.find_by_name(langopt)
      return language
    elsif language = Language.find_by_pretty_name(langopt)
      return language
    else
      return nil
    end
  end

  def self.find_problem_in_source(source)
    prob_opt = find_option_in_source(/^TASK:/,source)
    if problem = Problem.find_by_name(prob_opt)
      return problem
    else
      return nil
    end
  end

  # validation codes
  def must_specify_language
    return if self.source==nil
    self.language = Submission.find_language_in_source(self.source)
    errors.add_to_base("must specify programming language") unless self.language!=nil
  end

  def must_have_valid_problem
    return if self.source==nil
    if self.problem_id!=-1
      problem = Problem.find(self.problem_id)
    else
      problem = Submission.find_problem_in_source(self.source)
    end
    if problem==nil
      errors.add_to_base("must specify problem")
    elsif !problem.available
      errors.add_to_base("must specify valid problem")
    end
  end

  # callbacks
  def assign_latest_number
    latest = Submission.find_last_by_user_and_problem(self.user_id, self.problem_id)
    self.number = (latest==nil) ? 1 : latest.number + 1;
  end

end
