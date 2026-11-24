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

  test "backfill_llm_usage! reads token counts out of the stored provider response" do
    c = submissions(:add1_by_john).comments.create!(
      user: users(:john), kind: 'llm_assist', status: 'ok', title: 't', body: 'b', cost: 10,
      llm_response: {choices: [], usage: {prompt_tokens: 11, completion_tokens: 7}}.to_json)
    assert c.backfill_llm_usage!
    c.reload
    assert_equal [11, 7], [c.prompt_tokens, c.completion_tokens]
    c.update_columns(llm_response: 'not json', prompt_tokens: nil)
    refute c.backfill_llm_usage!
    assert_nil c.reload.prompt_tokens
  end

  # --- AI-assist roll-up (stat pages) ---

  def assist(sub, model, status: 'ok', cost: 10, llm_cost: nil, tokens: nil, user: users(:john))
    Comment.create!(commentable: sub, user: user, kind: 'llm_assist', status: status, llm_model: model, cost: cost,
                    llm_cost: llm_cost, prompt_tokens: tokens&.first, completion_tokens: tokens&.last,
                    title: "Assistance by #{model}")
  end

  test "llm_assists_on attributes requests to the submission's owner, whoever pressed Get" do
    mine  = assist(submissions(:add1_by_john), 'm1', user: users(:admin))   # admin asked on john's behalf
    other = assist(submissions(:add1_by_james), 'm1')
    rows = Comment.llm_assists_on(Submission.where(user: users(:john)))
    assert_includes rows, mine
    assert_not_includes rows, other
  end

  test "usage_by_model: one row per model, heaviest first, with answers, points, priced dollars and tokens" do
    sub = submissions(:add1_by_john)
    assist(sub, 'm1', llm_cost: 0.5, tokens: [1000, 200])
    assist(sub, 'm1', status: 'processing', cost: 0)   # in flight: no charge yet, unpriced
    assist(sub, 'm2', tokens: [3000, 400])               # a provider without a cost source
    rows = Comment.llm_assists_on(Submission.where(user: users(:john))).usage_by_model
    assert_equal %w[m1 m2], rows.map(&:model)
    m1, m2 = rows
    assert_equal [2, 1, 10.0, 1, 1000, 200], [m1.requests, m1.answered, m1.points, m1.priced, m1.prompt_tokens, m1.completion_tokens]
    assert_in_delta 0.5, m1.dollars.to_f, 1e-9
    assert_equal [1, 1, 10.0, 0], [m2.requests, m2.answered, m2.points, m2.priced]
    assert_nil m2.dollars
  end
end
