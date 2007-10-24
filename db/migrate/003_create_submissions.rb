class CreateSubmissions < ActiveRecord::Migration
  def self.up
    create_table :submissions do |t|
      t.column :user_id, :integer
      t.column :problem_id, :integer
      t.column :language_id, :integer
      t.column :source, :text
      t.column :binary, :binary
      t.column :submitted_at, :datetime
      t.column :compiled_at, :datetime
      t.column :compiler_message, :text
      t.column :graded_at, :datetime
      t.column :points, :integer
      t.column :grader_comment, :text
    end
  end

  def self.down
    drop_table :submissions
  end
end
