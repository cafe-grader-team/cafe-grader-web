
require File.dirname(__FILE__) + '/../spec_helper'

describe TestController do

  before(:each) do
    @john = mock(User, :id => "1", :login => 'john')
    @john_result = mock(TestRequest, :id => "1", :user_id => @john.id)
    @mary_result = mock(TestRequest, :id => "2", :user_id => @john.id + '1')
    User.should_receive(:find).at_least(:once).with(@john.id).and_return(@john)
  end

  it "should let user see her testing result" do
    TestRequest.should_receive(:find).with(@john_result.id).
      and_return(@john_result)
    get 'result', {:id => @john_result.id}, {:user_id => @john.id}
    response.should be_success
  end

  it "should not let user see other's testing result" do
    TestRequest.should_receive(:find).with(@mary_result.id).
      and_return(@mary_result)
    get 'result', {:id => @mary_result.id}, {:user_id => @john.id}
    response.should redirect_to(:action => 'index')
  end
  
end

