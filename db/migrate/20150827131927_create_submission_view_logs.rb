class CreateSubmissionViewLogs < ActiveRecord::Migration[4.2]
  def change
    create_table :submission_view_logs, options: "ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci" do |t|
      t.integer :user_id
      t.integer :submission_id

      t.timestamps
    end
  end
end
