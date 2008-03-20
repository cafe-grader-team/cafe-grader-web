require File.dirname(__FILE__) + '/../test_helper'
require 'main_controller'

# Re-raise errors caught by the controller.
class MainController; def rescue_action(e) raise e end; end

class MainControllerTest < Test::Unit::TestCase

  fixtures :problems
  fixtures :users

  def setup
    @controller = MainController.new
    @request    = ActionController::TestRequest.new
    @response   = ActionController::TestResponse.new
  end

  # Replace this with your real tests.
  def test_should_redirect_new_user_to_login
    get :list
    assert_redirected_to :action => 'login'
  end

  def test_should_list_available_problems_if_logged_in
    john = users(:john)
    get :list, {}, {:user_id => john.id}

    assert_template 'main/list'
    assert_select "table tr:nth-child(2)", :text => /\(add\)/
  end

end
