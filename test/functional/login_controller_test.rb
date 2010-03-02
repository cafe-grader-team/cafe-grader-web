require File.dirname(__FILE__) + '/../test_helper'
require 'login_controller'

# Re-raise errors caught by the controller.
class LoginController; def rescue_action(e) raise e end; end

class LoginControllerTest < ActionController::TestCase

  fixtures :users

  def setup
    @controller = LoginController.new
    @request    = ActionController::TestRequest.new
    @response   = ActionController::TestResponse.new
  end

  # Replace this with your real tests.
  def test_should_hide_index
    get :index
    assert_redirected_to :controller => 'main', :action => 'login'
  end

  def test_should_login_user_and_set_session
    john = users(:john)

    post :login, :login => 'john', :password => "hello"
    assert_redirected_to :controller => 'main', :action => 'list'
    assert_equal john.id, session[:user_id]
  end

  def test_should_reject_user_with_wrong_password
    john = users(:john)

    post :login, :login => 'john', :password => "wrong"
    assert_redirected_to :controller => 'main', :action => 'login'
  end
end
