class AddStatusToGraderProcess < ActiveRecord::Migration[7.0]
  def change
    add_column :grader_processes, :status, :integer, default: 0
  end
end
