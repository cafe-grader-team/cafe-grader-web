class ChangeSubmissionSourceSize < ActiveRecord::Migration
  def change
    change_column :submissions, :source, :text, :limit => 1.megabyte
  end
end
