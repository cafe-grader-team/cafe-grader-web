class CreateGraderMessages < ActiveRecord::Migration
  def self.up
    create_table :grader_messages do |t|
      t.integer :grader_process_id
      t.integer :command
      t.string :options
      t.integer :target_id
      t.boolean :taken
      t.integer :taken_grader_process_id
      t.timestamps
    end
  end

  def self.down
    drop_table :grader_messages
  end
end
