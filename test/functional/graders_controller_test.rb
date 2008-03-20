require File.dirname(__FILE__) + '/../test_helper'

class GradersControllerTest < ActionController::TestCase

  fixtures :users, :roles, :rights

  def test_should_not_allow_new_user_to_see
    get :list
    assert_redirected_to :controller => 'main', :action => 'login'
  end

  def test_should_not_allow_normal_user_to_see
    john = users(:john)

    get :list, {}, {:user_id => john.id}
    assert_redirected_to :controller => 'main', :action => 'login'
  end

  def test_should_allow_admin_to_see
    mary = users(:mary)

    get :list, {}, {:user_id => mary.id}
    assert_template 'graders/list'
  end

end
