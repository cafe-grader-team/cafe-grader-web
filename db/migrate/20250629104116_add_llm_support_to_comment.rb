class AddLlmSupportToComment < ActiveRecord::Migration[8.0]
  def change
    add_column :comments, :llm_response, :text, limit: 16.megabytes - 1
    add_column :comments, :llm_model, :string
  end
end
