# Viva test-drive sessions (design D7, spec 2026-09-23): an editor/admin sits
# their own viva in a session flagged test_drive. Graded like a real session;
# excluded from every student-facing list, quota and report via
# Submission.regular. Appended boolean with a default = instant DDL on MySQL 8.
class AddTestDriveToSubmissions < ActiveRecord::Migration[8.0]
  def change
    add_column :submissions, :test_drive, :boolean, null: false, default: false
  end
end
