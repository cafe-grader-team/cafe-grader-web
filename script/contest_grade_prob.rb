#!/usr/bin/env ruby

APP_PATH = File.expand_path('../../config/application',  __FILE__)
require File.expand_path('../../config/boot',  __FILE__)
require APP_PATH

# set Rails.env here if desired
Rails.application.require_environment!

def main
  if ARGV.length != 1
    puts "Usage: contest_grade_prob.rb [problem_name]"
    exit(0)
  end

  problem_name = ARGV[0]
  problem = Problem.where(:name => problem_name).first
  if !problem
    puts "Problem not found"
    exit(0)
  end

  problem.full_score = 100
  problem.save

  test_pair = TestPair.get_for(problem, true)
  
  User.all.each do |u|
    puts "#{u.login}:"
    submissions = Submission.find_all_by_user_problem(u.id, problem.id)
    submissions.each do |sub|
      result = test_pair.grade(sub.output)
      result2 = test_pair.grade(sub.source)
      if result2[:score] > result[:score]
        result = result2
        puts "Use source field (#{sub.id})"
      end

      full_score = result[:full_score]
      sub.points = result[:score]*100 / full_score
      sub.grader_comment = result[:msg]
      sub.graded_at = Time.now.gmtime
      sub.save
    end
  end
end

main
