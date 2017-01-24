class AddViewTestcaseToProblem < ActiveRecord::Migration
  def change
    add_column :problems, :view_testcase, :bool
  end
end
