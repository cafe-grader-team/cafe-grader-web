class MoreNewEvaluation < ActiveRecord::Migration[7.0]
  def change
    rename_column :testcases, :score, :weight
  end
end
