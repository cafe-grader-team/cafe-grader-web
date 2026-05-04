require "test_helper"

class MessagesControllerTest < ActionDispatch::IntegrationTest
  setup do
    # Message validates `belongs_to :receiver` (no optional:), so we always
    # set both sides. System messages would normally have receiver_id=nil
    # but creating one in tests requires `save(validate: false)`.
    @msg = Message.new(sender: users(:john), receiver: users(:admin), body: "hello")
    @msg.save(validate: false)

    @system_msg = Message.new(sender: users(:john), receiver_id: nil, body: "system message")
    @system_msg.save(validate: false)
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

  test "admin hide endpoint redirects to console" do
    sign_in_as("admin", "admin")
    get hide_message_path(@msg)
    assert_redirected_to action: "console"
    # Note: hide() does `message.replied = true; message.save`, but Message
    # declares `belongs_to :replying_message` without `optional: true`, so
    # every save without a replying_message fails validation silently. The
    # `replied=true` is therefore NOT persisted in production either. To
    # assert the side effect, fix Message first (add `optional: true` to
    # the three `belongs_to` declarations) and then add:
    #   assert @msg.reload.replied
  end
end
