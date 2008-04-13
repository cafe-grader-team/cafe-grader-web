
require File.dirname(__FILE__) + '/../spec_helper'

describe TestRequest do

  before(:each) do
    @problem = mock_model(Problem)
    @user = mock_model(User)
    @submission = mock_model(Submission)
  end

  it "should validates that problem exists" do
    test_request = TestRequest.new(:user => @user,
                                   :problem => nil,
                                   :submission => @submission,
                                   :input_file_name => "somefile")
    test_request.save.should == false
    test_request.errors['problem'].should_not be_nil
  end

  it "should validates that problem is available" do
    @problem.should_receive(:available).and_return(false)
    test_request = TestRequest.new(:user => @user,
                                   :problem => @problem,
                                   :submission => @submission,
                                   :input_file_name => "somefile")
    test_request.save.should == false
  end

  it "should validates valid submission" do
    @problem.should_receive(:available).and_return(true)
    test_request = TestRequest.new(:user_id => @user.id,
                                   :problem => @problem,
                                   :submission => nil,
                                   :input_file_name => "somefile")
    test_request.save.should == false
  end

end
