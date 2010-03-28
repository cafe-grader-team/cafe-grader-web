require 'spec_helper'
require 'config_spec_helper'
require 'delorean'

describe "ContestManagements" do
  include ConfigSpecHelperMethods

  fixtures :users
  fixtures :problems
  fixtures :contests
  fixtures :roles

  before(:each) do
    @admin_user = users(:mary)
    @contest_b = contests(:contest_b)
    @james = users(:james)
    @jack = users(:jack)

    set_contest_time_limit('3:00')
    set_indv_contest_mode
    enable_multicontest
  end

  it "should reset users' timer when their contests change" do
    james_session = open_session
    james_session.extend(MainSessionMethods)

    james_login_and_get_main_list(james_session)
    james_session.response.should_not have_text(/OVER/)

    Delorean.time_travel_to(190.minutes.since) do
      james_session.get_main_list
      james_session.response.should have_text(/OVER/)

      james_session.get '/'                   # logout
      james_session.get '/main/list'          # clearly log out
      james_session.response.should_not render_template 'main/list'

      admin_change_users_contest_to("james", @contest_b, true)

      james_login_and_get_main_list(james_session)
      james_session.response.should_not have_text(/OVER/)
    end
  end

  it "should force users to log out when their contests change" do
    james_session = open_session
    james_session.extend(MainSessionMethods)

    james_login_and_get_main_list(james_session)
    james_session.response.should_not have_text(/OVER/)

    Delorean.time_travel_to(190.minutes.since) do
      james_session.get_main_list
      james_session.response.should have_text(/OVER/)

      admin_change_users_contest_to("james", @contest_b, true)

      james_session.get '/main/list'
      james_session.response.should_not render_template 'main/list'
      james_session.should be_redirect

      Delorean.time_travel_to(200.minutes.since) do
        james_login_and_get_main_list(james_session)
        james_session.response.should_not have_text(/OVER/)
      end
    end
  end

  private

  module MainSessionMethods
    def login(login_name, password)
      post '/login/login', :login => login_name, :password => password
      assert_redirected_to '/main/list'
    end

    def get_main_list
      get '/main/list'
      assert_template 'main/list'
    end

    def get_main_list_and_assert_logout
      get '/main/list'
      assert_redirected_to '/main'
    end
  end

  module ContestManagementSessionMethods
    def change_users_contest_to(user_login_list, contest, reset_timer=false)
      post_data = {
        :contest => {:id => contest.id},
        :operation => 'assign',
        :login_list => user_login_list
      }
      post_data[:reset_timer] = true if reset_timer
      post '/user_admin/manage_contest', post_data
    end
  end

  def admin_change_users_contest_to(user_list, contest, reset_timer)
    admin_session = open_session
    admin_session.extend(MainSessionMethods)
    admin_session.extend(ContestManagementSessionMethods)
    
    admin_session.login('mary','goodbye')
    admin_session.get '/main/list'
    admin_session.change_users_contest_to(user_list, contest, reset_timer)
  end

  def james_login_and_get_main_list(session)
    session.login('james', 'morning')
    session.get_main_list
  end

end

