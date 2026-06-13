class ChangeSubmissionSourceSize < ActiveRecord::Migration[4.2]
  def change
    change_column :submissions, :source, :text, :limit => 1.megabyte
  end
end
