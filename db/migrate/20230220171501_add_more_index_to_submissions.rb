class AddMoreIndexToSubmissions < ActiveRecord::Migration[7.0]
  def change
    add_index :submissions, :graded_at
  end
end
