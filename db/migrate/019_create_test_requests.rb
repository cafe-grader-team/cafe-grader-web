class CreateTestRequests < ActiveRecord::Migration[4.2]
  def self.up
    create_table :test_requests, options: "ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci" do |t|
      t.column :user_id, :integer
      t.column :problem_id, :integer
      t.column :submission_id, :integer
      t.column :input_file_name, :string
      t.column :output_file_name, :string
      t.column :running_stat, :string

      # these are similar to tasks
      t.column :status, :integer

      # these are intentionally similar to submissions
      t.column :submitted_at, :datetime
      t.column :compiled_at, :datetime
      t.column :compiler_message, :string
      t.column :graded_at, :datetime
      t.column :grader_comment, :string
      t.timestamps
    end
    add_index :test_requests, [:user_id, :problem_id]
  end

  def self.down
    remove_index :test_requests, :column => [:user_id, :problem_id]
    drop_table :test_requests
  end
end
