class AddVivaRetakeGrantToSubmissions < ActiveRecord::Migration[8.0]
  # "Allow another attempt" (design 2026-10-07, A4): a staff grant marks a
  # viva session as no longer counting toward the start limit, so the student
  # can start one more. Two nullable columns — MySQL 8.0 adds them INSTANT,
  # without copying the (large) submissions table.
  def change
    add_column :submissions, :viva_retake_granted_at, :datetime, precision: 6
    add_column :submissions, :viva_retake_granted_by_id, :integer
  end
end
