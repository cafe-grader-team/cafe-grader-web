class Submission < ActiveRecord::Base

  belongs_to :language
  belongs_to :problem
  belongs_to :user

  def self.find_by_user_and_problem(user_id, problem_id)
    subcount = count(:conditions => "user_id = #{user_id} AND problem_id = #{problem_id}")
    if subcount != 0
      last_sub = find(:first, 
		      :conditions => {:user_id => user_id,
			:problem_id => problem_id},
		      :order => 'submitted_at DESC')
    else
      last_sub = nil
    end
    return subcount, last_sub
  end

  def self.find_last_by_problem(problem_id)
    # need to put in SQL command, maybe there's a better way
    Submission.find_by_sql("SELECT * FROM submissions " +
			   "WHERE id = " +
			   "(SELECT MAX(id) FROM submissions AS subs " +
			   "WHERE subs.user_id = submissions.user_id AND " +
                           "problem_id = " + problem_id.to_s + " " +
			   "GROUP BY user_id)")
  end

  def self.find_option_in_source(option, source)
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

end
