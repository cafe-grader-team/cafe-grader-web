class AddIsPrivateToTestPairs < ActiveRecord::Migration
  def change
    add_column :test_pairs, :is_private, :boolean
  end
end
