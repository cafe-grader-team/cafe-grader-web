class CreateTasks < ActiveRecord::Migration
  def self.up
    create_table :tasks do |t|
      t.column 'submission_id', :integer
      t.column 'created_at', :datetime
    end
  end

  def self.down
    drop_table :tasks
  end
end
