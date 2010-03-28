require 'delorean'

require File.dirname(__FILE__) + '/../spec_helper'
require File.dirname(__FILE__) + '/../config_spec_helper'

describe UserAdminController, "when manage contest" do

  include ConfigSpecHelperMethods

  fixtures :users
  fixtures :problems
  fixtures :contests
  fixtures :roles

  def change_users_contest_to(user_login_list, contest, reset_timer=false)
    post_data = {
      :contest => {:id => contest.id},
      :operation => 'assign',
      :login_list => user_login_list
    }
    post_data[:reset_timer] = true if reset_timer
    post 'manage_contest', post_data, {:user_id => @admin_user.id}
  end

  before(:each) do
    @admin_user = users(:mary)
    @contest_b = contests(:contest_b)
    @james = users(:james)
    @jack = users(:jack)

    set_contest_time_limit('3:00')
    set_indv_contest_mode
  end

  it "should allow admin to see contest management page" do
    get 'contest_management', {}, {:user_id => @admin_user.id}

    response.should render_template 'user_admin/contest_management'
  end

  it "should change users' contest" do
    change_users_contest_to("james\njack", @contest_b)
    response.should redirect_to :action => 'contest_management'

    @james.contests(true).should include @contest_b
    @jack.contests(true).should_not include @contest_a
  end

  it "should reset users' timer when their contests change" do
    @james.update_start_time

    Delorean.time_travel_to(190.minutes.since) do
      @james.contest_finished?.should be_true

      change_users_contest_to("james", @contest_b, true)

      @james.contest_finished?.should be_false
    end
  end

  it "should set forced_logout flag for users when their contests change" do
    @james.update_start_time

    Delorean.time_travel_to(190.minutes.since) do
      @james.contest_finished?.should be_true

      change_users_contest_to("james", @contest_b, true)

      @james.contest_stat(true).forced_logout.should be_true
    end
  end

end
