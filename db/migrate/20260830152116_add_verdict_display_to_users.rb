class AddVerdictDisplayToUsers < ActiveRecord::Migration[8.0]
  def change
    # How the user wants Submission#grader_comment rendered everywhere:
    # 0 = tiles (colour-coded verdict strip, the default), 1 = plain text
    # (the pre-4.5 monospace string). Enum on User (verdict_display).
    add_column :users, :verdict_display, :integer, limit: 1, default: 0, null: false
  end
end
