class CreateGraderProcesses < ActiveRecord::Migration
  def self.up
    create_table :grader_processes do |t|
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
