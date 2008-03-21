
require File.dirname(__FILE__) + '/../spec_helper'

describe Submission, "when verifying user submission" do

  before(:each) do
    @submission = Submission.new
    @submission.source = <<SOURCE
/*
LANG: C++
TASK: testproblem
*/
SOURCE
  end

  it "should find language in source" do
    langcpp = stub(Language, :name => 'cpp', :ext => 'cpp')
    Language.should_receive(:find_by_name).with('C++').and_return(langcpp)
    Submission.find_language_in_source(@submission.source).should == langcpp
  end

  it "should find problem in source, when there is any" do
    problem = stub(Problem, :name => 'testproblem')
    Problem.should_receive(:find_by_name).with('testproblem').and_return(problem)
    Submission.find_problem_in_source(@submission.source).should == problem
  end

  it "should return nil when it cannot find problem in source" do
    Submission.find_problem_in_source(<<SOURCE
/*
LANG: C
*/
SOURCE
).should == nil
  end

end
