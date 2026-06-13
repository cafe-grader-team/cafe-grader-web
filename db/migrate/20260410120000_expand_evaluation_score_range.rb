class ExpandEvaluationScoreRange < ActiveRecord::Migration[8.0]
  def up
    change_column :evaluations, :score, :decimal, precision: 16, scale: 6
  end

  def down
    change_column :evaluations, :score, :decimal, precision: 8, scale: 6
  end
end
