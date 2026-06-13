require "test_helper"

class CommentTest < ActiveSupport::TestCase
  # --- Validations ---

  test "title must be present" do
    comment = Comment.new(commentable: problems(:prob_add), user: users(:admin), kind: :hint)
    assert_not comment.valid?
    assert comment.errors[:title].any?
  end

  # --- Enums ---

  test "kind enum values" do
    comment = comments(:hint_for_add)
    assert comment.hint?
    assert comments(:solution_for_add).solution?
  end

  test "status enum values" do
    comment = comments(:hint_for_add)
    assert comment.ok?
  end

  # --- Scopes ---

  test "hints scope returns hint comments" do
    hints = Comment.hints
    assert_includes hints, comments(:hint_for_add)
    assert_not_includes hints, comments(:solution_for_add)
  end

  # --- Methods ---

  test "to_label returns kind and title" do
    comment = comments(:hint_for_add)
    assert_equal "hint: Hint for add", comment.to_label
  end

  test "set_default_hint_title sets title when blank" do
    comment = Comment.new(commentable: problems(:prob_add), user: users(:admin), kind: :hint)
    comment.set_default_hint_title
    assert_match(/Hint \d+/, comment.title)
  end

  test "set_default_hint_title does not overwrite existing title" do
    comment = comments(:hint_for_add)
    original_title = comment.title
    comment.set_default_hint_title
    assert_equal original_title, comment.title
  end

  # --- Associations ---

  test "comment belongs to commentable and user" do
    comment = comments(:hint_for_add)
    assert_equal problems(:prob_add), comment.commentable
    assert_equal users(:admin), comment.user
  end
end
