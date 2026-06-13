class AddTypeToSubmission < ActiveRecord::Migration[7.0]
  def change
    add_column :submissions, :tag, :integer, default: 0
    add_column :problems, :difficulty, :integer
  end
end
