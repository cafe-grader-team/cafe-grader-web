class AddIndexToSubmission < ActiveRecord::Migration[5.2]
  def change
    add_index :submissions, :submitted_at
  end
end
