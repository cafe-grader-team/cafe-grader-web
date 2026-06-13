class AddViewTestcaseToProblem < ActiveRecord::Migration[4.2]
  def change
    add_column :problems, :view_testcase, :bool
  end
end
