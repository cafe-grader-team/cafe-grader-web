require "test_helper"

class MessagesControllerTest < ActionDispatch::IntegrationTest
  setup do
    @msg = Message.create!(sender: users(:john), receiver: users(:admin), body: "hello")
    @system_msg = Message.create!(sender: users(:john), receiver_id: nil, body: "system message")
  end

  # --- Authorization ---

  test "unauthenticated cannot list messages" do
    get messages_path
    assert_redirected_to login_main_path
  end

  test "normal user can list own messages" do
    sign_in_as("john", "hello")
    get messages_path
    assert_response :success
  end

  test "normal user cannot access admin console" do
    sign_in_as("john", "hello")
    get console_messages_path
    assert_redirected_to list_main_path
  end

  test "normal user cannot show a message (admin only)" do
    sign_in_as("john", "hello")
    get message_path(@msg)
    assert_redirected_to list_main_path
  end

  test "normal user cannot list_all" do
    sign_in_as("john", "hello")
    get list_all_messages_path
    assert_redirected_to list_main_path
  end

  test "normal user cannot reply" do
    sign_in_as("john", "hello")
    post reply_message_path(@msg), params: { message: { body: "trying to reply" } }
    assert_redirected_to list_main_path
  end

  test "normal user cannot hide" do
    sign_in_as("john", "hello")
    get hide_message_path(@msg)
    assert_redirected_to list_main_path
  end

  # --- Admin paths ---

  test "admin can access console" do
    sign_in_as("admin", "admin")
    get console_messages_path
    assert_response :success
  end

  test "admin can list_all" do
    sign_in_as("admin", "admin")
    get list_all_messages_path
    assert_response :success
  end

  test "admin can show a message" do
    sign_in_as("admin", "admin")
    get message_path(@msg)
    assert_response :success
  end

  test "admin can hide a message" do
    sign_in_as("admin", "admin")
    get hide_message_path(@msg)
    assert_redirected_to action: "console"
    assert @msg.reload.replied
  end
end
