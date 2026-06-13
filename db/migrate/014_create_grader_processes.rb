class CreateGraderProcesses < ActiveRecord::Migration[4.2]
  def self.up
    create_table :grader_processes, options: "ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci" do |t|
      t.column :ip, :string, :limit => 20
      t.column :pid, :integer
      t.column :mode, :string
      t.column :active, :boolean
      t.timestamps
    end
    add_index :grader_processes, ["ip","pid"]
  end

  def self.down
    drop_table :grader_processes
  end
end
