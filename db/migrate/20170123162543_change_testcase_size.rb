class ChangeTestcaseSize < ActiveRecord::Migration
  def change
    change_column :testcases, :input, :text, :limit => 4294967295
    change_column :testcases, :sol, :text, :limit => 4294967295
  end
end
