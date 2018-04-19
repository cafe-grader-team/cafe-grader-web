class AddShowScoreToUsers < ActiveRecord::Migration
  def change
    add_column :users, :show_score, :boolean, :default => 1
  end
end
