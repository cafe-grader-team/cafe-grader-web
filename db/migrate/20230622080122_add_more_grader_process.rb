class AddMoreGraderProcess < ActiveRecord::Migration[7.0]
  def change
    create_table :worker_datasets do |t|
      t.references :worker
      t.references :dataset
      t.integer :status, limit: 1, default: 0
      t.timestamps
    end

    add_column :grader_processes, :worker_id, :integer
    add_column :grader_processes, :box_id, :integer
    add_column :grader_processes, :last_heartbeat, :datetime
    add_column :grader_processes, :key, :string
    add_column :grader_processes, :enabled, :boolean, default: false
  end
end
