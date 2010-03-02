require File.dirname(__FILE__) + '/../test_helper'
require 'problems_controller'

# Re-raise errors caught by the controller.
class ProblemsController; def rescue_action(e) raise e end; end

class ProblemsControllerTest < ActionController::TestCase
  fixtures :problems

  def setup
    @controller = ProblemsController.new
    @request    = ActionController::TestRequest.new
    @response   = ActionController::TestResponse.new

    @first_id = problems(:first).id
  end

  def test_index
    get :index
    assert_response :success
    assert_template 'list'
  end

  def test_list
    get :list

    assert_response :success
    assert_template 'list'

    assert_not_nil assigns(:problems)
  end

  def test_show
    get :show, :id => @first_id

    assert_response :success
    assert_template 'show'

    assert_not_nil assigns(:problem)
    assert assigns(:problem).valid?
  end

  def test_new
    get :new

    assert_response :success
    assert_template 'new'

    assert_not_nil assigns(:problem)
  end

  def test_create
    num_problems = Problem.count

    post :create, :problem => {}

    assert_response :redirect
    assert_redirected_to :action => 'list'

    assert_equal num_problems + 1, Problem.count
  end

  def test_edit
    get :edit, :id => @first_id

    assert_response :success
    assert_template 'edit'

    assert_not_nil assigns(:problem)
    assert assigns(:problem).valid?
  end

  def test_update
    post :update, :id => @first_id
    assert_response :redirect
    assert_redirected_to :action => 'show', :id => @first_id
  end

  def test_destroy
    assert_nothing_raised {
      Problem.find(@first_id)
    }

    post :destroy, :id => @first_id
    assert_response :redirect
    assert_redirected_to :action => 'list'

    assert_raise(ActiveRecord::RecordNotFound) {
      Problem.find(@first_id)
    }
  end
end
