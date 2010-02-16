require 'test_helper'

class ContestsControllerTest < ActionController::TestCase
  test "should get index" do
    get :index
    assert_response :success
    assert_not_nil assigns(:contests)
  end

  test "should get new" do
    get :new
    assert_response :success
  end

  test "should create contest" do
    assert_difference('Contest.count') do
      post :create, :contest => { }
    end

    assert_redirected_to contest_path(assigns(:contest))
  end

  test "should show contest" do
    get :show, :id => contests(:one).to_param
    assert_response :success
  end

  test "should get edit" do
    get :edit, :id => contests(:one).to_param
    assert_response :success
  end

  test "should update contest" do
    put :update, :id => contests(:one).to_param, :contest => { }
    assert_redirected_to contest_path(assigns(:contest))
  end

  test "should destroy contest" do
    assert_difference('Contest.count', -1) do
      delete :destroy, :id => contests(:one).to_param
    end

    assert_redirected_to contests_path
  end
end
