require File.dirname(__FILE__) +  '/../test_helper'

class MainControllerTest < ActionController::TestCase
  fixtures :users
  fixtures :problems

  def test_should_redirect_new_user_to_login
    get :list
    assert_redirected_to :controller => 'main', :action => 'login'
  end

  def test_should_list_available_problems_if_logged_in
    john = users(:john)
    get :list, {}, {:user_id => john.id}

    assert_template 'main/list'
    assert_select "table tr:nth-child(2)", :text => /\(add\)/
  end

end
