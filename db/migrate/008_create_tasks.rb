class CreateTasks < ActiveRecord::Migration[4.2]
  def self.up
    create_table :tasks, options: "ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci" do |t|
      t.column 'submission_id', :integer
      t.column 'created_at', :datetime
    end
  end

  def self.down
    drop_table :tasks
  end
end
