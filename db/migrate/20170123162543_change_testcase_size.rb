class ChangeTestcaseSize < ActiveRecord::Migration[4.2]
  def change
    change_column :testcases, :input, :text, :limit => 4294967295
    change_column :testcases, :sol, :text, :limit => 4294967295
  end
end
