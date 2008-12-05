
require File.dirname(__FILE__) + '/../spec_helper'

describe User do

  before(:each) do 
    @password = "hello"
    @salt = "123"
    @john = stub_model(User, :salt => @salt,
                       :hashed_password => User.encrypt(@password,@salt))
  end

  it "should be authenticated if activated" do
    @john.should_receive(:activated).and_return(true)
    @john.authenticated?(@password).should == true
  end

  it "should not be authenticated if inactivated" do
    @john.should_receive(:activated).and_return(false)
    @john.authenticated?(@password).should == false
  end

  it "should not be authenticated if incorrect password is provided" do
    @john.should_receive(:activated).and_return(true)
    @john.should_receive(:hashed_password).and_return("byebye")
    @john.authenticated?(@password).should == false
  end
  
end

describe User, "during registration" do
  
  class User
    public :encrypt_new_password
  end

  before(:each) do
    @john = User.new(:login => 'john', :password => 'hello')
    @john.encrypt_new_password
  end
  
  it "should produce and accept activation key" do
    activation_key = @john.activation_key

    @john.verify_activation_key(activation_key).should == true
  end
  
  it "should not accept invalid activation key" do
    @john.verify_activation_key("12345").should == false
  end
  
end

describe User, "as a class" do

  it "should be able to generate random password" do
    password1 = User.random_password
    password2 = User.random_password
    
    password1.should_not == password2
  end
  
end
