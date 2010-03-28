
require File.dirname(__FILE__) + '/../spec_helper'

describe UsersController, "when a new user registers" do

  before(:each) do
    # create john

    @john_info = {:login => 'john', 
      :full_name => 'John John', 
      :email => 'john@space.com'}
    @john = User.new(@john_info)

    @john_activation_key = "123456"

    @john.should_receive(:activation_key).
      any_number_of_times.
      and_return(@john_activation_key)

    Configuration.new(:key => 'system.online_registration',
                      :value_type => 'boolean',
                      :value => 'true').save

    get :new
    response.should render_template('users/new')
  end

  it "should show the new form again when user information is invalid" do
    User.should_receive(:new).with(any_args()).and_return(@john)
    @john.should_receive(:activated=).with(false)
    @john.should_receive(:valid?).and_return(false)
    @john.should_not_receive(:save)

    post :register, :login => @john_info[:login], 
                    :full_name => @john_info[:full_name], 
                    :email => @john_info[:email]    

    response.should render_template('users/new')
  end

  it "should create unactivated user and send e-mail with activation key" do
    User.should_receive(:new).with(any_args()).and_return(@john)
    @john.should_receive(:activated=).with(false)
    @john.should_receive(:valid?).and_return(true)
    @john.should_receive(:save).and_return(true)

    smtp_mock = mock("smtp")
    smtp_mock.should_receive(:send_message) do |msg,fr,to|
      to.should == [@john_info[:email]]
      msg.index(@john_activation_key).should_not be_nil
    end

    Net::SMTP.should_receive(:start).
      with(any_args()).
      and_yield(smtp_mock)

    post :register, :login => @john_info[:login], 
                    :full_name => @john_info[:full_name], 
                    :email => @john_info[:email]

    response.should render_template('users/new_splash')    
  end
  
  it "should create unactivated user and return error page when e-mail sending error" do
    User.should_receive(:new).with(any_args()).and_return(@john)
    @john.should_receive(:activated=).with(false)
    @john.should_receive(:valid?).and_return(true)
    @john.should_receive(:save).and_return(true)

    smtp_mock = mock("smtp")
    smtp_mock.should_receive(:send_message).
      and_throw(:error) 

    Net::SMTP.should_receive(:start).
      with(any_args()).
      and_yield(smtp_mock)

    post :register, :login => @john_info[:login], 
                    :full_name => @john_info[:full_name], 
                    :email => @john_info[:email]

    response.should render_template('users/email_error')    
  end
  
  it "should activate user with valid activation key" do
    login = @john_info[:login]
    User.should_receive(:find_by_login).
      with(login).
      and_return(@john)
    User.should_not_receive(:find_by_email)
    @john.should_receive(:valid?).and_return(true)
    @john.should_receive(:activated=).with(true)
    @john.should_receive(:save).and_return(true)

    get :confirm, :login => login, :activation => @john_activation_key

    response.should render_template('users/confirm')
  end

end
