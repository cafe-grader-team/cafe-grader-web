class ModifyGraderProcess < ActiveRecord::Migration[4.2]
  def up
    change_column :grader_processes, :host, :string
  end

  def down
    change_column :grader_processes, :host, :string, limit: 20
  end
end
