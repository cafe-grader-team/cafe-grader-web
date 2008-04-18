require File.dirname(__FILE__) + '/../test_helper'

class AnnouncementsControllerTest < ActionController::TestCase
  def test_should_get_index
    get :index
    assert_response :success
    assert_not_nil assigns(:announcements)
  end

  def test_should_get_new
    get :new
    assert_response :success
  end

  def test_should_create_announcement
    assert_difference('Announcement.count') do
      post :create, :announcement => { }
    end

    assert_redirected_to announcement_path(assigns(:announcement))
  end

  def test_should_show_announcement
    get :show, :id => announcements(:one).id
    assert_response :success
  end

  def test_should_get_edit
    get :edit, :id => announcements(:one).id
    assert_response :success
  end

  def test_should_update_announcement
    put :update, :id => announcements(:one).id, :announcement => { }
    assert_redirected_to announcement_path(assigns(:announcement))
  end

  def test_should_destroy_announcement
    assert_difference('Announcement.count', -1) do
      delete :destroy, :id => announcements(:one).id
    end

    assert_redirected_to announcements_path
  end
end
