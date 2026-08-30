class AddRepairedFromIdToSubmissions < ActiveRecord::Migration[8.0]
  def change
    add_column :submissions, :repaired_from_id, :integer
    add_index :submissions, :repaired_from_id
  end
end
