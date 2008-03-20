require File.dirname(__FILE__) + '/../test_helper'
require 'user_admin_controller'

# Re-raise errors caught by the controller.
class UserAdminController; def rescue_action(e) raise e end; end

class UserAdminControllerTest < Test::Unit::TestCase
  fixtures :users
  fixtures :roles
  fixtures :rights

  def setup
    @controller = UserAdminController.new
    @request    = ActionController::TestRequest.new
    @response   = ActionController::TestResponse.new

    @first_id = users(:john).id
    @admin_id = users(:mary).id
  end

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
    assert_template 'user_admin/list'
  end


  def test_index
    get :index, {}, {:user_id => @admin_id}
    assert_response :success
    assert_template 'list'
  end

  def test_list
    get :list, {}, {:user_id => @admin_id}

    assert_response :success
    assert_template 'list'

    assert_not_nil assigns(:users)
  end

  def test_show
    get :show, {:id => @first_id}, {:user_id => @admin_id}

    assert_response :success
    assert_template 'show'

    assert_not_nil assigns(:user)
  end

  def test_new
    get :new, {}, {:user_id => @admin_id}

    assert_response :success
    assert_template 'new'

    assert_not_nil assigns(:user)
  end

  def test_create_with_correct_confirmation_password
    num_users = User.count

    post :create, {:user => {
        :login => 'test',
        :full_name => 'hello',
        :password => 'abcde',
        :password_confirmation => 'abcde'
      }}, {:user_id => @admin_id}

    assert_response :redirect
    assert_redirected_to :action => 'list'

    assert_equal num_users + 1, User.count
  end

  def test_create_with_wrong_confirmation_password
    num_users = User.count

    post :create, {:user => {
        :login => 'test',
        :full_name => 'hello',
        :password => 'abcde',
        :password_confirmation => 'abcdef'
      }}, {:user_id => @admin_id}

    assert_response :success
    assert_template 'new'

    assert_equal num_users, User.count
  end

  def test_edit
    get :edit, {:id => @first_id}, {:user_id => @admin_id}

    assert_response :success
    assert_template 'edit'

    assert_not_nil assigns(:user)
  end

  def test_update
    post :update, {
      :id => @first_id,
      :user => {
        :login => 'test',
        :full_name => 'hello',
        :password => 'abcde',
        :password_confirmation => 'abcde'
      }
    }, {:user_id => @admin_id}
    assert_response :redirect
    assert_redirected_to :action => 'show', :id => @first_id
  end

  def test_destroy
    assert_nothing_raised {
      User.find(@first_id)
    }

    post :destroy, {:id => @first_id}, {:user_id => @admin_id}
    assert_response :redirect
    assert_redirected_to :action => 'list'

    assert_raise(ActiveRecord::RecordNotFound) {
      User.find(@first_id)
    }
  end
end
