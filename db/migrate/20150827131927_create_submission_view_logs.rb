class CreateSubmissionViewLogs < ActiveRecord::Migration
  def change
    create_table :submission_view_logs do |t|
      t.integer :user_id
      t.integer :submission_id

      t.timestamps
    end
  end
end
