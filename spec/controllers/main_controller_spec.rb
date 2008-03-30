
require File.dirname(__FILE__) + '/../spec_helper'

describe MainController do

  before(:each) do
    @problem = mock(Problem, :name => 'test')
    @language = mock(Language, :name => 'cpp', :ext => 'cpp')
    @submission = mock(Submission,
                       :id => 1,
                       :user_id => 1,
                       :problem => @problem,
                       :language => @language,
                       :source => 'sample source',
                       :compiler_message => 'none')
    @user = mock(User, :id => 1, :login => 'john')
    Submission.should_receive(:find).with(@submission.id.to_s).and_return(@submission)
  end

  it "should let user sees her own source" do
    get 'source', {:id => @submission.id}, {:user_id => 1}
    response.should be_success
  end

  it "should let user sees her own compiler message" do
    get 'compiler_msg', {:id => @submission.id}, {:user_id => 1}
    response.should be_success
  end

  it "should not let user sees other user's source" do
    get 'source', {:id => @submission.id}, {:user_id => 2}
    flash[:notice].should =~ /[Ee]rror/ 
    response.should redirect_to(:action => 'list')
  end

  it "should not let user sees other user's compiler message" do
    get 'compiler_msg', {:id => @submission.id}, {:user_id => 2}
    flash[:notice].should =~ /[Ee]rror/ 
    response.should redirect_to(:action => 'list')
  end

end
