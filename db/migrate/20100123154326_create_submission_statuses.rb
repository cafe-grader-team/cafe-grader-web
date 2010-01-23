class CreateSubmissionStatuses < ActiveRecord::Migration
  def self.up
    create_table :submission_statuses do |t|
      t.integer :user_id
      t.integer :problem_id
      t.boolean :passed
      t.integer :submission_count

      t.timestamps
    end
  end

  def self.down
    drop_table :submission_statuses
  end
end
