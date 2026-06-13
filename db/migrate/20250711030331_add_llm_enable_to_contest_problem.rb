class AddLlmEnableToContestProblem < ActiveRecord::Migration[8.0]
  def change
    add_column :contests_problems, :allow_llm, :boolean, default: false
  end
end
