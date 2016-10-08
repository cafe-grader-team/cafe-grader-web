class ModifyGraderProcess < ActiveRecord::Migration
  def up
    change_column :grader_processes, :host, :string
  end

  def down
    change_column :grader_processes, :host, :string, limit: 20
  end
end
