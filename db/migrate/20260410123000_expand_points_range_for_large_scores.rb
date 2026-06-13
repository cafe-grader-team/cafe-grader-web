class ExpandPointsRangeForLargeScores < ActiveRecord::Migration[8.0]
  def up
    change_column :submissions, :points, :decimal, precision: 16, scale: 6
    change_column :score_submissions, :points, :decimal, precision: 16, scale: 6 if table_exists?(:score_submissions) && column_exists?(:score_submissions, :points)
    change_column :score_users, :points, :decimal, precision: 16, scale: 6 if table_exists?(:score_users) && column_exists?(:score_users, :points)
  end

  def down
    change_column :submissions, :points, :decimal, precision: 8, scale: 4
    change_column :score_submissions, :points, :decimal, precision: 8, scale: 4 if table_exists?(:score_submissions) && column_exists?(:score_submissions, :points)
    change_column :score_users, :points, :decimal, precision: 8, scale: 4 if table_exists?(:score_users) && column_exists?(:score_users, :points)
  end
end
