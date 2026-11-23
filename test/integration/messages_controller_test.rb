require "test_helper"

class MessagesControllerTest < ActionDispatch::IntegrationTest
  setup do
    @msg = Message.create!(sender: users(:john), receiver: users(:admin), body: "hello")
    @system_msg = Message.create!(sender: users(:john), receiver_id: nil, body: "system message")
  end

  # --- Authorization ---

  test "unauthenticated cannot list messages" do
    get messages_path
    assert_redirected_to_login
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

  # --- Body rendering ---
  #
  # Students type C++ into messages. Bare simple_format sanitized the body, so
  # `vector<int>` showed as `vector` on both the sender's and the admin's page.
  # Assert inside .message .body: the admin page's reply box is pre-filled with
  # the (already escaped) original, which would satisfy a whole-page match.

  test "the sender's message list shows brackets literally and never runs HTML" do
    Message.create!(sender: users(:john), receiver_id: nil, body: "my vector<int> v; fails when a<b\n<script>alert(1)</script>")
    sign_in_as("john", "hello")
    get messages_path
    assert_select ".message .body", text: %r{my vector<int> v; fails when a<b\s*<script>alert\(1\)</script>}
    assert_select ".message .body script", count: 0
  end

  test "the admin's message page shows brackets literally and never runs HTML" do
    msg = Message.create!(sender: users(:john), receiver_id: nil, body: "my vector<int> v; fails when a<b\n<script>alert(1)</script>")
    sign_in_as("admin", "admin")
    get message_path(msg)
    assert_select ".message .body", text: %r{my vector<int> v; fails when a<b\s*<script>alert\(1\)</script>}
    assert_select ".message .body script", count: 0
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
