require File.dirname(__FILE__) + '/../spec_helper'

module ConfigHelperMethods
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

describe MainController, "when a user comes to list page" do

  it "should redirect user to login page when unlogged-in user try to access main/list" do
    get 'list'
    response.should redirect_to(:action => 'login')
  end

end

describe MainController, "when a logged in user comes to list page, with multicontests off" do
  integrate_views

  include ConfigHelperMethods

  fixtures :users
  fixtures :problems
  fixtures :contests

  before(:each) do
    disable_multicontest
  end

  it "should list available problems" do
    john = users(:john)
    get "list", {}, {:user_id => john.id}

    response.should render_template 'main/list'
    response.should have_text(/add/)
    response.should have_text(/easy_problem/)
    response.should have_text(/hard_problem/)
  end

end

describe MainController, "when a logged in user comes to list page, with multicontests on" do
  integrate_views

  include ConfigHelperMethods

  fixtures :users
  fixtures :problems
  fixtures :contests

  before(:each) do
    enable_multicontest
  end

  it "should list only available public problems to users with no contest assigned" do
    john = users(:john)
    get "list", {}, {:user_id => john.id}
    
    response.should render_template('main/list')
    response.should have_text(/add/)
    response.should_not have_text(/easy_problem/)
    response.should_not have_text(/hard_problem/)
  end

  it "should list available problems on a specific contest" do
    james = users(:james)
    get "list", {}, {:user_id => james.id}

    response.should render_template('main/list')
    response.should have_text(/add/)
    response.should have_text(/easy_problem/)
    response.should_not have_text(/hard_problem/)
  end

  it "should shows available problems by contests" do
    james = users(:james)
    get "list", {}, {:user_id => james.id}

    response.should render_template('main/list')
    response.should have_text(Regexp.new('Contest A.*easy_problem', Regexp::MULTILINE))
  end

  it "should shows available problems by contests; problems belonging to more the one contest should appear many times" do
    jack = users(:jack)
    get "list", {}, {:user_id => jack.id}

    response.should render_template('main/list')
    response.should have_text(Regexp.new('Contest A.*easy_problem.*Contest B.*easy_problem', Regexp::MULTILINE))
    response.should have_text(Regexp.new('Contest B.*hard_problem', Regexp::MULTILINE))
  end
end

describe MainController, "when a user loads sources and compiler messages" do

  before(:each) do
    @problem = mock(Problem, :name => 'test', :output_only => false)
    @language = mock(Language, :name => 'cpp', :ext => 'cpp')
    @submission = mock(Submission,
                       :id => 1,
                       :user_id => 1,
                       :problem => @problem,
                       :language => @language,
                       :source => 'sample source',
                       :compiler_message => 'none')

    @user = mock(User, :id => 1, :login => 'john')
    @user.should_receive(:update_start_time).at_most(:once)

    @another_user = mock(User, :id => 2, :login => 'mary')
    @another_user.should_receive(:update_start_time).at_most(:once)

    User.should_receive(:find).
      with(1).any_number_of_times.
      and_return(@user)
    User.should_receive(:find).
      with(2).any_number_of_times.
      and_return(@another_user)
    Submission.should_receive(:find).
      any_number_of_times.with(@submission.id.to_s).
      and_return(@submission)
  end

  it "should let user sees her own source" do
    @submission.should_receive(:download_filename).and_return("foo.c")
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


