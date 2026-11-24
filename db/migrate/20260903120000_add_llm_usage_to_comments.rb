class AddLlmUsageToComments < ActiveRecord::Migration[8.0]
  # `comments.cost` is the SCORE penalty a student pays for an AI assist (10
  # points). These three are the provider's own accounting for the call:
  # dollars (from the gateway's cost header / body — nil where the provider
  # reports none) and token counts. Rows written before this migration can
  # have their tokens recovered from the stored response with
  # `rake comments:backfill_llm_usage`; the dollar figure cannot.
  def change
    add_column :comments, :llm_cost, :decimal, precision: 12, scale: 6
    add_column :comments, :prompt_tokens, :integer
    add_column :comments, :completion_tokens, :integer
  end
end
