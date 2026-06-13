class OptimizeSubmissionIndices < ActiveRecord::Migration[7.0]
  def change
    remove_index :submissions, column: [:user_id,:problem_id]
    add_index :submissions, :problem_id
  end
end
