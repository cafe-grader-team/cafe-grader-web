
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

describe User, "when re-register with the same e-mail" do

  before(:each) do
    @mary_email = 'mary@in.th'
    
    @time_first_register = Time.local(2008,5,10,9,00).gmtime

    @mary_first = mock_model(User, 
                             :login => 'mary1', 
                             :password => 'hello', 
                             :email => @mary_email,
                             :created_at => @time_first_register)
    @mary_second = User.new(:login => 'mary2', 
                            :password => 'hello', 
                            :email => @mary_email)
    User.stub!(:find_by_email).
      with(@mary_email, {:order => "created_at DESC"}).
      and_return(@mary_first)
  end

  class User
    public :enough_time_interval_between_same_email_registrations
  end

  it "should not be allowed if the time interval is less than 5 mins" do
    time_now = @time_first_register + 4.minutes
    Time.stub!(:now).and_return(time_now)

    @mary_second.enough_time_interval_between_same_email_registrations
    @mary_second.errors.length.should_not be_zero
  end

  it "should be allowed if the time interval is more than 5 mins" do
    time_now = @time_first_register + 6.minutes
    Time.stub!(:now).and_return(time_now)

    @mary_second.enough_time_interval_between_same_email_registrations
    @mary_second.errors.length.should be_zero
  end

end

describe User, "as a class" do

  it "should be able to generate random password" do
    password1 = User.random_password
    password2 = User.random_password
    
    password1.should_not == password2
  end
  
end

describe User, "when requesting problem description," do
  
  fixtures :users
  fixtures :problems

  before(:each) do
    @james = users(:james)
    @john = users(:john)
    @jack = users(:jack)
    @add = problems(:one)
    @easy = problems(:easy)
    @hard = problems(:hard)
  end

  it "should check if a problem is in user's contests" do
    @james.problem_in_user_contests?(@easy).should be_true
    @james.problem_in_user_contests?(@hard).should be_false

    @john.problem_in_user_contests?(@easy).should be_false
    @john.problem_in_user_contests?(@hard).should be_false
  end

  it "should be able to view problem in user's contests, when multicontests is on" do
    enable_multicontest
    @james.can_view_problem?(@easy).should be_true
    @jack.can_view_problem?(@easy).should be_true
    @jack.can_view_problem?(@hard).should be_true
  end

  it "should not be able to view problem not in user's contests, when multicontests is on" do
    enable_multicontest
    @john.can_view_problem?(@easy).should be_false
    @john.can_view_problem?(@hard).should be_false
    @james.can_view_problem?(@hard).should be_false
  end

  it "should be able to view all available problems, when multicontests is off" do
    disable_multicontest
    @john.can_view_problem?(@easy).should be_true
    @john.can_view_problem?(@hard).should be_true
    @james.can_view_problem?(@easy).should be_true
    @james.can_view_problem?(@hard).should be_true
  end

  it "should be able to view public problems, when multicontests is on" do
    enable_multicontest
    @john.can_view_problem?(@add).should be_true
    @james.can_view_problem?(@add).should be_true
  end

  def enable_multicontest
    c = Configuration.new(:key => 'system.multicontests',
                          :value_type => 'boolean',
                          :value => 'true')
    c.save
  end

  def disable_multicontest
    c = Configuration.new(:key => 'system.multicontests',
                          :value_type => 'boolean',
                          :value => 'false')
    c.save
  end
end
